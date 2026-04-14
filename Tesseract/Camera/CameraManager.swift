// CameraManager.swift
// Tesseract
//
// TrueDepth front camera: synchronized RGB + Depth.
// Based on Apple's TrueDepthStreamer pattern.
//
// .photo preset: full 4:3 sensor FOV (not cropped 16:9).
// AVCaptureDataOutputSynchronizer: paired RGB+depth delivery.
// videoRotationAngle=90 on BOTH connections: portrait buffers.
// Dynamic crop: reads dimensions from buffer, no hardcoded constants.

import AVFoundation
import CoreImage
import CoreMedia
import os.log

private let logger = Logger(subsystem: "com.tesseract.app", category: "Camera")

/// Camera state machine
enum CameraState: Equatable {
    case idle, previewing, recording(Int), processing, done, error(String)
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

/// Constants
enum CameraConfig {
    static let captureSize = 64
    static let displayScale = 4
    static let displaySize = captureSize * displayScale
    static let targetFPS = 20
    static let totalFrames = 64
}

@MainActor
final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var state: CameraState = .idle
    @Published var previewImage: CGImage?       // composite quantized preview
    @Published var previewR: CGImage?            // R channel (64×64 grayscale)
    @Published var previewG: CGImage?            // G channel
    @Published var previewB: CGImage?            // B channel
    @Published var previewD: CGImage?            // Depth channel
    @Published var previewMeasure: BirkhoffMeasure?
    @Published var gifData: Data?
    @Published var gifMeasure: BirkhoffMeasure?

    // Processing progress (shown during compute phase)
    @Published var processProgress: Float = 0        // 0.0 → 1.0
    @Published var processPhase: String = ""          // "Analyzing frame 12/64"
    @Published var processBoards: GoBoards?           // live Go board snapshot

    // MARK: - Capture

    private let session = AVCaptureSession()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let depthOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private let processingQueue = DispatchQueue(label: "com.tesseract.camera", qos: .userInteractive)

    // MARK: - Processing

    private let frameBuffer = FrameBuffer()
    nonisolated(unsafe) private var _metalPipeline: MetalPipeline?
    private let goEvaluator = GoEvaluator()
    nonisolated(unsafe) private static var _loggedOnce = false

    override init() {
        super.init()
        self._metalPipeline = MetalPipeline()
    }

    // MARK: - Lifecycle

    func start() {
        guard state == .idle else { return }
        Task { await configure() }
    }

    func startRecording() {
        guard state == .previewing else { return }
        gifData = nil
        gifMeasure = nil
        frameBuffer.startRecording()
        state = .recording(0)
    }

    func stop() {
        session.stopRunning()
        state = .idle
    }

    // MARK: - Session Configuration (Apple TrueDepthStreamer pattern)

    private func configure() async {
        session.beginConfiguration()

        // .photo preset: full 4:3 sensor FOV, supports depth output
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(
            .builtInTrueDepthCamera, for: .video, position: .front
        ) else {
            state = .error("No TrueDepth camera")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                state = .error("Cannot add camera input"); return
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
                state = .error("Cannot add video output"); return
            }
            session.addOutput(videoOutput)

            // Depth output
            guard session.canAddOutput(depthOutput) else {
                state = .error("Cannot add depth output"); return
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

            session.commitConfiguration()
            session.startRunning()
            state = .previewing
            logger.info("Camera: session running")

            // Stagger KataGo model load — don't block camera startup
            goEvaluator.loadIfNeeded()

        } catch {
            state = .error(error.localizedDescription)
            logger.error("Camera: \(error.localizedDescription)")
        }
    }

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
        // GPU does parallel texture reads (megapixel → 64×64).
        // CPU does deterministic distribution matching (4096 pixels).
        // ════════════════════════════════════════════════════════

