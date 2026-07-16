// RGBTCaptureManager.swift
// Tesseract
//
// Rear-camera session + 64-frame plain-Bayer RAW burst state machine.
// Structurally mirrors RAWCaptureManager (sibling class — that one is NOT
// modified): @unchecked Sendable, dedicated sessionQueue, setState hopping
// to main for @Published, NSLock'd pendingDelegates, full teardown().
//
// Differences that are load-bearing:
//   • .photo preset, NO 48MP dance — the binned 4224×3024 12-bit readout is
//     the point (48MP cannot sustain a 64-shot burst).
//   • AVCapturePhotoSettings(rawPixelFormatType:) with NO rawFileType —
//     photo.pixelBuffer IS the raw Bayer plane; DNG bytes never exist.
//   • .speed prioritization per shot: .balanced throws
//     NSInvalidArgumentException with Bayer RAW on device (BOREAL).
//   • never iterate device.formats — several video-only formats trap the
//     Swift runtime when their properties are accessed on iOS 26 (BOREAL).
//   • AE/AWB/focus locked across the burst: cross-frame photon statistics
//     require ONE exposure.

@preconcurrency import AVFoundation
import Combine
import CoreMedia
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tesseract.app", category: "RGBTCapture")

// MARK: - Frame payload (delegate → reducer, ownership transferred)

/// Ownership transferred: exactly one consumer (BayerCellReducer), never shared.
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
    /// 4 pairs, Var(x) = s*x + o on the normalized [0,1] signal.
    let noise: [(s: Double, o: Double)]
    let exposureSec: Double
    let iso: Int
    let cfa: OSType
    let width: Int
    let height: Int
    let bytesPerRow: Int
    /// True when NoiseProfile was absent and the fallback engaged.
    let noiseIsFallback: Bool
}

// MARK: - Result types

struct RGBTStats: Sendable {
    let burstDurationSec: Double        // last hw timestamp - first
    let meanIntervalMs: Double
    let maxIntervalMs: Double
    let skippedSlots: Int
    let iso: Int
    let exposureSec: Double
    let tP1: Double                     // seconds, pre-normalization percentiles
    let tP99: Double
    let meanSigmaT: Double              // mean per-cell sigma_T (seconds)
    let floorFraction: Double           // fraction of cells that hit the Heisenberg floor
    let cfaFourCC: OSType
    let sensorWidth: Int
    let sensorHeight: Int
}

struct RGBTResult: Sendable, Equatable {
    let id: UUID
    let gifData: Data
    let measure: BirkhoffMeasure
    let stats: RGBTStats

