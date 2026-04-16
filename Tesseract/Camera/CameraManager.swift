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

/// Camera state machine
/// Composition order: which gene is the base?
enum CompositionOrder: Equatable {
    case aIntoB  // A is base, B is residual
    case bIntoA  // B is base, A is residual
}

/// Three-phase state machine: Dual Explore → Compose → Refine
enum CameraState: Equatable {
    case idle
    case previewing
    case recording(Int)
    case processing
    case dualExplore(Int)         // Phase 1: generation counter, two GIFs
    case composing(CompositionOrder)  // Phase 2: instant, compute composite
    case refining(Float)           // Phase 3: α ∈ [0,1], single composite GIF
    case done
    case error(String)

    static func == (lhs: CameraState, rhs: CameraState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.previewing, .previewing),
             (.processing, .processing), (.done, .done): return true
        case (.recording(let a), .recording(let b)): return a == b
        case (.dualExplore(let a), .dualExplore(let b)): return a == b
        case (.composing(let a), .composing(let b)): return a == b
        case (.refining(let a), .refining(let b)): return a == b
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

    // Active mode (Training 64³ or Inference 128³)
    nonisolated(unsafe) static var mode: CubeMode = .training
    static var outputSize: Int { mode.spatialSide }
    static var totalFrames: Int { mode.frameCount }
    static var rgbStep: Int { rgbCrop / outputSize }
    static var depthStep: Int { depthCrop / outputSize }
    static var pixelCount: Int { outputSize * outputSize }

    static let displayScale = 4
    static var displaySize: Int { outputSize * displayScale }
    static let targetFPS = 20
}

