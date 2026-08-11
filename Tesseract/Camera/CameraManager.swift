// CameraManager.swift
// Tesseract
//
// TrueDepth front camera: synchronized RGB + Depth.
// Based on Apple's TrueDepthStreamer pattern.
//
// .photo preset: full 4:3 sensor FOV (not cropped 16:9).
// AVCaptureDataOutputSynchronizer: paired RGB+depth delivery.
// videoRotationAngle=90 on BOTH connections: portrait buffers.
// Universal 768 crop: forced, centered in whatever the sensor gives.

import AVFoundation
import CoreImage
import CoreMedia
import os.log

private let logger = Logger(subsystem: "com.tesseract.app", category: "Camera")

/// Camera state machine — the SIMPLICITY arc (2026-08-09): capture goes
/// straight to the result. (The three-phase A/B explore/compose/refine
/// states were excised 2026-08-10 with the rest of the gene arc.)
enum CameraState: Equatable {
    case idle
    case previewing
    case recording(Int)
    case processing
    case done
    case error(String)

    static func == (lhs: CameraState, rhs: CameraState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.previewing, .previewing),
             (.processing, .processing), (.done, .done): return true
        case (.recording(let a), .recording(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

/// Two cubes: Training 64³, Inference 128³. S = K (cube invariant).
/// From spec/algebra/Block.hs — verified by 14 axioms.
enum CubeMode: Int, CaseIterable {
    case training  = 64   // 64×64×64    (S=K=64,  step=12, native=Coarse)
    case inference = 128  // 128×128×128 (S=K=128, step=6,  native=Medium)

    var spatialSide: Int { rawValue }
    var frameCount: Int { rawValue }      // S = K (cube)
    var framesPerEpoch: Int { frameCount / 4 }

    var label: String {
        switch self {
        case .training:  return "64³ train"
        case .inference: return "128³ infer"
        }
    }
}

enum CameraConfig {
    // Universal crop (fits any TrueDepth sensor ≥1080 RGB, ≥360 depth)
    static let rgbCrop = 768
    static let depthCrop = 256
    static let scaleFactor = 3
    static let paletteSize = 256  // 4⁴, always

    // Pinned to 64³. The 128³ runtime switch was UI-only: MetalPipeline
    // allocates its textures once at 64 with no reallocation path, so
    // flipping to .inference dispatched 128-sized grids into 64-sized
    // textures and killed the app on device (2026-08-03). The two-cube
    // algebra (Block.hs, LevelTests) stays verified; revisit 128³ only
    // with a full pipeline reallocation design.
    static let mode: CubeMode = .training
    static var outputSize: Int { mode.spatialSide }
    static var totalFrames: Int { mode.frameCount }
    static var rgbStep: Int { rgbCrop / outputSize }
    static var depthStep: Int { depthCrop / outputSize }
    static var pixelCount: Int { outputSize * outputSize }

    static let displayScale = 4
    static var displaySize: Int { outputSize * displayScale }
    static let targetFPS = 20

    // Every export is 256×256: fat voxels via index replication (256/S per axis).
    static let exportSide = 256
    static var exportUpscale: Int { exportSide / outputSize }
}

@MainActor
final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var state: CameraState = .idle
    @Published var previewImage: CGImage?       // composite quantized preview
    @Published var previewMeasure: BirkhoffMeasure?
    @Published var gifData: Data?
    @Published var gifMeasure: BirkhoffMeasure?
    /// Tri-scale ladder telemetry over the realized 64³ cube
    /// (spec/output/TriScaleLadder.hs). Measurement only — no GIF
    /// byte depends on it.
    @Published private(set) var rungTelemetry: RungTelemetry?
    /// Dissonance telemetry (spec/statistics/Dissonance.hs): tuning
    /// at the rung-16 cadence + the urgency weight field. v1 is
    /// measurement only.
    @Published private(set) var dissonance: DissonanceTelemetry?

    // Processing progress (shown during compute phase)
    @Published var processProgress: Float = 0        // 0.0 → 1.0
    @Published var processPhase: String = ""          // "Analyzing frame 12/64"
    @Published var processBoards: GoBoards?           // live Go board snapshot
    /// Palette-creation visibility (Daniel, 2026-08-10): the current
    /// frame's 768-byte DYAD table, published as each is solved.
    @Published var liveTable: Data?

    // MARK: - Capture

    // Session objects live on sessionQueue after init (Apple TrueDepthStreamer
    // pattern): startRunning() blocks for hundreds of ms and must never run
    // on the main actor.
    nonisolated(unsafe) private let session = AVCaptureSession()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let depthOutput = AVCaptureDepthDataOutput()
    nonisolated(unsafe) private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    nonisolated private let sessionQueue = DispatchQueue(label: "com.tesseract.session", qos: .userInitiated)
    nonisolated private let processingQueue = DispatchQueue(label: "com.tesseract.camera", qos: .userInteractive)

    // MARK: - Processing

    private let frameBuffer = FrameBuffer()
    nonisolated(unsafe) private var _metalPipeline: MetalPipeline?
    /// Preview/export unification v1: the DYAD preview engine. Touched
    /// ONLY on processingQueue (serial) — no locking.
    nonisolated(unsafe) private let dyadPreview = DyadPreview()
    // GoEvaluator removed — territory analysis in GoBoard.swift is sufficient
    nonisolated(unsafe) private static var _loggedOnce = false

    override init() {
        super.init()
        // Build the Metal pipeline on the frame queue, not the main thread:
        // the queue is serial and is also the synchronizer's delegate queue,
        // so the pipeline is guaranteed ready before the first frame callback.
        processingQueue.async { [weak self] in
            self?._metalPipeline = MetalPipeline()
        }
    }

    // MARK: - Lifecycle

    private var hasConfigured = false

    // Message-key constants are nonisolated: they are read from the
    // session queue (configureSession) and ARKit's delegate queue.

    /// Error message for camera-permission denial. ContentView keys off
    /// this exact string to offer an "Open Settings" action.
    nonisolated static let cameraDeniedMessage = "camera access denied"

    /// Terminal: this hardware has no TrueDepth camera. ContentView keys
    /// off this string to render the gate (no retry — it cannot succeed).
    nonisolated static let noTrueDepthMessage = "no truedepth camera"

    /// GIFMachine.makeGIF returned nil — surfaced honestly instead of a
    /// "done" state with nothing to show. Shared by LIVE and FACE.
    nonisolated static let encodeFailedMessage = "gif export failed"

    func start() {
        guard state == .idle else { return }
        // If we already wired inputs/outputs, just resume the session.
        // configure unconditionally adds input/output and would fail the
        // canAddInput guard on the second pass, freezing the preview.
        if hasConfigured {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.session.startRunning()
                Task { @MainActor in self.state = .previewing }
            }
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { [weak self] in self?.configureAndStart() }
        case .notDetermined:
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard let self else { return }
                if granted {
                    self.sessionQueue.async { [weak self] in self?.configureAndStart() }
                } else {
                    self.state = .error(Self.cameraDeniedMessage)
                }
            }
        default:
            state = .error(Self.cameraDeniedMessage)
        }
    }