    static func == (lhs: RGBTResult, rhs: RGBTResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Manager

final class RGBTCaptureManager: NSObject, ObservableObject, @unchecked Sendable {

    enum State: Sendable, Equatable {
        case idle
        case configuring
        case ready
        case capturing(frame: Int)            // 0..63 completed count
        case processing(progress: Float, phase: String)
        case done(RGBTResult)
        case error(String)
    }

    @Published private(set) var state: State = .idle

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.tesseract.rgbt.session")
    private var photoOutput: AVCapturePhotoOutput?
    private var currentDevice: AVCaptureDevice?
    private var rawFormat: OSType?
    private var runtimeErrorObserver: (any NSObjectProtocol)?

    /// First-frame pixel-format latch (SixFour): every later frame must match.
    private var latchedFormat: OSType?

    /// Stamps each pipeline run; a late completion whose generation != current
    /// is discarded (SixFour generation-tag lesson).
    private var burstGeneration = 0

    /// Preview layer owned by the manager (same lazy pattern as RAWCaptureManager).
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        return layer
    }()

    // Retain delegates until their callbacks fire, keyed by settings uniqueID.
    private var pendingDelegates: [Int64: RGBTPhotoDelegate] = [:]
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

        // Permission flow — copied from RAWCaptureManager.configureOnQueue.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configure()
                } else {
                    self.setState(.error(RAWError.cameraPermissionDenied.localizedDescription))
                }
            }
            return
        case .denied, .restricted:
            setState(.error(RAWError.cameraPermissionDenied.localizedDescription))
            return
        @unknown default:
            setState(.error(RAWError.cameraPermissionDenied.localizedDescription))
            return
        }

        setState(.configuring)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // .photo preset deliberately yields the binned 4224×3024 12MP format.
        // No 48MP dance, no .inputPriority.
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else {
            setState(.error(RAWError.noRearCamera.localizedDescription))
            return
        }
        self.currentDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                setState(.error(RAWError.cannotAddInput.localizedDescription))
                return
            }
            session.addInput(input)
        } catch {
            setState(.error(error.localizedDescription))
            return
        }

        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            setState(.error(RAWError.cannotAddOutput.localizedDescription))
            return
        }
        session.addOutput(output)
        self.photoOutput = output

        // NEVER iterate device.formats or read per-format properties — on
        // iPhone 17 Pro / iOS 26 several video-only formats trap the Swift
        // runtime when their properties are accessed (BOREAL, device-verified).
        // The static class method on OSTypes is safe.
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
        logger.info("RGBT: plain-Bayer RAW format \(fourCCString(bayer))")

        // Fig/XPC errors like -17281 are otherwise invisible (BOREAL).
        if runtimeErrorObserver == nil {
            runtimeErrorObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: nil
            ) { note in
                let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
                logger.error("RGBT: session runtime error: \(String(describing: err))")
            }
        }

        // Commit happens via defer, THEN start as a follow-up on the same
        // queue (RAWCaptureManager pattern).
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
            if let obs = self.runtimeErrorObserver {
                NotificationCenter.default.removeObserver(obs)
                self.runtimeErrorObserver = nil
            }
            self.setState(.idle)
        }
    }

    /// Frees the session's ISP buffers (~100 MB) before compute, but keeps
    /// currentDevice so the deferred AE unlock still has a target.
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

    /// Cross-frame photon statistics require ONE exposure across the burst.
    /// Runs on sessionQueue. Polls the settle flags; proceeds anyway on
    /// timeout (never block the shutter). The lock propagates asynchronously
    /// through the ISP (sixteen3), hence the settle wait.
    private func lockExposureOnQueue(timeoutMs: Int) {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            device.unlockForConfiguration()
        } catch {
            logger.error("RGBT: lockExposure lockForConfiguration failed: \(error.localizedDescription)")
            return
        }
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while (device.isAdjustingExposure || device.isAdjustingWhiteBalance || device.isAdjustingFocus)
                && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.015)
        }
        if Date() >= deadline {
            logger.warning("RGBT: AE/AWB/AF settle timed out after \(timeoutMs) ms — proceeding")
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
            logger.error("RGBT: unlockExposure failed: \(error.localizedDescription)")
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

    static let burstFrames = 64
    private static let maxSkippedSlots = 4

    func captureBurst() async {
        guard case .ready = state, let output = photoOutput, let raw = rawFormat else {
            logger.warning("RGBT: captureBurst called but not ready")
            return
        }
        burstGeneration += 1
        let generation = burstGeneration
        latchedFormat = nil

        await onSessionQueue { self.lockExposureOnQueue(timeoutMs: 400) }
        // Every exit path restores AE (device ref survives compute teardown).
        defer { sessionQueue.async { self.unlockExposureOnQueue() } }

        let n = Self.burstFrames
        var stats: [FrameCellStats?] = Array(repeating: nil, count: n)
        var pending: (slot: Int, task: Task<FrameCellStats?, Never>)? = nil
        var skipped = 0

        for slot in 0..<n {
            setState(.capturing(frame: slot))
            // Fire-next-then-reduce overlap: the previous frame's reduce runs
            // while this shot is in flight. Pipeline depth: 1 reduce + 1 capture.
            var payload = await captureOne(slot: slot, output: output, rawFormat: raw, timeoutSec: 5)

            if let p = pending {
                stats[p.slot] = await p.task.value
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
                    logger.error("RGBT: slot \(slot) CFA changed mid-burst: \(fourCCString(got.meta.cfa)) != \(fourCCString(self.latchedFormat ?? 0)) — dropping slot")
                    payload = nil
                }
            }

            if let payload {
                pending = (slot, Task.detached(priority: .userInitiated) {
                    BayerCellReducer.reduce(payload)     // consumes the CVPixelBuffer
                })
            } else {
                skipped += 1
                logger.warning("RGBT: slot \(slot) dropped (\(skipped) total)")
                if skipped > Self.maxSkippedSlots {
                    setState(.error("burst failed: \(skipped) dropped slots"))
                    return
                }
                // A dropped slot never blocks the burst (BOREAL); it is
                // duplicated from a neighbor in the fill pass below.
            }
        }
        if let p = pending {
            stats[p.slot] = await p.task.value
        }

        // Fill: forward-fill from the previous good slot; leading nils take
        // the first good slot. Reduce failures count as skips too.
        guard let firstGood = stats.firstIndex(where: { $0 != nil }) else {
            setState(.error("burst failed: no frames reduced"))
            return
        }
        for i in 0..<firstGood { stats[i] = stats[firstGood] }
        for i in 1..<n where stats[i] == nil { stats[i] = stats[i - 1] }
        let filled = stats.compactMap { $0 }
        let duplicated = filled.count == n ? zip(filled, filled.indices).filter { $0.0.slot != $0.1 }.count : 0
        logBurstTiming(filled)

        // stopRunning + remove IO frees ~100 MB of ISP buffers before compute
        // (ROTAS teardownSync lesson).
        await teardownSessionForCompute()
        runPipeline(filled, skippedSlots: max(skipped, duplicated), generation: generation)
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
        logger.info("RGBT: frame 0 latch OK — \(fourCCString(actual)) \(payload.meta.width)×\(payload.meta.height)")
        return nil
    }

    /// Measure-and-warn only, never reject (SixFour BurstTiming policy).
    private func logBurstTiming(_ stats: [FrameCellStats]) {
        let ts = stats.map { Double($0.hwTimestampNs) / 1e9 }
        guard ts.count > 1 else { return }
        let intervals = zip(ts.dropFirst(), ts).map { $0 - $1 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let maxI = intervals.max() ?? 0
        let minI = intervals.min() ?? 0
        let variance = intervals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(intervals.count)
        logger.info("RGBT: burst timing — mean \(mean * 1000, format: .fixed(precision: 1)) ms, std \(variance.squareRoot() * 1000, format: .fixed(precision: 1)) ms, min \(minI * 1000, format: .fixed(precision: 1)) ms, max \(maxI * 1000, format: .fixed(precision: 1)) ms")
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
            let delegate = RGBTPhotoDelegate(slot: slot) { [weak self] payload in
                self?.removeDelegate(for: uid)
                gate.tryResume { cont.resume(returning: payload) }
            }
            storeDelegate(delegate, for: uid)
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSec * 1_000_000_000))
                gate.tryResume {
                    logger.error("RGBT: slot \(slot) timed out after \(timeoutSec) s")
                    cont.resume(returning: nil)
                }
            }
            sessionQueue.async {
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    private func storeDelegate(_ d: RGBTPhotoDelegate, for id: Int64) {
        delegatesLock.lock()
        pendingDelegates[id] = d
        delegatesLock.unlock()
    }

    private func removeDelegate(for id: Int64) {
        delegatesLock.lock()
        pendingDelegates[id] = nil
        delegatesLock.unlock()
    }

    // MARK: - Pipeline kickoff

    private func runPipeline(_ stats: [FrameCellStats], skippedSlots: Int, generation: Int) {
        setState(.processing(progress: 0, phase: "estimating T"))
        // Detached, NOT Task{} (BOREAL: plain Task inherits MainActor when
        // launched from a MainActor context).
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = RGBTPipeline.run(stats: stats, skippedSlots: skippedSlots) { [weak self] p, phase in
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

private final class RGBTPhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
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
            logger.error("RGBT: slot \(self.slot) didFinishProcessing error: \(error.localizedDescription)")
            return
        }
        // Riskiest assumption of the whole mode (re-verify on first device
        // run): photo.pixelBuffer must be non-nil for plain-Bayer captures
        // without rawFileType.
        guard let buffer = photo.pixelBuffer else {
            logger.error("RGBT: slot \(self.slot) photo.pixelBuffer == nil (plain-Bayer without rawFileType)")
            return
        }

        let meta = extractFrameMeta(photo: photo, buffer: buffer)
        if meta.noiseIsFallback {
            logger.warning("RGBT: slot \(self.slot) NoiseProfile ABSENT — using fallback s=0.001 o=0 (T becomes monotone in brightness)")
        }

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
            logger.error("RGBT: slot \(self.slot) didFinishCapture error: \(error.localizedDescription)")
        }
        payloadLock.lock()
        let p = payload
        payload = nil
        payloadLock.unlock()
        completion(p)
    }
}

