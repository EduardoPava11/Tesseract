// DNGCaptureManager.swift
// Tesseract
//
// Rear-camera session + 64-frame plain-Bayer RAW burst state machine,
// restored from archive/rear-rgbt RGBTCaptureManager and reworked for the
// DNG streaming pipeline: per captured frame, IN the capture callback
// chain (process then drop the pixel buffer, peak raw residency ≤ 2
// buffers — the archive's proven fire-next-then-process overlap):
//
//   Bayer CVPixelBuffer
//     → normalize to RGGB float mosaic (black-sub, WB, latched exposure,
//       sRGB OETF — matches DebayerNet's sRGB-encoded training domain)
//     → MetalPipeline.debayerToRung (DebayerNet f16 + boxReduceRGB)
//     → DNGPipeline.processFrame (palette quantize + binomial histogram)
//     → store ONLY the S² UInt8 index frame; the 25.5 MB buffer dies here.
//
// The photon-time path (PhotonTime / BayerCellReducer) stays archived.
//
// Session lessons carried over verbatim (all device-verified):
//   • .photo preset, NO 48MP dance — binned 4224×3024 12-bit readout.
//   • AVCapturePhotoSettings(rawPixelFormatType:) with NO rawFileType —
//     photo.pixelBuffer IS the raw Bayer plane; DNG bytes never exist.
//   • .speed prioritization per shot (.balanced traps with Bayer RAW).
//   • never iterate device.formats (video-only formats trap on iOS 26).
//   • AE/AWB/focus locked across the burst: ONE exposure.

@preconcurrency import AVFoundation
import Combine
import CoreMedia
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tesseract.app", category: "DNGCapture")

// MARK: - Frame payload (delegate → pipeline, ownership transferred)

/// Ownership transferred: exactly one consumer (processPayload), never shared.
struct RawFramePayload: @unchecked Sendable {
    let slot: Int
    let buffer: CVPixelBuffer
    let meta: FrameMeta
    let hwTimestampNs: Int64
}

struct FrameMeta: Sendable {
    /// 4 entries, [R, Gr, Gb, B] order after CFA mapping; fallback 528 each.
    let blackLevel: [Double]
    /// Fallback 4095 (12-bit in 16-bit container, TENET-verified).
    let whiteLevel: Double
    /// AsShotNeutral, 3 entries; gains derived later. Fallback [1,1,1].
    let wbNeutral: [Double]
    let exposureSec: Double
    let iso: Int
    let cfa: OSType
    let width: Int
    let height: Int
    let bytesPerRow: Int
}

/// One processed slot: everything the finish pass needs, nothing raw.
struct DNGFrameSlot: Sendable {
    let slot: Int
    let indices: [UInt8]
    let counts: [Int]
    let binomial: DNGBinomialStats
    let hwTimestampNs: Int64
    let meta: FrameMeta
    let nativeSide: Int
}

// MARK: - Manager

final class DNGCaptureManager: NSObject, ObservableObject, @unchecked Sendable {

    enum State: Sendable, Equatable {
        case idle
        case configuring
        case ready
        case capturing(frame: Int)            // 0..63 completed count
        case processing(progress: Float, phase: String)
        case done(DNGResult)
        case error(String)
    }

    @Published private(set) var state: State = .idle

    /// Live per-frame binomial readout ("see the colors in the binomial
    /// distribution") — updated from the streaming pipeline during capture.
    @Published private(set) var liveBinomial: DNGBinomialStats?

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.tesseract.dng.session")
    private var photoOutput: AVCapturePhotoOutput?
    private var currentDevice: AVCaptureDevice?
    private var rawFormat: OSType?
    private var runtimeErrorObserver: (any NSObjectProtocol)?

    /// First-frame pixel-format latch (SixFour): every later frame must match.
    private var latchedFormat: OSType?

    /// Stamps each pipeline run; a late completion whose generation != current
    /// is discarded (SixFour generation-tag lesson).
    private var burstGeneration = 0

    /// Metal state for debayer + rung reduce. Created lazily on the first
    /// burst; only ever touched from the serial processing chain.
    private var metal: MetalPipeline?

    /// Exposure normalization scale, latched from the first processed frame
    /// (p99.5 of its linear G — streaming-friendly; AE is locked so one
    /// anchor is valid for the whole burst). Reset per burst.
    private var exposureScale: Double?

