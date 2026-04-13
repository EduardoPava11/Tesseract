// CameraManager.swift
// Tesseract
//
// TrueDepth front camera: RGB + Depth at 20fps.
// State machine: idle → previewing → recording → done.
// Preview shows EXACTLY what the GIF will capture.

import AVFoundation
import CoreImage
import Combine
import simd

/// Camera state machine
enum CameraState: Equatable {
    case idle              // not started
    case previewing        // live feed, quantized 64×64 shown
    case recording(Int)    // capturing frame N of 64
    case processing        // quantizing + encoding GIF
    case done              // GIF ready
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

/// A captured frame: RGB pixels + depth map, both at 64×64
struct CapturedFrame {
    let frameIndex: Int
    let rgb: [SIMD3<Float>]      // 4096 pixels, sRGB [0,1]
    let depth: [Float]            // 4096 depth values, meters
    let timestamp: TimeInterval
}

/// Constants: accessible from any isolation domain
enum CameraConfig {
    static let captureSize = 64
    static let displayScale = 4
    static let displaySize = captureSize * displayScale  // 256
    static let targetFPS = 20
    static let totalFrames = 64
    static let recordingDuration: TimeInterval = Double(totalFrames) / Double(targetFPS)
}

/// Manages TrueDepth camera capture pipeline
@MainActor
final class CameraManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var state: CameraState = .idle
    @Published var previewImage: CGImage?       // live 64×64 quantized preview
    @Published var previewMeasure: BirkhoffMeasure?
    @Published var depthZones: [DepthZone] = []
    @Published var recordedFrames: [CapturedFrame] = []

    // MARK: - Capture Session

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let processingQueue = DispatchQueue(label: "com.tesseract.camera", qos: .userInteractive)

    // MARK: - Lifecycle

    func start() {
        guard state == .idle else { return }
        Task { await configure() }
    }

    func startRecording() {
        guard state == .previewing else { return }
        recordedFrames.removeAll()
        recordedFrames.reserveCapacity(CameraConfig.totalFrames)
        state = .recording(0)
    }

    func stop() {
        session.stopRunning()
        state = .idle
    }

    // MARK: - Session Configuration

    private func configure() async {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Front TrueDepth camera
        guard let device = AVCaptureDevice.default(
            .builtInTrueDepthCamera, for: .video, position: .front
        ) else {
            state = .error("No TrueDepth camera")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                state = .error("Cannot add camera input")
                return
            }
            session.addInput(input)

            // Configure frame rate
            try device.lockForConfiguration()
            let targetDuration = CMTime(value: 1, timescale: CMTimeScale(CameraConfig.targetFPS))
            device.activeVideoMinFrameDuration = targetDuration
            device.activeVideoMaxFrameDuration = targetDuration
            device.unlockForConfiguration()

            // Video output (RGB)
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(videoOutput) else {
                state = .error("Cannot add video output")
                return
            }
            session.addOutput(videoOutput)

            // Depth output
            guard session.canAddOutput(depthOutput) else {
                state = .error("Cannot add depth output")
                return
            }
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true

            // Square crop: use the center 1:1 region
            if let connection = videoOutput.connection(with: .video) {
                connection.videoRotationAngle = 0
            }

            session.commitConfiguration()

            // Set delegate on processing queue
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            depthOutput.setDelegate(self, callbackQueue: processingQueue)

            session.startRunning()
            state = .previewing

        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Frame Processing

    /// Process a video frame: downsample to 64×64, quantize to tesseract
    nonisolated func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Square crop from center, then downsample to 64×64
        let cropSize = min(width, height)
        let cropX = (width - cropSize) / 2
        let cropY = (height - cropSize) / 2
        let step = cropSize / CameraConfig.captureSize

        var pixels = [SIMD3<Float>]()
        pixels.reserveCapacity(CameraConfig.captureSize * CameraConfig.captureSize)

        for y in 0..<CameraConfig.captureSize {
            for x in 0..<CameraConfig.captureSize {
                let srcX = cropX + x * step + step / 2
                let srcY = cropY + y * step + step / 2
                let offset = srcY * bytesPerRow + srcX * 4  // BGRA

                let b = Float(buffer[offset]) / 255.0
                let g = Float(buffer[offset + 1]) / 255.0
                let r = Float(buffer[offset + 2]) / 255.0
                pixels.append(SIMD3(r, g, b))
            }
        }

        // Quantize to tesseract palette (use frame 0 for preview epoch)
        let indices = TesseractPalette.quantizeFrame(
            frame: 0, pixels: pixels.map { ($0.x, $0.y, $0.z) }
        )

        // Build preview CGImage
        let previewImage = buildPreviewImage(indices: indices)
        let measure = BirkhoffMeasure(paletteIndices: indices)

        Task { @MainActor in
            self.previewImage = previewImage
            self.previewMeasure = measure
        }
    }