// MARK: - Metadata extraction (full type paranoia — TENET/sixteen3 lessons)

/// BlackLevel/WhiteLevel/AsShotNeutral/NoiseProfile arrive as ANY of
/// [Double], [Int], [Float], NSArray<NSNumber>, or a scalar.
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

/// Parse NoiseProfile into 4 (s, o) pairs in R, Gr, Gb, B order.
/// 1 pair → replicate to 4; 3 pairs (R,G,B) → [R, G, G, B].
private func noisePairs(_ any: Any?) -> [(s: Double, o: Double)]? {
    var flat: [Double] = []
    if let d = doubleArray(any) {
        flat = d
    } else if let arr = any as? [Any] {
        for e in arr {
            guard let p = doubleArray(e) else { return nil }
            flat.append(contentsOf: p)
        }
    } else {
        return nil
    }
    guard flat.count >= 2, flat.count % 2 == 0 else { return nil }
    var pairs: [(s: Double, o: Double)] = stride(from: 0, to: flat.count, by: 2)
        .map { (s: flat[$0], o: flat[$0 + 1]) }
    switch pairs.count {
    case 1:  pairs = Array(repeating: pairs[0], count: 4)
    case 3:  pairs = [pairs[0], pairs[1], pairs[1], pairs[2]]   // R,G,B → R,Gr,Gb,B
    case 4:  break
    default: pairs = Array(repeating: pairs[0], count: 4)
    }
    return pairs
}