    func startRecording() {
        guard state == .previewing else { return }
        gifData = nil
        gifMeasure = nil
        liveTable = nil
        frameBuffer.startRecording()
        state = .recording(0)
    }

    func stop() {
        // Synchronous: the TrueDepth hardware admits one owner, and ARKit
        // (FACE mode) may start the instant this returns. sessionQueue is
        // serial and never blocks on the main actor, so sync is deadlock-free.
        sessionQueue.sync { session.stopRunning() }
        state = .idle
    }

    // MARK: - Session Configuration (Apple TrueDepthStreamer pattern)

    /// Runs on sessionQueue. Configure, then start; report state to the actor.
    nonisolated private func configureAndStart() {
        if let failure = configureSession() {
            Task { @MainActor in self.state = .error(failure) }
            return
        }
        session.startRunning()
        Task { @MainActor in
            self.hasConfigured = true
            self.state = .previewing
        }
        logger.info("Camera: session running")

        #if DEBUG
        runFrontRAWProbe()
        #endif
    }

    /// Runs on sessionQueue. Returns an error message, or nil on success.
    /// beginConfiguration/commitConfiguration are balanced on EVERY path
    /// (an early return without commit would poison all later attempts).
    nonisolated private func configureSession() -> String? {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // .photo preset: full 4:3 sensor FOV, supports depth output
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(
            .builtInTrueDepthCamera, for: .video, position: .front
        ) else {
            return Self.noTrueDepthMessage
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                return "Cannot add camera input"
            }
            session.addInput(input)

            // Frame rate
            try device.lockForConfiguration()
            let targetDuration = CMTime(value: 1, timescale: CMTimeScale(CameraConfig.targetFPS))
            device.activeVideoMinFrameDuration = targetDuration
            device.activeVideoMaxFrameDuration = targetDuration

            // Video output
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(videoOutput) else {
                return "Cannot add video output"
            }
            session.addOutput(videoOutput)

            // Depth output
            guard session.canAddOutput(depthOutput) else {
                return "Cannot add depth output"
            }
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true
            depthOutput.alwaysDiscardsLateDepthData = true

            // Select best depth format (Float16, highest resolution)
            let depthFormats = device.activeFormat.supportedDepthDataFormats
            let bestDepth = depthFormats
                .filter { CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat16 }
                .max(by: {
                    CMVideoFormatDescriptionGetDimensions($0.formatDescription).width
                    < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
                })
            if let bestDepth = bestDepth {
                device.activeDepthDataFormat = bestDepth
                let dims = CMVideoFormatDescriptionGetDimensions(bestDepth.formatDescription)
                logger.info("Camera: depth format \(dims.width)×\(dims.height) Float16")
            }

            device.unlockForConfiguration()

            // Orientation: portrait on BOTH connections (hardware rotation)
            if let vc = videoOutput.connection(with: .video) {
                if vc.isVideoRotationAngleSupported(90) {
                    vc.videoRotationAngle = 90
                }
                vc.isVideoMirrored = true
                logger.info("Camera: video connection rotationAngle=\(vc.videoRotationAngle), mirrored=\(vc.isVideoMirrored)")
            }
            if let dc = depthOutput.connection(with: .depthData) {
                if dc.isVideoRotationAngleSupported(90) {
                    dc.videoRotationAngle = 90
                }
                dc.isVideoMirrored = true
                logger.info("Camera: depth connection rotationAngle=\(dc.videoRotationAngle), mirrored=\(dc.isVideoMirrored)")
            }

            // Synchronizer: paired RGB + depth delivery
            outputSynchronizer = AVCaptureDataOutputSynchronizer(
                dataOutputs: [videoOutput, depthOutput]
            )
            outputSynchronizer?.setDelegate(self, queue: processingQueue)
            logger.info("Camera: synchronizer active")
            // Go territory analysis runs during processing phase, not here

        } catch {
            logger.error("Camera: \(error.localizedDescription)")
            return error.localizedDescription
        }
        return nil
    }

    #if DEBUG
    /// Diagnostic (runs on sessionQueue, after the session is live): does
    /// THIS front camera expose any RAW to third-party apps? Bayer formats
    /// land in availableRawPhotoPixelFormatTypes; ProRAW (linear DNG) is
    /// gated by isAppleProRAWSupported. Attach a throwaway photo output,
    /// log, detach. Answer appears once per run.
    nonisolated private func runFrontRAWProbe() {
        let probe = AVCapturePhotoOutput()
        session.beginConfiguration()
        if session.canAddOutput(probe) {
            session.addOutput(probe)
            session.commitConfiguration()
            let raws = probe.availableRawPhotoPixelFormatTypes
            let bayer = raws.filter { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
            logger.info("FRONT-RAW PROBE: rawFormats=\(raws.count) bayer=\(bayer.count) proRAWSupported=\(probe.isAppleProRAWSupported)")
            session.beginConfiguration()
            session.removeOutput(probe)
            session.commitConfiguration()
        } else {
            session.commitConfiguration()
            logger.info("FRONT-RAW PROBE: cannot attach photo output to front session")
        }
    }
    #endif

    // MARK: - Frame Processing

    nonisolated(unsafe) private static var _frameCounter: Int = 0
    nonisolated(unsafe) private static var _depthFrames: Int = 0
    nonisolated(unsafe) private static var _noDepthFrames: Int = 0
    nonisolated(unsafe) private static var _lastTimestamp: CFTimeInterval = 0
    nonisolated(unsafe) private static var _fpsAccum: Double = 0
    nonisolated(unsafe) private static var _fpsCount: Int = 0

    nonisolated func processFrame(rgbBuffer: CVPixelBuffer, depthBuffer: CVPixelBuffer?) {
        let rgbW = CVPixelBufferGetWidth(rgbBuffer)
        let rgbH = CVPixelBufferGetHeight(rgbBuffer)
        Self._frameCounter += 1

        // ── Frame timing ──
        let now = CACurrentMediaTime()
        let delta = now - Self._lastTimestamp
        Self._lastTimestamp = now
        if delta > 0 && delta < 1.0 {  // skip first frame and outliers
            Self._fpsAccum += delta
            Self._fpsCount += 1
        }

        if depthBuffer != nil { Self._depthFrames += 1 } else { Self._noDepthFrames += 1 }

        let logThis = Self._frameCounter % 20 == 1
        if logThis {
            let avgFPS = Self._fpsCount > 0 ? Double(Self._fpsCount) / Self._fpsAccum : 0
            logger.info("Camera: frame \(Self._frameCounter) RGB=\(rgbW)×\(rgbH) depth=\(depthBuffer != nil ? "YES" : "NO") avgFPS=\(String(format: "%.1f", avgFPS)) delta=\(String(format: "%.1fms", delta * 1000))")
            Self._fpsAccum = 0; Self._fpsCount = 0
        }

        let frameIdx = frameBuffer.frameCount

        // ════════════════════════════════════════════════════════
        // CONSOLIDATED PATH: GPU downsample → CPU PerfectQuantize
        // GPU: parallel texture reads (megapixel → S×S via 768 crop).
        // CPU: deterministic distribution matching (S² pixels).
        // ════════════════════════════════════════════════════════

        // Stage 1: GPU downsample (camera res → S×S with rotation)
        if let metal = _metalPipeline,
           let rgbTex = metal.makeTexture(from: rgbBuffer, pixelFormat: .bgra8Unorm) {

            let depthTex = depthBuffer.flatMap { metal.makeDepthTexture(from: $0) }

            if let result = metal.downsampleFrame(rgbTexture: rgbTex, depthTexture: depthTex) {
                let (img, measure) = makePreview(rgb: result.rgb,
                                                 depths: result.depth,
                                                 frameIndex: frameIdx,
                                                 metal: metal,
                                                 gpuTexturesReady: depthTex != nil)

                Task { @MainActor in
                    self.previewImage = img
                    self.previewMeasure = measure
                }

                // Recording: store raw data ONLY — no heavy analysis during capture
                if frameBuffer.frameCount < CameraConfig.totalFrames {
                    let captured = CapturedFrame(
                        index: frameIdx,
                        rgb: result.rgb,
                        depths: result.depth,
                        blockEvals: nil,  // computed during processing phase
                        timestamp: now
                    )
                    let count = frameBuffer.addCapturedFrame(captured)
                    if let count = count {
                        Task { @MainActor in
                            self.state = .recording(count)
                            if count >= CameraConfig.totalFrames {
                                self.state = .processing
                                self.encodeGIF()
                            }
                        }
                    }
                }
                return
            }
        }

        // ── CPU fallback (GPU unavailable) ──
        processFrameCPU(rgbBuffer: rgbBuffer, depthBuffer: depthBuffer, frameIdx: frameIdx, timestamp: now)
    }

    /// CPU-only frame processing: reads pixels directly from CVPixelBuffer.
    /// Used when Metal is unavailable (simulator, old device).
    nonisolated private func processFrameCPU(
        rgbBuffer: CVPixelBuffer, depthBuffer: CVPixelBuffer?,
        frameIdx: Int, timestamp: CFTimeInterval
    ) {
        let rgbW = CVPixelBufferGetWidth(rgbBuffer)
        let rgbH = CVPixelBufferGetHeight(rgbBuffer)
        let outSize = CameraConfig.outputSize
        let cropSize = CameraConfig.rgbCrop  // 768, forced
        let cropX = (rgbW - cropSize) / 2
        let cropY = (rgbH - cropSize) / 2
        let step = CameraConfig.rgbStep     // 768 / outSize, integer
        let half = step / 2

        CVPixelBufferLockBaseAddress(rgbBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(rgbBuffer, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(rgbBuffer)
        guard let baseAddr = CVPixelBufferGetBaseAddress(rgbBuffer) else { return }
        let buffer = baseAddr.assumingMemoryBound(to: UInt8.self)

        var pixels = [(Float, Float, Float)]()
        pixels.reserveCapacity(outSize * outSize)

        for y in 0..<outSize {
            for x in 0..<outSize {
                let srcX = cropX + y * step + half
                let srcY = cropY + (outSize - 1 - x) * step + half
                guard srcX < rgbW && srcY < rgbH else { pixels.append((0,0,0)); continue }
                let off = srcY * bytesPerRow + srcX * 4
                let b = Float(buffer[off]) / 255.0
                let g = Float(buffer[off + 1]) / 255.0
                let r = Float(buffer[off + 2]) / 255.0
                pixels.append((r, g, b))
            }
        }

        var depthValues: [Float]?
        if let db = depthBuffer {
            depthValues = readDepth(db, outSize: outSize)
        }

        let depths = depthValues ?? [Float](repeating: 0.5, count: outSize * outSize)

        let (img, measure) = makePreview(rgb: pixels, depths: depths,
                                         frameIndex: frameIdx)

        Task { @MainActor in
            self.previewImage = img
            self.previewMeasure = measure
        }

        // Recording: store CapturedFrame for global compute
        if frameBuffer.frameCount < CameraConfig.totalFrames {
            let captured = CapturedFrame(
                index: frameIdx, rgb: pixels, depths: depths,
                blockEvals: nil,
                timestamp: timestamp
            )
            let count = frameBuffer.addCapturedFrame(captured)
            if let count = count {
                Task { @MainActor in
                    self.state = .recording(count)
                    if count >= CameraConfig.totalFrames {
                        self.state = .processing
                        self.encodeGIF()
                    }
                }
            }
        }
    }

    // MARK: - Depth Reading

    nonisolated private func readDepth(_ depthBuffer: CVPixelBuffer, outSize: Int) -> [Float] {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let dW = CVPixelBufferGetWidth(depthBuffer)
        let dH = CVPixelBufferGetHeight(depthBuffer)
        guard let base = CVPixelBufferGetBaseAddress(depthBuffer) else {
            return [Float](repeating: 0.5, count: outSize * outSize)
        }

        let formatType = CVPixelBufferGetPixelFormatType(depthBuffer)

        let dCropSize = CameraConfig.depthCrop  // 256, forced
        let dCropX = (dW - dCropSize) / 2
        let dCropY = (dH - dCropSize) / 2
        let dStep = CameraConfig.depthStep    // 256 / outSize, integer
        let dHalf = dStep / 2

        var values = [Float]()
        values.reserveCapacity(outSize * outSize)

        if formatType == kCVPixelFormatType_DepthFloat16 {
            let ptr = base.assumingMemoryBound(to: UInt16.self)
            let stride = CVPixelBufferGetBytesPerRow(depthBuffer) / 2
            for y in 0..<outSize {
                for x in 0..<outSize {
                    // 90° CCW to match RGB rotation
                    let srcX = dCropX + y * dStep + dHalf
                    let srcY = dCropY + (outSize - 1 - x) * dStep + dHalf
                    guard srcX < dW && srcY < dH else { values.append(DepthSignal.fill); continue }
                    let raw = ptr[srcY * stride + srcX]
                    values.append(DepthSignal.signalOrFill(meters: Float(Float16(bitPattern: raw))))
                }
            }
        } else {
            // Float32 fallback
            let ptr = base.assumingMemoryBound(to: Float.self)
            let stride = CVPixelBufferGetBytesPerRow(depthBuffer) / 4
            for y in 0..<outSize {
                for x in 0..<outSize {
                    // 90° CCW
                    let srcX = dCropX + y * dStep + dHalf
                    let srcY = dCropY + (outSize - 1 - x) * dStep + dHalf
                    guard srcX < dW && srcY < dH else { values.append(DepthSignal.fill); continue }
                    values.append(DepthSignal.signalOrFill(meters: ptr[srcY * stride + srcX]))
                }
            }
        }

        // Fixed meters→signal map (spec/temporal/DepthSignal.hs), NOT
        // per-frame min/max normalization: the signal must be a pure
        // function of meters or σ flickers across the 64-frame capture.
        return values
    }

    // MARK: - GIF Encoding

    private func encodeGIF() {
        let capturedFrames = frameBuffer.exportCapturedFrames()
        let totalFrames = capturedFrames.count

        Task.detached(priority: .userInitiated) {
            // ════════════════════════════════════════════
            // Phase 1: Go analysis per frame (0% → 40%)
            // Sample first 361 pixels (19×19) for Go territory analysis.
            // This is a SAMPLE of the frame, not the full grid.
            // Territory + liberties = dithering guidance.
            // ════════════════════════════════════════════

            await MainActor.run {
                self.processProgress = 0
                self.processPhase = "Analyzing color structure..."
            }

            for (i, frame) in capturedFrames.enumerated() {
                // Go analysis on first 19×19 = 361 pixels (blockToGoBoards reads up to GoBoard.count)
                let boards = blockToGoBoards(pixels: frame.rgb)
                let eval = evaluateBlock(boards)

                await MainActor.run {
                    self.processProgress = Float(i + 1) / Float(totalFrames) * 0.40
                    self.processPhase = "Go analysis \(i + 1)/\(totalFrames) — complexity \(String(format: "%.2f", eval.complexity)), \(eval.ditherBudget) liberties"
                    self.processBoards = boards
                }
            }

            // ════════════════════════════════════════════
            // Phase 2: Quantize all frames (40% → 80%)
            // PerfectQuantizer with color + temporal dithering.
            // ════════════════════════════════════════════

            await MainActor.run {
                self.processPhase = "Quantizing tesseract..."
            }

            var quantizedFrames: [QuantizedFrame] = []
            for (i, frame) in capturedFrames.enumerated() {
                let indices = PerfectQuantizer.quantizeFrame(
                    frameIndex: frame.index,
                    rgb: frame.rgb,
                    depths: frame.depths
                )
                quantizedFrames.append(QuantizedFrame(
                    index: frame.index,
                    paletteIndices: indices,
                    rawRGB: frame.rgb,
                    depths: frame.depths,
                    measure: BirkhoffMeasure(paletteIndices: indices),
                    subjectAnalysis: PerfectQuantizer.analyzeSubject(depths: frame.depths),
                    anchorTrace: PerfectQuantizer.findAnchors(indices: indices),
                    timestamp: frame.timestamp
                ))

                await MainActor.run {
                    self.processProgress = 0.4 + Float(i + 1) / Float(totalFrames) * 0.4
                    self.processPhase = "Quantizing frame \(i + 1)/\(totalFrames)"
                }
            }

            // ════════════════════════════════════════════
            // Phase 3: Encode GIF (80% → 100%)
            // ════════════════════════════════════════════

            await MainActor.run {
                self.processPhase = "Encoding GIF..."
                self.processProgress = 0.85
            }

            let measure: BirkhoffMeasure? = quantizedFrames.isEmpty ? nil : {
                var totalCounts = [Int](repeating: 0, count: 256)
                for frame in quantizedFrames {
                    for idx in frame.paletteIndices { totalCounts[Int(idx)] += 1 }
                }
                let perFrame = totalCounts.map { $0 / max(1, quantizedFrames.count) }
                return BirkhoffMeasure(counts: perFrame)
            }()

            // Encode through the 64³ machine: persisted method setting,
            // eligibility fallback (spec/output/ExportMethods.hs).
            // The palette is shown as it is created (per-frame tables).
            let gifData = GIFMachine.makeGIF(frames: quantizedFrames, measure: measure,
                                             settings: ExportSettings.load(),
                                             onFrameTable: { [frameTotal = quantizedFrames.count] f, table in
                Task { @MainActor in
                    self.liveTable = table
                    self.processPhase = "Solving palette \(f + 1)/\(frameTotal)"
                }
            })

            // Archive every successful export — the library reviews old
            // GIFs + their palettes from the exact encoded bytes.
            if let gifData { GIFLibrary.archive(gifData) }

            // The 16/32/64 ladder over the realized cube — exact
            // lattice-level sums, telemetry only (TriScaleLadder.swift).
            let rungs = TriScaleLadder.telemetry(frames: quantizedFrames)
            if let rungs {
                logger.info("TriScale: mass \(rungs.mass) conserved=\(rungs.massConserved) free 64→32 \(rungs.freeBlocks3264)/32768, 32→16 \(rungs.freeBlocks1632)/4096")
            }
            let diss = DissonanceField.telemetry(frames: quantizedFrames)
            if let diss {
                logger.info("Dissonance: tuning (δG \(diss.loopTuning.kG), δB \(diss.loopTuning.kB))/1200, Ū \(diss.urgencyTotal)")
            }

            await MainActor.run {
                self.processProgress = 1.0
                self.processPhase = ""
                self.processBoards = nil
                self.gifData = gifData
                self.gifMeasure = measure
                self.rungTelemetry = rungs
                self.dissonance = diss
                // Simplicity decree (2026-08-09): capture → result.
                if gifData != nil {
                    self.state = .done
                } else {
                    // A nil encode is a failure, not a result.
                    self.state = .error(Self.encodeFailedMessage)
                }
            }
        }
    }

    // MARK: - Preview Images

    /// Build the composite quantized preview from palette indices.
    /// PREVIEW/EXPORT UNIFICATION under the Aerial Mirror Law: LOOK =
    /// dyad previews through the export's law (γ staging, one search,
    /// σ-routing). Slow state (τ-lifted rung-16 fit, stats-on-ŷ,
    /// table) at 5 Hz on CPU; the 20 Hz assignment runs the
    /// aerialPreview Metal kernel when this frame's textures are
    /// resident, the CPU reference otherwise. Other looks keep the
    /// lattice quick-quantize.
    nonisolated private func makePreview(
        rgb: [(Float, Float, Float)], depths: [Float], frameIndex: Int,
        metal: MetalPipeline? = nil, gpuTexturesReady: Bool = false
    ) -> (CGImage?, BirkhoffMeasure) {
        if ExportSettings.load().method == .dyad {
            dyadPreview.refreshIfDue(rgb: rgb, depths: depths)
            let indices: [UInt8]?
            if gpuTexturesReady, let metal, let st = dyadPreview.metalState,
               let gpu = metal.aerialAssign(state: st) {
                indices = gpu
            } else {
                indices = dyadPreview.assignCPU(rgb: rgb, depths: depths)
            }
            if let indices {
                return (buildPreviewImage(indices: indices, table: dyadPreview.table),
                        BirkhoffMeasure(paletteIndices: indices))
            }
        }
        let indices = PerfectQuantizer.previewQuantize(
            rgb: rgb, depths: depths, frameIndex: frameIndex)
        return (buildPreviewImage(indices: indices),
                BirkhoffMeasure(paletteIndices: indices))
    }

    /// Build a preview image from palette indices. With `table`, colors
    /// come from the live DYAD table (the unified preview); without,
    /// from the canonical tesseract lattice palette.
    nonisolated func buildPreviewImage(
        indices: [UInt8], table: [(UInt8, UInt8, UInt8)]
    ) -> CGImage? {
        guard table.count == 256 else { return buildPreviewImage(indices: indices) }
        let size = CameraConfig.outputSize
        var rgba = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            let (r, g, b) = table[Int(indices[i])]
            rgba[i * 4] = r; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = b
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &rgba, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        return ctx.makeImage()
    }

    nonisolated func buildPreviewImage(indices: [UInt8]) -> CGImage? {
        let size = CameraConfig.outputSize
        var rgba = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            let (r, g, b) = TesseractCoord(index: indices[i]).sRGB8
            rgba[i * 4] = r; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = b
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &rgba, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        return ctx.makeImage()
    }

    // MARK: - Full-Resolution Block Analysis

    /// Read step×step blocks from the FULL CVPixelBuffer and compute Go analysis per block.
    /// Uses universal 768 crop centered in whatever the sensor gives.
    /// Returns outputSize² BlockEvals — one per output pixel position.
    nonisolated func analyzeBlocks(rgbBuffer: CVPixelBuffer) -> [BlockEval] {
        let rgbW = CVPixelBufferGetWidth(rgbBuffer)
        let rgbH = CVPixelBufferGetHeight(rgbBuffer)
        let outSize = CameraConfig.outputSize
        let cropSize = CameraConfig.rgbCrop  // 768, forced
        let cropX = (rgbW - cropSize) / 2
        let cropY = (rgbH - cropSize) / 2
        let step = CameraConfig.rgbStep     // 768 / outSize, integer

        CVPixelBufferLockBaseAddress(rgbBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(rgbBuffer, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(rgbBuffer)
        guard let baseAddr = CVPixelBufferGetBaseAddress(rgbBuffer) else {
            return []
        }
        let buffer = baseAddr.assumingMemoryBound(to: UInt8.self)

        var evals = [BlockEval]()
        evals.reserveCapacity(outSize * outSize)

        for by in 0..<outSize {
            for bx in 0..<outSize {
                // Read step×step pixels from this block (with 90° CCW rotation)
                var blockPixels = [(Float, Float, Float)]()
                blockPixels.reserveCapacity(step * step)

                for dy in 0..<step {
                    for dx in 0..<step {
                        // Same rotation as downsample kernel: output (x,y) → source (y, 63-x)
                        let srcX = cropX + by * step + dy
                        let srcY = cropY + (outSize - 1 - bx) * step + dx
                        guard srcX < rgbW && srcY < rgbH else {
                            blockPixels.append((0, 0, 0))
                            continue
                        }
                        let off = srcY * bytesPerRow + srcX * 4
                        let b = Float(buffer[off]) / 255.0
                        let g = Float(buffer[off + 1]) / 255.0
                        let r = Float(buffer[off + 2]) / 255.0
                        blockPixels.append((r, g, b))
                    }
                }

                // Compute 3 Go boards from block pixels → evaluate
                let boards = blockToGoBoards(pixels: blockPixels)
                let eval = evaluateBlock(boards)
                evals.append(eval)
            }
        }

        return evals
    }
}

// MARK: - AVCaptureDataOutputSynchronizerDelegate

extension CameraManager: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        // Get paired video + depth
        guard let syncedVideo = synchronizedDataCollection.synchronizedData(for: videoOutput)
                as? AVCaptureSynchronizedSampleBufferData,
              !syncedVideo.sampleBufferWasDropped,
              let rgbBuffer = CMSampleBufferGetImageBuffer(syncedVideo.sampleBuffer)
        else { return }

        // Depth is optional (may be dropped)
        var depthBuffer: CVPixelBuffer?
        if let syncedDepth = synchronizedDataCollection.synchronizedData(for: depthOutput)
            as? AVCaptureSynchronizedDepthData,
           !syncedDepth.depthDataWasDropped {
            let converted = syncedDepth.depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16)
            depthBuffer = converted.depthDataMap
        }

        processFrame(rgbBuffer: rgbBuffer, depthBuffer: depthBuffer)
    }
}