    /// Rung latched at shutter press (the picker is disabled mid-burst).
    private var activeRung: DNGRung = DNGConfig.rung

    /// Preview layer owned by the manager (survives view teardown/recreate).
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        return layer
    }()

    // Retain delegates until their callbacks fire, keyed by settings uniqueID.
    private var pendingDelegates: [Int64: DNGPhotoDelegate] = [:]
    private let delegatesLock = NSLock()

    // MARK: - Configure

    func configure() {
        sessionQueue.async { [weak self] in
            self?.configureOnQueue()
        }
    }

    private func configureOnQueue() {
        // Re-entrancy guard (idempotent configure — BOREAL err=-17281
        // double-configure lesson). Benign cross-thread enum read.
        switch state {
        case .configuring, .ready, .capturing, .processing, .done:
            return
        case .idle, .error:
            break
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configure()
                } else {
                    self.setState(.error("Camera permission denied"))
                }
            }
            return
        case .denied, .restricted:
            setState(.error("Camera permission denied"))
            return
        @unknown default:
            setState(.error("Camera permission denied"))
            return
        }

        setState(.configuring)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // .photo preset deliberately yields the binned 4224×3024 12MP format.
        // No 48MP dance, no .inputPriority (48MP cannot sustain a 64-burst;
        // full 48MP is out of scope this round).
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else {
            setState(.error("No rear camera"))
            return
        }
        self.currentDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                setState(.error("Cannot add camera input"))
                return
            }
            session.addInput(input)
        } catch {
            setState(.error(error.localizedDescription))
            return
        }

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            setState(.error("Cannot add photo output"))
            return
        }
        session.addOutput(output)
        self.photoOutput = output

        // NEVER iterate device.formats or read per-format properties — on
        // iPhone 17 Pro / iOS 26 several video-only formats trap the Swift
        // runtime when their properties are accessed (BOREAL, device-verified).
        output.maxPhotoQualityPrioritization = .quality        // ceiling only
        // ProRAW must stay OFF: leave output.isAppleProRAWEnabled = false (default).
        guard let bayer = output.availableRawPhotoPixelFormatTypes
                .first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) })
        else {
            setState(.error("No plain-Bayer RAW format"))
            return
        }
        // Expected 'bgg4' (BGGR) on iPhone 17 Pro; do NOT hardcode.
        self.rawFormat = bayer
        logger.info("DNG: plain-Bayer RAW format \(fourCCString(bayer))")

        // Fig/XPC errors like -17281 are otherwise invisible (BOREAL).
        if runtimeErrorObserver == nil {
            runtimeErrorObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil
            ) { note in
                let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
                logger.error("DNG: session runtime error: \(String(describing: err))")
            }
        }

        // Commit happens via defer, THEN start as a follow-up on the same queue.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            // Pre-allocate ISP buffers for the RAW path (sixteen3 lesson).
            if let output = self.photoOutput, let raw = self.rawFormat {
                output.setPreparedPhotoSettingsArray(
                    [AVCapturePhotoSettings(rawPixelFormatType: raw)],
                    completionHandler: nil
                )
            }
            self.setState(.ready)
        }
    }

    func retry() {
        teardown()
        sessionQueue.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.configure()
            }
        }
    }

    // MARK: - Lifecycle

    /// Fully releases the camera: stops running, removes all inputs/outputs,
    /// drops device/output refs, resets state. Next configure() builds fresh.
    func teardown() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
            self.photoOutput = nil
            self.currentDevice = nil
            self.rawFormat = nil
            self.latchedFormat = nil
            self.metal?.releaseDebayerResources()
            if let obs = self.runtimeErrorObserver {
                NotificationCenter.default.removeObserver(obs)
                self.runtimeErrorObserver = nil
            }
            self.setState(.idle)
        }
    }

    /// Frees the session's ISP buffers (~100 MB) before the finish pass,
    /// but keeps currentDevice so the deferred AE unlock still has a target.
    private func teardownSessionForCompute() async {
        await onSessionQueue {
            if self.session.isRunning { self.session.stopRunning() }
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
            self.photoOutput = nil
            self.rawFormat = nil
        }
    }

    // MARK: - AE/AWB/focus lock

    /// Cross-frame comparability requires ONE exposure across the burst
    /// (the exposure anchor is latched from frame 0). Runs on sessionQueue.
    private func lockExposureOnQueue(timeoutMs: Int) {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            device.unlockForConfiguration()
        } catch {
            logger.error("DNG: lockExposure lockForConfiguration failed: \(error.localizedDescription)")
            return
        }
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while (device.isAdjustingExposure || device.isAdjustingWhiteBalance || device.isAdjustingFocus)
                && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.015)
        }
        if Date() >= deadline {
            logger.warning("DNG: AE/AWB/AF settle timed out after \(timeoutMs) ms — proceeding")
        }
    }

    private func unlockExposureOnQueue() {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch {
            logger.error("DNG: unlockExposure failed: \(error.localizedDescription)")
        }
    }

    private func onSessionQueue(_ body: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                body()
                cont.resume()
            }
        }
    }

    // MARK: - Burst

    static let burstFrames = DNGConfig.burstFrames
    private static let maxSkippedSlots = 4

    func captureBurst() async {
        guard case .ready = state, let output = photoOutput, let raw = rawFormat else {
            logger.warning("DNG: captureBurst called but not ready")
            return
        }
        burstGeneration += 1
        let generation = burstGeneration
        latchedFormat = nil
        exposureScale = nil
        activeRung = DNGConfig.rung
        DispatchQueue.main.async { [weak self] in self?.liveBinomial = nil }

        await onSessionQueue { self.lockExposureOnQueue(timeoutMs: 400) }
        // Every exit path restores AE (device ref survives compute teardown).
        defer { sessionQueue.async { self.unlockExposureOnQueue() } }

        let n = Self.burstFrames
        var slots: [DNGFrameSlot?] = Array(repeating: nil, count: n)
        var pending: (slot: Int, task: Task<DNGFrameSlot?, Never>)? = nil
        var skipped = 0

        for slot in 0..<n {
            setState(.capturing(frame: slot))
            // Fire-next-then-process overlap: the previous frame's debayer +
            // quantize runs while this shot is in flight. Pipeline depth:
            // 1 processing + 1 capture → raw residency ≤ 2 CVPixelBuffers.
            var payload = await captureOne(slot: slot, output: output, rawFormat: raw, timeoutSec: 5)

            if let p = pending {
                slots[p.slot] = await p.task.value
                pending = nil
            }

            if let got = payload {
                if latchedFormat == nil {
                    // First-frame pixel-format latch (SixFour). Abort loudly.
                    if let err = verifyFirstFrame(got, requested: raw) {
                        setState(.error(err))
                        return
                    }
                    latchedFormat = got.meta.cfa
                } else if got.meta.cfa != latchedFormat {
                    logger.error("DNG: slot \(slot) CFA changed mid-burst: \(fourCCString(got.meta.cfa)) != \(fourCCString(self.latchedFormat ?? 0)) — dropping slot")
                    payload = nil
                }
            }

            if let payload {
                let rung = activeRung
                pending = (slot, Task.detached(priority: .userInitiated) { [weak self] in
                    self?.processPayload(payload, rung: rung)   // consumes the CVPixelBuffer
                })
            } else {
                skipped += 1
                logger.warning("DNG: slot \(slot) dropped (\(skipped) total)")
                if skipped > Self.maxSkippedSlots {
                    setState(.error("burst failed: \(skipped) dropped slots"))
                    return
                }
                // A dropped slot never blocks the burst (BOREAL); it is
                // duplicated from a neighbor in the fill pass below.
            }
        }
        if let p = pending {
            slots[p.slot] = await p.task.value
        }

        // Fill: forward-fill from the previous good slot; leading nils take
        // the first good slot. Processing failures count as skips too.
        guard let firstGood = slots.firstIndex(where: { $0 != nil }) else {
            setState(.error("burst failed: no frames processed"))
            return
        }
        for i in 0..<firstGood { slots[i] = slots[firstGood] }
        for i in 1..<n where slots[i] == nil { slots[i] = slots[i - 1] }
        let filled = slots.compactMap { $0 }
        let duplicated = filled.count == n ? zip(filled, filled.indices).filter { $0.0.slot != $0.1 }.count : 0
        logBurstTiming(filled)

        // stopRunning + remove IO frees ~100 MB of ISP buffers, and the
        // debayer GPU buffers (~150 MB) are done too, before the finish pass.
        await teardownSessionForCompute()
        metal?.releaseDebayerResources()
        runFinish(filled, skippedSlots: max(skipped, duplicated), generation: generation)
    }

    /// nil error message when OK. Checks the actual buffer format is a known
    /// Bayer fourCC AND equals the requested format.
    private func verifyFirstFrame(_ payload: RawFramePayload, requested: OSType) -> String? {
        let known: Set<OSType> = [
            kCVPixelFormatType_14Bayer_RGGB,
            kCVPixelFormatType_14Bayer_BGGR,
            kCVPixelFormatType_14Bayer_GRBG,
            kCVPixelFormatType_14Bayer_GBRG
        ]
        let actual = payload.meta.cfa
        guard known.contains(actual) else {
            return "frame 0: unexpected pixel format \(fourCCString(actual)) (not plain Bayer)"
        }
        guard actual == requested else {
            return "frame 0: format \(fourCCString(actual)) != requested \(fourCCString(requested))"
        }
        logger.info("DNG: frame 0 latch OK — \(fourCCString(actual)) \(payload.meta.width)×\(payload.meta.height)")
        return nil
    }

    /// Measure-and-warn only, never reject (SixFour BurstTiming policy).
    private func logBurstTiming(_ slots: [DNGFrameSlot]) {
        let ts = slots.map { Double($0.hwTimestampNs) / 1e9 }
        guard ts.count > 1 else { return }
        let intervals = zip(ts.dropFirst(), ts).map { $0 - $1 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let maxI = intervals.max() ?? 0
        logger.info("DNG: burst timing — mean \(mean * 1000, format: .fixed(precision: 1)) ms, max \(maxI * 1000, format: .fixed(precision: 1)) ms")
    }

    // MARK: - Streaming per-frame pipeline (steps 1-4)

    /// CFA → crop-origin parity shift that renders the crop RGGB.
    /// (dy, dx) such that absolute position (cropY+dy, cropX+dx) is R.
    private static func rggbOriginShift(_ cfa: OSType) -> (dy: Int, dx: Int)? {
        switch cfa {
        case kCVPixelFormatType_14Bayer_RGGB: return (0, 0)
        case kCVPixelFormatType_14Bayer_BGGR: return (1, 1)
        case kCVPixelFormatType_14Bayer_GRBG: return (0, 1)
        case kCVPixelFormatType_14Bayer_GBRG: return (1, 0)
        default: return nil
        }
    }

    /// Consumes the payload's CVPixelBuffer: normalize → debayer at native
    /// square scale → box-reduce to the rung → quantize + histogram.
    /// Returns nil (logged) on any failure; the slot is then forward-filled.
    private func processPayload(_ payload: RawFramePayload, rung: DNGRung) -> DNGFrameSlot? {
        let buffer = payload.buffer
        let meta = payload.meta

        guard let shift = Self.rggbOriginShift(meta.cfa) else {
            logger.error("DNG: slot \(payload.slot) non-Bayer format \(fourCCString(meta.cfa))")
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            logger.error("DNG: slot \(payload.slot) no base address")
            return nil
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        // bytesPerRow includes padding — never assume width (ROTAS lesson).
        let rowStride = CVPixelBufferGetBytesPerRow(buffer) / 2  // UInt16 units

        // Largest centered EVEN square, with 1 px slack each side so the
        // RGGB parity shift never leaves the buffer.
        var side = min(width, height) & ~1
        side -= 2
        guard side >= rung.side, side > 0 else {
            logger.error("DNG: slot \(payload.slot) sensor too small (side \(side) < rung \(rung.side))")
            return nil
        }
        let cropX = (((width - side) / 2) & ~1) + shift.dx
        let cropY = (((height - side) / 2) & ~1) + shift.dy
        guard cropX >= 0, cropY >= 0, cropX + side <= width, cropY + side <= height else {
            logger.error("DNG: slot \(payload.slot) crop out of bounds")
            return nil
        }

        let base = baseAddress.assumingMemoryBound(to: UInt16.self)

        // ── Exposure anchor: latch p99.5 of linear G from the first
        //    processed frame (AE is locked → valid for the whole burst). ──
        if exposureScale == nil {
            var gSamples = [Double]()
            gSamples.reserveCapacity((side / 16 + 1) * (side / 16 + 1))
            let blackGr = meta.blackLevel[1]
            let denom = max(meta.whiteLevel - blackGr, 1e-6)
            var y = 0
            while y < side {                  // even local rows → Gr at odd x
                let row = base + (cropY + y) * rowStride + cropX
                var x = 1
                while x < side {
                    gSamples.append(min(max((Double(row[x]) - blackGr) / denom, 0), 1))
                    x += 16
                }
                y += 16
            }
            let sorted = gSamples.sorted()
            let idx = min(Int(Double(sorted.count - 1) * 0.995), sorted.count - 1)
            let anchor = max(sorted.isEmpty ? 1.0 : sorted[idx], 1e-4)
            exposureScale = 1.0 / anchor
            logger.info("DNG: exposure anchor p99.5 = \(anchor, format: .fixed(precision: 5)) (scale \(1.0 / anchor, format: .fixed(precision: 2)))")
        }
        let expScale = exposureScale ?? 1.0

        // ── Per-channel DN → display-domain LUTs. The net trained on
        //    sRGB-encoded mosaics and is scale-equivariant (BR4), so the
        //    OETF is applied BEFORE debayer; box-reduce and quantization
        //    then stay in the display domain (no second transfer pass). ──
        let nR = meta.wbNeutral[0], nG = meta.wbNeutral[1], nB = meta.wbNeutral[2]
        let gainR = (nR > 0 && nR.isFinite && nG > 0 && nG.isFinite) ? nG / nR : 1.0
        let gainB = (nB > 0 && nB.isFinite && nG > 0 && nG.isFinite) ? nG / nB : 1.0
        let gains = [gainR, 1.0, 1.0, gainB]              // [R, Gr, Gb, B]
        let lutSize = 16384                                // 14-bit container
        var lut = [Float](repeating: 0, count: 4 * lutSize)
        for ch in 0..<4 {
            let black = meta.blackLevel[ch]
            let denom = max(meta.whiteLevel - black, 1e-6)
            let gain = gains[ch] * expScale
            for dn in 0..<lutSize {
                // CLAMP, not max: metadata can report white levels below
                // the actual bit depth (ROTAS device bug).
                let lin = min(max((Double(dn) - black) / denom, 0), 1) * gain
                lut[ch * lutSize + dn] = Float(Self.srgbOETF(min(lin, 1)))
            }
        }

        // ── Normalize the crop into an RGGB float mosaic. ──
        var mosaic = [Float](repeating: 0, count: side * side)
        mosaic.withUnsafeMutableBufferPointer { mPtr in
            lut.withUnsafeBufferPointer { lPtr in
                for y in 0..<side {
                    let row = base + (cropY + y) * rowStride + cropX
                    let rowParity = (y & 1) << 1
                    let out = mPtr.baseAddress! + y * side
                    for x in 0..<side {
                        // Local parity IS the RGGB channel: 0=R 1=Gr 2=Gb 3=B.
                        let ch = rowParity | (x & 1)
                        out[x] = lPtr[ch * lutSize + min(Int(row[x]), lutSize - 1)]
                    }
                }
            }
        }

        // ── GPU: NN debayer at native square scale, tiled, then box-reduce
        //    to the active rung. Serial across slots by construction. ──
        if metal == nil { metal = MetalPipeline() }
        guard let rgb = metal?.debayerToRung(mosaic: mosaic, side: side, rung: rung.side) else {
            logger.error("DNG: slot \(payload.slot) debayerToRung failed")
            return nil
        }

        // ── Palette quantize + binomial histogram (pure CPU). ──
        let (indices, counts, binomial) = DNGPipeline.processFrame(
            rgb: rgb, side: rung.side, frame: payload.slot
        )

        DispatchQueue.main.async { [weak self] in
            self?.liveBinomial = binomial
        }

        return DNGFrameSlot(
            slot: payload.slot,
            indices: indices,
            counts: counts,
            binomial: binomial,
            hwTimestampNs: payload.hwTimestampNs,
            meta: meta,
            nativeSide: side
        )
    }

    /// Piecewise IEC 61966-2-1, applied ONCE (sixteen3 rule).
    static func srgbOETF(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }

    // MARK: - Single capture

    private func captureOne(slot: Int,
                            output: AVCapturePhotoOutput,
                            rawFormat: OSType,
                            timeoutSec: Double) async -> RawFramePayload? {
        // Fresh settings object per frame (single-use). NO rawFileType — we
        // never want DNG container bytes. No preview format (saves ISP work).
        let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
        // .speed REQUIRED: .balanced throws NSInvalidArgumentException at
        // capturePhoto() with Bayer RAW, on device only (BOREAL).
        settings.photoQualityPrioritization = .speed
        let uid = settings.uniqueID

        return await withCheckedContinuation { (cont: CheckedContinuation<RawFramePayload?, Never>) in
            // BOREAL OneShot pattern: delegate-vs-timeout races resume once.
            let gate = OneShotGate()
            let delegate = DNGPhotoDelegate(slot: slot) { [weak self] payload in
                self?.removeDelegate(for: uid)
                gate.tryResume { cont.resume(returning: payload) }
            }
            storeDelegate(delegate, for: uid)
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSec * 1_000_000_000))
                gate.tryResume {
                    logger.error("DNG: slot \(slot) timed out after \(timeoutSec) s")
                    cont.resume(returning: nil)
                }
            }
            sessionQueue.async {
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    private func storeDelegate(_ d: DNGPhotoDelegate, for id: Int64) {
        delegatesLock.lock()
        pendingDelegates[id] = d
        delegatesLock.unlock()
    }

    private func removeDelegate(for id: Int64) {
        delegatesLock.lock()
        pendingDelegates[id] = nil
        delegatesLock.unlock()
    }

    // MARK: - Finish kickoff (steps 5-6)

    private func runFinish(_ slots: [DNGFrameSlot], skippedSlots: Int, generation: Int) {
        setState(.processing(progress: 0, phase: "Wasserstein trajectory"))
        let rung = activeRung
        // Detached, NOT Task{} (BOREAL: plain Task inherits MainActor when
        // launched from a MainActor context).
        Task.detached(priority: .userInitiated) { [weak self] in
            let meta0 = slots[0].meta
            let result = DNGPipeline.finish(
                indexFrames: slots.map(\.indices),
                histograms: slots.map(\.counts),
                binomial: slots.map(\.binomial),
                rung: rung,
                nativeSide: slots[0].nativeSide,
                hwTimestampsNs: slots.map(\.hwTimestampNs),
                skippedSlots: skippedSlots,
                iso: meta0.iso,
                exposureSec: meta0.exposureSec,
                cfaFourCC: meta0.cfa,
                sensorWidth: meta0.width,
                sensorHeight: meta0.height
            ) { [weak self] p, phase in
                self?.setState(.processing(progress: p, phase: phase))
            }
            guard let self, self.burstGeneration == generation else { return }
            switch result {
            case .success(let r): self.setState(.done(r))
            case .failure(let e): self.setState(.error(String(describing: e)))
            }
        }
    }

    // MARK: - State dispatch

    private func setState(_ new: State) {
        if Thread.isMainThread {
            self.state = new
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.state = new
            }
        }
    }
}