    /// Build a 64×64 CGImage from palette indices for preview
    nonisolated func buildPreviewImage(indices: [UInt8]) -> CGImage? {
        let size = CameraConfig.captureSize
        var rgbaData = [UInt8](repeating: 255, count: size * size * 4)

        for i in 0..<(size * size) {
            let (r, g, b) = TesseractCoord(index: indices[i]).sRGB8
            rgbaData[i * 4] = r
            rgbaData[i * 4 + 1] = g
            rgbaData[i * 4 + 2] = b
            // alpha already 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rgbaData,
            width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        return context.makeImage()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        processVideoFrame(sampleBuffer)
    }
}

// MARK: - AVCaptureDepthDataOutputDelegate

extension CameraManager: AVCaptureDepthDataOutputDelegate {
    nonisolated func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        // Convert depth to float map
        let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let depthMap = converted.depthDataMap

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return }

        let floatBuffer = base.assumingMemoryBound(to: Float.self)

        // Find depth range for zone quantization
        var minDepth: Float = .greatestFiniteMagnitude
        var maxDepth: Float = 0
        for i in 0..<(width * height) {
            let d = floatBuffer[i]
            if d.isFinite && d > 0 {
                minDepth = min(minDepth, d)
                maxDepth = max(maxDepth, d)
            }
        }

        // Quantize depth into 4 zones
        let range = max(maxDepth - minDepth, 0.001)
        // Downsample depth to 64×64 and build zones
        // (depth zones update published state for UI)
        let cropSize = min(width, height)
        let cropX = (width - cropSize) / 2
        let cropY = (height - cropSize) / 2
        let step = cropSize / CameraConfig.captureSize

        var depthValues = [Float]()
        depthValues.reserveCapacity(CameraConfig.captureSize * CameraConfig.captureSize)

        for y in 0..<CameraConfig.captureSize {
            for x in 0..<CameraConfig.captureSize {
                let srcX = cropX + x * step + step / 2
                let srcY = cropY + y * step + step / 2
                let idx = srcY * width + srcX
                let d = (idx < width * height) ? floatBuffer[idx] : minDepth
                depthValues.append(d)
            }
        }

        // Quantize to 4 zones
        let zones = quantizeDepthToZones(depthValues, minDepth: minDepth, range: range)

        Task { @MainActor in
            self.depthZones = zones
        }
    }

    /// Partition 64×64 depth map into 4 zones
    nonisolated private func quantizeDepthToZones(
        _ depths: [Float], minDepth: Float, range: Float
    ) -> [DepthZone] {
        var zonePixels: [[UInt8]] = [[], [], [], []]  // placeholder indices per zone
        var zoneCounts = [0, 0, 0, 0]

        for (i, d) in depths.enumerated() {
            let normalized = (d - minDepth) / range
            let zone = min(3, max(0, Int(normalized * 4)))
            zoneCounts[zone] += 1
        }

        return (0..<4).map { level in
            DepthZone(
                level: UInt8(level),
                pixelCount: zoneCounts[level],
                dominantPair: ColorPair(
                    colorA: .black, colorB: .white,
                    countA: 0, countB: 0
                )
            )
        }
    }
}
