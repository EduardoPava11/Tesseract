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
    @Published var previewImage: CGImage?
    @Published var previewMeasure: BirkhoffMeasure?
    @Published var depthZones: [DepthZone] = []
    @Published var gifData: Data?
    @Published var gifMeasure: BirkhoffMeasure?

    // MARK: - Capture

    private let session = AVCaptureSession()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let depthOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    private let processingQueue = DispatchQueue(label: "com.tesseract.camera", qos: .userInteractive)

    // MARK: - Processing

    private let frameBuffer = FrameBuffer()
    nonisolated(unsafe) private var _metalPipeline: MetalPipeline?
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

        } catch {
            state = .error(error.localizedDescription)
            logger.error("Camera: \(error.localizedDescription)")
        }
    }

    // MARK: - Frame Processing

    nonisolated func processFrame(rgbBuffer: CVPixelBuffer, depthBuffer: CVPixelBuffer?) {
        let rgbW = CVPixelBufferGetWidth(rgbBuffer)
        let rgbH = CVPixelBufferGetHeight(rgbBuffer)

        if !Self._loggedOnce {
            Self._loggedOnce = true
            logger.info("Camera: RGB buffer \(rgbW)×\(rgbH)")
            if let db = depthBuffer {
                let dW = CVPixelBufferGetWidth(db)
                let dH = CVPixelBufferGetHeight(db)
                logger.info("Camera: depth buffer \(dW)×\(dH)")
            }
        }

        // Dynamic crop: square from short side, centered
        let outSize = CameraConfig.captureSize
        let cropSize = min(rgbW, rgbH)
        let cropX = (rgbW - cropSize) / 2
        let cropY = (rgbH - cropSize) / 2
        let step = cropSize / outSize
        let half = step / 2

        // Read RGB pixels
        CVPixelBufferLockBaseAddress(rgbBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(rgbBuffer, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(rgbBuffer)
        guard let baseAddr = CVPixelBufferGetBaseAddress(rgbBuffer) else { return }
        let buffer = baseAddr.assumingMemoryBound(to: UInt8.self)

        var pixels = [(Float, Float, Float)]()
        pixels.reserveCapacity(outSize * outSize)

        for y in 0..<outSize {
            for x in 0..<outSize {
                // videoRotationAngle=90 reports portrait dims but pixels may still
                // be in landscape memory layout. Apply 90° CCW to correct.
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

        // Read depth (if available)
        var depthValues: [Float]?
        if let db = depthBuffer {
            depthValues = readDepth(db, outSize: outSize)
        }

        // Quantize
        let depthZones: [UInt8]? = depthValues?.map { d in
            let n = max(0, min(1, d))
            return UInt8(min(3, max(0, Int(n * 4))))
        }

        let frameIdx = frameBuffer.frameCount
        let indices = TesseractPalette.quantizeFrame(
            frame: frameIdx, pixels: pixels, depthZones: depthZones
        )

        // Preview
        let img = buildPreviewImage(indices: indices)
        let measure = BirkhoffMeasure(paletteIndices: indices)

        Task { @MainActor in
            self.previewImage = img
            self.previewMeasure = measure
        }

        // Recording
        if frameBuffer.frameCount < CameraConfig.totalFrames {
            let count = frameBuffer.addQuantizedFrame(
                paletteIndices: indices,
                depth: depthValues,
                timestamp: CACurrentMediaTime()
            )
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
        let frames = frameBuffer.exportFrames()
        let measure = frameBuffer.aggregateMeasure()

        Task.detached(priority: .userInitiated) {
            let gifData = GIFEncoder.encode(frames: frames, measure: measure)
            await MainActor.run {
                self.gifData = gifData
                self.gifMeasure = measure
                self.state = .done
            }
        }
    }

    // MARK: - Preview Image

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