// MARK: - One-shot gate

/// NSLock-guarded resume-exactly-once flag (BOREAL OneShot pattern).
private final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func tryResume(_ body: () -> Void) {
        lock.lock()
        let already = resumed
        resumed = true
        lock.unlock()
        if !already { body() }
    }
}

// MARK: - Delegate

private final class DNGPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let slot: Int
    private let completion: @Sendable (RawFramePayload?) -> Void
    private var payload: RawFramePayload?
    private let payloadLock = NSLock()

    init(slot: Int, completion: @escaping @Sendable (RawFramePayload?) -> Void) {
        self.slot = slot
        self.completion = completion
        super.init()
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            logger.error("DNG: slot \(self.slot) didFinishProcessing error: \(error.localizedDescription)")
            return
        }
        // Riskiest assumption of the whole mode (re-verify on first device
        // run): photo.pixelBuffer must be non-nil for plain-Bayer captures
        // without rawFileType.
        guard let buffer = photo.pixelBuffer else {
            logger.error("DNG: slot \(self.slot) photo.pixelBuffer == nil (plain-Bayer without rawFileType)")
            return
        }

        let meta = extractFrameMeta(photo: photo, buffer: buffer)

        // iOS 26 reports timescale 1e9; hand-rolled value*1e9/timescale
        // overflows Int64 (BOREAL gotcha).
        let tNs = CMTimeConvertScale(photo.timestamp,
                                     timescale: 1_000_000_000,
                                     method: .roundHalfAwayFromZero).value

        payloadLock.lock()
        payload = RawFramePayload(slot: slot, buffer: buffer, meta: meta, hwTimestampNs: tNs)
        payloadLock.unlock()
    }

    // The official "safe to fire the next shot" signal (BOREAL): resume here.
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                                 error: Error?) {
        if let error {
            logger.error("DNG: slot \(self.slot) didFinishCapture error: \(error.localizedDescription)")
        }
        payloadLock.lock()
        let p = payload
        payload = nil
        payloadLock.unlock()
        completion(p)
    }
}