@MainActor
final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var state: CameraState = .idle
    @Published var previewImage: CGImage?       // composite quantized preview
    @Published var previewR: CGImage?            // R channel (outputSize² grayscale)
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

    // MARK: - Gene State (three-phase interaction)
    @Published var geneA: GeneWeights = .defaultWeights()
    @Published var geneB: GeneWeights = .defaultWeights()
    @Published var compositeGene: GeneWeights = .defaultWeights()
    @Published var compositeAlpha: Float = 0.5
    @Published var generation: Int = 0
    private var previousGeneA: GeneWeights = .defaultWeights()
    private var previousGeneB: GeneWeights = .defaultWeights()
    private var baseGene: GeneWeights = .defaultWeights()   // for composition
    private var otherGene: GeneWeights = .defaultWeights()  // for composition
    private var sobolExplorer = SobolExplorer()

    // MARK: - Capture

    private let session = AVCaptureSession()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let depthOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private let processingQueue = DispatchQueue(label: "com.tesseract.camera", qos: .userInteractive)

    // MARK: - Processing

    private let frameBuffer = FrameBuffer()
    nonisolated(unsafe) private var _metalPipeline: MetalPipeline?
    // GoEvaluator removed — territory analysis in GoBoard.swift is sufficient
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

    // MARK: - Phase 1: Dual Exploration (↑↓←→ steer BOTH GIFs)

    /// Swipe steers BOTH genes in the same direction.
    /// They diverge because they started from different points.
    func dualSwipe(_ direction: SwipeDirection) {
        guard case .dualExplore = state else { return }
        previousGeneA = geneA
        previousGeneB = geneB

        switch direction {
        case .up:
            geneA = perturbEpochAxis(geneA, scale: 0.03, increase: true)
            geneB = perturbEpochAxis(geneB, scale: 0.03, increase: true)
        case .down:
            geneA = perturbEpochAxis(geneA, scale: 0.03, increase: false)
            geneB = perturbEpochAxis(geneB, scale: 0.03, increase: false)
        case .left:
            geneA = sobolExplorer.perturb(geneA, scale: 0.05)
            geneB = sobolExplorer.perturb(geneB, scale: 0.05)
        case .right:
            geneA = previousGeneA
            geneB = previousGeneB
        }
        generation += 1
        state = .dualExplore(generation)
    }

    // MARK: - Phase 2: Composition (irreversible)

    /// TAP+HOLD drag A→B or B→A triggers composition.
    /// This is IRREVERSIBLE. A and B are consumed.
    func compose(order: CompositionOrder) {
        guard case .dualExplore = state else { return }

        switch order {
        case .aIntoB:
            baseGene = geneA
            otherGene = geneB
        case .bIntoA:
            baseGene = geneB
            otherGene = geneA
        }

        compositeAlpha = 0.5
        compositeGene = composeGenes(base: baseGene, other: otherGene, alpha: compositeAlpha)
        state = .composing(order)

        // Immediately transition to refining
        state = .refining(compositeAlpha)
    }

    /// Compose two genes: base + α × (other - base)
    private func composeGenes(base: GeneWeights, other: GeneWeights, alpha: Float) -> GeneWeights {
        var weights = [Float](repeating: 0, count: GeneWeights.totalCount)
        for i in 0..<GeneWeights.attentionCount {
            let residual = other.weights[i] - base.weights[i]
            weights[i] = base.weights[i] + alpha * residual
        }
        for i in GeneWeights.attentionCount..<GeneWeights.totalCount {
            weights[i] = base.weights[i]  // CORE from base
        }
        return GeneWeights(weights: weights)
    }

    // MARK: - Phase 3: Refinement (CW/CCW adjust α)

    /// Clockwise: increase α (more of the other gene's influence)
    func rotateCW(delta: Float = 0.05) {
        guard case .refining(let alpha) = state else { return }
        compositeAlpha = min(1, alpha + delta)
        compositeGene = composeGenes(base: baseGene, other: otherGene, alpha: compositeAlpha)
        state = .refining(compositeAlpha)
        recomputeGIF()  // Gap 4 fix: GIF updates when α changes
    }

    /// Counter-clockwise: decrease α (back toward base)
    func rotateCCW(delta: Float = 0.05) {
        guard case .refining(let alpha) = state else { return }
        compositeAlpha = max(0, alpha - delta)
        compositeGene = composeGenes(base: baseGene, other: otherGene, alpha: compositeAlpha)
        state = .refining(compositeAlpha)
        recomputeGIF()  // Gap 4 fix: GIF updates when α changes
    }

    /// TAP in any phase = export the current GIF
    func tapExport() {
        // Export is available at any phase — doesn't end the session in Phase 1
        // In Phase 3: TAP exports and ends
        if case .refining = state {
            state = .done
        }
        // In Phase 1: TAP exports but stays in dualExplore (handled by the view)
    }

    /// Build a VoxelCube from the last captured+quantized frames.
    func buildVoxelCube() -> VoxelCube {
        let capturedFrames = frameBuffer.exportCapturedFrames()
        let paletteFrames: [[UInt8]] = capturedFrames.map { frame in
            PerfectQuantizer.quantizeFrame(
                frameIndex: frame.index,
                rgb: frame.rgb,
                depths: frame.depths
            )
        }
        return VoxelCube(frames: paletteFrames)
    }

    /// Recompute GIF from stored capture using current gene (CPU path).
    /// The gene's forward pass produces palette indices directly.
    /// Each swipe produces a DIFFERENT GIF from the SAME capture.
    private func recomputeGIF() {
        let capturedFrames = frameBuffer.exportCapturedFrames()
        guard !capturedFrames.isEmpty else { return }
        let gene = geneA  // Phase 1: use gene A for recompute

        Task.detached(priority: .userInitiated) {
            var quantizedFrames: [QuantizedFrame] = []
            let k = capturedFrames.count

            for frame in capturedFrames {
                // Gene CPU forward pass: each pixel → 137-float input → palette index
                let n = frame.rgb.count
                var indices = [UInt8](repeating: 0, count: n)
                let frameNorm: Float = k > 1 ? Float(frame.index) / Float(k - 1) : 0

                for i in 0..<n {
                    // Build a minimal 137-float input for this pixel.
                    // In production: pre-computed BlockPyramid histograms.
                    // Here: approximate with single-pixel "histogram" (peaked at one bin).
                    let (r, g, b) = frame.rgb[i]
                    let depth = frame.depths[i]

                    var input = [Float](repeating: 0, count: GeneWeights.inputDim)
                    // Slots [0..125]: 3ch × 3scales × 14bins — peak bin only
                    for (chIdx, val) in [(0, r), (1, g), (2, b)] {
                        let bin = min(13, max(0, Int(val * 14)))
                        for scaleIdx in 0..<3 {
                            let offset = chIdx * 42 + scaleIdx * 14
                            input[offset + bin] = 1.0  // peaked frequency
                        }
                    }
                    // Slots 126-127: depth + frame
                    input[126] = depth
                    input[127] = frameNorm
                    // Slots 128-131: sample counts
                    input[128] = 144; input[129] = 36; input[130] = 9
                    input[131] = Float(CameraConfig.depthStep * CameraConfig.depthStep)
                    // Slots 132-136: entropy (uniform for now)
                    for j in 132..<137 { input[j] = 1.0 }

                    let (idx, _g) = gene.forward(input)
                    indices[i] = idx
                    // _g = global weight, used for adaptive palette (future)
                }

                quantizedFrames.append(QuantizedFrame(
                    index: frame.index,
                    paletteIndices: indices,
                    rawRGB: frame.rgb,
                    depths: frame.depths,
                    measure: BirkhoffMeasure(paletteIndices: indices),
                    subjectAnalysis: nil,
                    anchorTrace: nil,
                    timestamp: frame.timestamp
                ))
            }

            // Compute overall measure across all frames
            let overallMeasure: BirkhoffMeasure? = quantizedFrames.isEmpty ? nil : {
                var totalCounts = [Int](repeating: 0, count: 256)
                for frame in quantizedFrames {
                    for idx in frame.paletteIndices { totalCounts[Int(idx)] += 1 }
                }
                let perFrame = totalCounts.map { $0 / max(1, quantizedFrames.count) }
                return BirkhoffMeasure(counts: perFrame)
            }()

            // Compute entropy for MAP-Elites placement
            let allIndices = quantizedFrames.flatMap { $0.paletteIndices }
            let entropy = EntropyMeasure.compute(paletteIndices: allIndices)
            let descriptor = Descriptor.from(entropy)
            let beauty = overallMeasure?.beauty ?? 0

            // Encode GIF
            if let data = GIFEncoder.encode(frames: quantizedFrames, measure: overallMeasure) {
                await MainActor.run {
                    self.gifData = data
                    self.gifMeasure = overallMeasure
                }
            }
        }
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
            // Go territory analysis runs during processing phase, not here

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
        // GPU: parallel texture reads (megapixel → S×S via 768 crop).
        // CPU: deterministic distribution matching (S² pixels).
        // ════════════════════════════════════════════════════════

        // Stage 1: GPU downsample (camera res → S×S with rotation)
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

            let gifData = GIFEncoder.encode(frames: quantizedFrames, measure: measure)

            await MainActor.run {
                self.processProgress = 1.0
                self.processPhase = "Swipe to explore"
                self.processBoards = nil
                self.gifData = gifData
                self.gifMeasure = measure
                self.generation = 0
                self.sobolExplorer.reset()
                // Initialize two genes: A = default, B = perturbed
                self.geneA = GeneWeights.defaultWeights()
                self.geneB = self.geneA.perturbed(scale: 0.05, seed: 42)
                self.state = .dualExplore(0)  // Phase 1: dual exploration
            }
        }
    }

    // MARK: - Preview Images

    /// Build the composite quantized preview from palette indices.
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

    /// Build a single-channel grayscale preview (R, G, B, or D).
    nonisolated func buildChannelPreview(values: [Float]) -> CGImage? {
        let size = CameraConfig.outputSize
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