        // Stage 1: GPU downsample (camera res → 64×64 with rotation)
        if let metal = _metalPipeline,
           let rgbTex = metal.makeTexture(from: rgbBuffer, pixelFormat: .bgra8Unorm) {

            let depthTex = depthBuffer.flatMap { metal.makeDepthTexture(from: $0) }

            if let result = metal.downsampleFrame(rgbTexture: rgbTex, depthTexture: depthTex) {
                // Preview: quick quantize + per-channel views (R, G, B, D)
                let previewIndices = PerfectQuantizer.previewQuantize(
                    rgb: result.rgb,
                    depths: result.depth,
                    frameIndex: frameIdx
                )

                let img = buildPreviewImage(indices: previewIndices)
                let measure = BirkhoffMeasure(paletteIndices: previewIndices)
                let rImg = buildChannelPreview(values: result.rgb.map(\.0))
                let gImg = buildChannelPreview(values: result.rgb.map(\.1))
                let bImg = buildChannelPreview(values: result.rgb.map(\.2))
                let dImg = buildChannelPreview(values: result.depth)

                Task { @MainActor in
                    self.previewImage = img
                    self.previewR = rImg
                    self.previewG = gImg
                    self.previewB = bImg
                    self.previewD = dImg
                    self.previewMeasure = measure
                }

                // Recording: analyze full-res blocks + store CapturedFrame
                if frameBuffer.frameCount < CameraConfig.totalFrames {
                    // CPU reads the FULL CVPixelBuffer for 18×18 block Go analysis
                    let blockStart = CACurrentMediaTime()
                    let blockEvals = analyzeBlocks(rgbBuffer: rgbBuffer)
                    let blockMs = (CACurrentMediaTime() - blockStart) * 1000
                    if logThis {
                        logger.info("Camera: block analysis \(blockEvals.count) blocks in \(String(format: "%.1f", blockMs))ms")
                    }

                    let captured = CapturedFrame(
                        index: frameIdx,
                        rgb: result.rgb,
                        depths: result.depth,
                        blockEvals: blockEvals.isEmpty ? nil : blockEvals,
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
        let outSize = CameraConfig.captureSize
        let cropSize = min(rgbW, rgbH)
        let cropX = (rgbW - cropSize) / 2
        let cropY = (rgbH - cropSize) / 2
        let step = cropSize / outSize
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

        // Preview: quick quantize + per-channel views
        let previewIndices = PerfectQuantizer.previewQuantize(
            rgb: pixels, depths: depths, frameIndex: frameIdx
        )

        let img = buildPreviewImage(indices: previewIndices)
        let measure = BirkhoffMeasure(paletteIndices: previewIndices)
        let rImg = buildChannelPreview(values: pixels.map(\.0))
        let gImg = buildChannelPreview(values: pixels.map(\.1))
        let bImg = buildChannelPreview(values: pixels.map(\.2))
        let dImg = buildChannelPreview(values: depths)

        Task { @MainActor in
            self.previewImage = img
            self.previewR = rImg
            self.previewG = gImg
            self.previewB = bImg
            self.previewD = dImg
            self.previewMeasure = measure
        }

        // Recording: store CapturedFrame for global compute
        if frameBuffer.frameCount < CameraConfig.totalFrames {
            let blockEvals = analyzeBlocks(rgbBuffer: rgbBuffer)
            let captured = CapturedFrame(
                index: frameIdx, rgb: pixels, depths: depths,
                blockEvals: blockEvals.isEmpty ? nil : blockEvals,
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

        // Depth may be Float16 — convert via CVPixelBuffer format
        let formatType = CVPixelBufferGetPixelFormatType(depthBuffer)

        let dCropSize = min(dW, dH)
        let dCropX = (dW - dCropSize) / 2
        let dCropY = (dH - dCropSize) / 2
        let dStep = dCropSize / outSize
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
                    guard srcX < dW && srcY < dH else { values.append(0.5); continue }
                    let raw = ptr[srcY * stride + srcX]
                    let f = Float(Float16(bitPattern: raw))
                    values.append(f.isFinite && f > 0 ? f : 0.5)
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
                    guard srcX < dW && srcY < dH else { values.append(0.5); continue }
                    let f = ptr[srcY * stride + srcX]
                    values.append(f.isFinite && f > 0 ? f : 0.5)
                }
            }
        }

        // Normalize to [0, 1]: 1=near, 0=far
        let valid = values.filter { $0 > 0 && $0 < 100 }
        guard let minD = valid.min(), let maxD = valid.max(), maxD > minD else { return values }
        let range = maxD - minD
        return values.map { 1.0 - max(0, min(1, ($0 - minD) / range)) }
    }

    // MARK: - GIF Encoding

    private func encodeGIF() {
        let capturedFrames = frameBuffer.exportCapturedFrames()
        let totalFrames = capturedFrames.count

        Task.detached(priority: .userInitiated) {
            // ════════════════════════════════════════════
            // Phase 1: Go analysis (0% → 40%)
            // Analyze each frame's pixels as 3 Go boards.
            // Publish boards to UI for live visualization.
            // ════════════════════════════════════════════

            await MainActor.run {
                self.processProgress = 0
                self.processPhase = "Analyzing Go boards..."
            }

            var kataGoEvalCount = 0
            var kataGoTotalContested = 0

            for (i, frame) in capturedFrames.enumerated() {
                let blockEvals = frame.blockEvals ?? []
                let complexBlocks = blockEvals.filter { needsNNEval($0) }.count
                let totalLibs = blockEvals.reduce(0) { $0 + $1.ditherBudget }
                let _ = blockEvals.isEmpty ? Float(0) :
                    blockEvals.reduce(Float(0)) { $0 + $1.complexity } / Float(blockEvals.count)

                // Run KataGo CoreML on complex blocks
                if self.goEvaluator.isReady && complexBlocks > 0 {
                    let displayBoards = blockToGoBoards(pixels: frame.rgb)
                    if let ownership = self.goEvaluator.evaluate(displayBoards) {
                        kataGoEvalCount += 1
                        kataGoTotalContested += ownership.contestedCount
                    }
                }

                let displayBoards = blockToGoBoards(pixels: frame.rgb)

                await MainActor.run {
                    self.processProgress = Float(i + 1) / Float(totalFrames) * 0.4
                    self.processPhase = "Frame \(i + 1)/\(totalFrames) — \(blockEvals.count) blocks, \(complexBlocks) complex, \(totalLibs) liberties"
                    self.processBoards = displayBoards
                }
            }

            if kataGoEvalCount > 0 {
                await MainActor.run {
                    self.processPhase = "KataGo: \(kataGoEvalCount) frames evaluated, \(kataGoTotalContested) contested positions"
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

            let gifData = GIFEncoder.encode(frames: quantizedFrames, measure: measure)

            await MainActor.run {
                self.processProgress = 1.0
                self.processPhase = "Done"
                self.processBoards = nil
                self.gifData = gifData
                self.gifMeasure = measure
                self.state = .done
            }
        }
    }

    // MARK: - Preview Images

    /// Build the composite quantized preview from palette indices.
    nonisolated func buildPreviewImage(indices: [UInt8]) -> CGImage? {
        let size = CameraConfig.captureSize
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

    /// Build a single-channel grayscale preview (R, G, B, or D).
    nonisolated func buildChannelPreview(values: [Float]) -> CGImage? {
        let size = CameraConfig.captureSize
        var rgba = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<min(size * size, values.count) {
            let v = UInt8(clamping: Int(values[i] * 255))
            rgba[i * 4] = v; rgba[i * 4 + 1] = v; rgba[i * 4 + 2] = v
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &rgba, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        return ctx.makeImage()
    }

    // MARK: - Full-Resolution Block Analysis

    /// Read 18×18 blocks from the FULL CVPixelBuffer and compute Go analysis per block.
    /// This accesses the raw camera data (1608×1206), not the downsampled 64×64.
    /// Returns 4096 BlockEvals — one per output pixel position.
    /// Time: ~27ms per frame. Memory: ~320 KB per frame.
    nonisolated func analyzeBlocks(rgbBuffer: CVPixelBuffer) -> [BlockEval] {
        let rgbW = CVPixelBufferGetWidth(rgbBuffer)
        let rgbH = CVPixelBufferGetHeight(rgbBuffer)
        let outSize = CameraConfig.captureSize  // 64
        let cropSize = min(rgbW, rgbH)
        let cropX = (rgbW - cropSize) / 2
        let cropY = (rgbH - cropSize) / 2
        let step = cropSize / outSize  // ~18

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