// MARK: - Metadata extraction (full type paranoia — TENET/sixteen3 lessons)

/// BlackLevel/WhiteLevel/AsShotNeutral arrive as ANY of [Double], [Int],
/// [Float], NSArray<NSNumber>, or a scalar.
private func doubleArray(_ any: Any?) -> [Double]? {
    switch any {
    case let a as [Double]:   return a
    case let a as [Int]:      return a.map(Double.init)
    case let a as [Float]:    return a.map(Double.init)
    case let a as [NSNumber]: return a.map(\.doubleValue)
    case let n as NSNumber:   return [n.doubleValue]
    default:                  return nil
    }
}

/// CFA channel LUT for position index (y & 1) * 2 + (x & 1), in ABSOLUTE
/// sensor coordinates. Channel order R=0, Gr=1, Gb=2, B=3. nil = non-Bayer.
/// (Restored from the archived BayerCellReducer — needed for the DNG
/// BlackLevel remap, which arrives in CFA position order.)
func cfaChannelLUT(_ fourCC: OSType) -> [Int]? {
    switch fourCC {
    case kCVPixelFormatType_14Bayer_RGGB: return [0, 1, 2, 3]  // 'rgg4'
    case kCVPixelFormatType_14Bayer_BGGR: return [3, 2, 1, 0]  // 'bgg4'
    case kCVPixelFormatType_14Bayer_GRBG: return [1, 0, 3, 2]  // 'grb4'
    case kCVPixelFormatType_14Bayer_GBRG: return [2, 3, 0, 1]  // 'gbr4'
    default: return nil
    }
}