private func extractFrameMeta(photo: AVCapturePhoto, buffer: CVPixelBuffer) -> FrameMeta {
    let md = photo.metadata
    let dng = md["{DNG}"] as? [String: Any] ?? [:]
    let exif = md["{Exif}"] as? [String: Any] ?? [:]

    let cfa = CVPixelBufferGetPixelFormatType(buffer)
    let lut = BayerCellReducer.cfaLUT(cfa)

    let exposureSec = (exif["ExposureTime"] as? NSNumber)?.doubleValue ?? 0
    let iso = (exif["ISOSpeedRatings"] as? [Int])?.first
        ?? (exif["ISOSpeedRatings"] as? [NSNumber])?.first?.intValue
        ?? 0

    // Black levels re-read EVERY frame — they drift with sensor temperature
    // (sixteen3 tracks the drift as a health metric).
    // DNG BlackLevel is in CFA position order; remap to [R, Gr, Gb, B].
    var black = [528.0, 528.0, 528.0, 528.0]
    if let raw = doubleArray(dng["BlackLevel"]) {
        if raw.count >= 4, let lut {
            // raw[pos] belongs to channel lut[pos]
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

    let parsedNoise = noisePairs(dng["NoiseProfile"])
    let noise = parsedNoise ?? Array(repeating: (s: 0.001, o: 0.0), count: 4)

    return FrameMeta(
        blackLevel: black,
        whiteLevel: white,
        wbNeutral: neutral,
        noise: noise,
        exposureSec: exposureSec,
        iso: iso,
        cfa: cfa,
        width: CVPixelBufferGetWidth(buffer),
        height: CVPixelBufferGetHeight(buffer),
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        noiseIsFallback: parsedNoise == nil
    )
}