private func extractFrameMeta(photo: AVCapturePhoto, buffer: CVPixelBuffer) -> FrameMeta {
    let md = photo.metadata
    let dng = md["{DNG}"] as? [String: Any] ?? [:]
    let exif = md["{Exif}"] as? [String: Any] ?? [:]

    let cfa = CVPixelBufferGetPixelFormatType(buffer)
    let lut = cfaChannelLUT(cfa)

    let exposureSec = (exif["ExposureTime"] as? NSNumber)?.doubleValue ?? 0
    let iso = (exif["ISOSpeedRatings"] as? [Int])?.first
        ?? (exif["ISOSpeedRatings"] as? [NSNumber])?.first?.intValue
        ?? 0

    // Black levels re-read EVERY frame — they drift with sensor temperature.
    // DNG BlackLevel is in CFA position order; remap to [R, Gr, Gb, B].
    var black = [528.0, 528.0, 528.0, 528.0]
    if let raw = doubleArray(dng["BlackLevel"]) {
        if raw.count >= 4, let lut {
            for pos in 0..<4 { black[lut[pos]] = raw[pos] }
        } else if let first = raw.first {
            black = [Double](repeating: first, count: 4)
        }
    }

    let white = doubleArray(dng["WhiteLevel"])?.first ?? 4095.0

    var neutral = [1.0, 1.0, 1.0]
    if let n = doubleArray(dng["AsShotNeutral"]), n.count >= 3 {
        neutral = Array(n.prefix(3))
    }

    return FrameMeta(
        blackLevel: black,
        whiteLevel: white,
        wbNeutral: neutral,
        exposureSec: exposureSec,
        iso: iso,
        cfa: cfa,
        width: CVPixelBufferGetWidth(buffer),
        height: CVPixelBufferGetHeight(buffer),
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)
    )
}

/// Render an OSType as its four-character string (diagnostics).
/// (Restored from the archived BayerCellReducer.)
func fourCCString(_ code: OSType) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xFF),
        UInt8((code >> 16) & 0xFF),
        UInt8((code >> 8) & 0xFF),
        UInt8(code & 0xFF)
    ]
    return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", code)
}
