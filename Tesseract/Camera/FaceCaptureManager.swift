// FaceCaptureManager.swift
// Tesseract
//
// FACE capture mode: ARKit face mesh → anatomical nearness cadence.
// ARSession replaces AVCaptureSession — they CANNOT coexist on the
// TrueDepth camera. ContentView stops CameraManager fully before this
// manager starts, and vice versa.
//
// Per frame (ARSession delegate queue, HaarScope frame-drop-guard pattern):
//   1. capturedImage (YCbCr 420f) → S×S RGB [0,1] over the largest
//      centered square crop (CPU box-average, BT.601 full range).
//   2. Face mesh → per-vertex signal s_i = 1 − ‖v_i − nose‖/R
//      (FaceMeshSignal, pure), projected via frame.camera.projectPoint
//      into an S×S portrait viewport, rasterized barycentrically.
//      No face anchor ⇒ all zeros.
//   3. CapturedFrame(rgb:depths:timestamp:) — the signal grid rides in
//      .depths so PerfectQuantizer's cadence σ(d) = σ_base(2−d) applies
//      unchanged (1 = nose/crisp, 0 = background/diffuse).
//
// Capture-then-compute: 64 frames at ~20fps (timestamp-throttled), then
// PerfectQuantizer + GIFEncoder exactly like CameraManager's processing path.

import ARKit
import CoreVideo
import os.log

private let logger = Logger(subsystem: "com.tesseract.app", category: "FaceCapture")

/// FACE mode state machine — deliberately its own small enum,
/// mirroring CameraState's shape without entangling with it.
enum FaceCaptureState: Equatable {
    case idle
    case previewing
    case recording(Int)
    case processing
    case done
    case error(String)
}

@MainActor
final class FaceCaptureManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var state: FaceCaptureState = .idle
    @Published var previewImage: CGImage?       // quantized S×S preview
    @Published var faceDetected: Bool = false
    @Published var gifData: Data?
    @Published var gifMeasure: BirkhoffMeasure?
    @Published var processProgress: Float = 0
    @Published var processPhase: String = ""

    // MARK: - ARKit Session

    private let session = ARSession()
    private let delegateQueue = DispatchQueue(label: "com.tesseract.arface", qos: .userInteractive)

    // Delegate-queue-only state (all delegate callbacks arrive serially
    // on delegateQueue; never touched from any other context).
    nonisolated(unsafe) private var isProcessingFrame = false  // frame-drop guard
    nonisolated(unsafe) private var lastAcceptedTime: Double = -.greatestFiniteMagnitude

    /// Accept a frame only if ≥ 1/21 s after the last accepted one (~20fps).
    nonisolated private static let minFrameSpacing: Double = 1.0 / 21.0

    private let frameBuffer = FrameBuffer()

    // MARK: - Lifecycle

    func start() {
        guard state == .idle else { return }
        guard ARFaceTrackingConfiguration.isSupported else {
            state = .error("ARKit face tracking not supported on this device")
            return
        }

        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        config.isLightEstimationEnabled = false

        session.delegate = self
        session.delegateQueue = delegateQueue
        session.run(config, options: [.resetTracking, .removeExistingAnchors])

        state = .previewing
        logger.info("FaceCapture: ARSession running")
    }

    /// Synchronous, full stop — the TrueDepth camera is released so
    /// CameraManager's AVCaptureSession can own it again.
    func stop() {
        session.pause()
        state = .idle
        logger.info("FaceCapture: ARSession paused")
    }

    func startRecording() {
        guard state == .previewing else { return }
        gifData = nil
        gifMeasure = nil
        frameBuffer.startRecording()
        state = .recording(0)
    }

    // MARK: - Frame Processing (delegate queue)

    nonisolated private func processFrame(_ frame: ARFrame) {
        // Throttle to ~20fps by presentation timestamp spacing.
        let timestamp = frame.timestamp
        guard timestamp - lastAcceptedTime >= Self.minFrameSpacing else { return }
        lastAcceptedTime = timestamp

        let outSize = CameraConfig.outputSize

        // 1. YCbCr 420f → S×S RGB over largest centered square crop.
        guard let rgb = Self.convertToGrid(frame.capturedImage, outSize: outSize) else { return }

        // 2. Face mesh → anatomical nearness grid (all zeros if no face).
        let faceAnchor = frame.anchors.compactMap { $0 as? ARFaceAnchor }.first
        let signalGrid: [Float]
        if let face = faceAnchor {
            signalGrid = Self.faceSignalGrid(face: face, camera: frame.camera, outSize: outSize)
        } else {
            signalGrid = [Float](repeating: 0, count: outSize * outSize)
        }
        let hasFace = faceAnchor != nil

        // 3. Preview: quick quantize with the anatomical cadence.
        let frameIdx = frameBuffer.frameCount
        let previewIndices = PerfectQuantizer.previewQuantize(
            rgb: rgb, depths: signalGrid, frameIndex: frameIdx
        )
        let img = Self.buildPreviewImage(indices: previewIndices, size: outSize)

        Task { @MainActor in
            self.previewImage = img
            self.faceDetected = hasFace
        }

        // 4. Recording: store raw data ONLY — no heavy analysis during capture.
        if frameBuffer.frameCount < CameraConfig.totalFrames {
            let captured = CapturedFrame(
                index: frameIdx,
                rgb: rgb,
                depths: signalGrid,
                blockEvals: nil,
                timestamp: timestamp
            )
            if let count = frameBuffer.addCapturedFrame(captured) {
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

    // MARK: - Face Signal Grid

    /// Project the face mesh into the S×S portrait viewport and rasterize
    /// the anatomical-nearness signal. x is mirrored (selfie preview) to
    /// match the RGB conversion below.
    nonisolated private static func faceSignalGrid(
        face: ARFaceAnchor, camera: ARCamera, outSize: Int
    ) -> [Float] {
        let geo = face.geometry
        let vertices = Array(geo.vertices)

        // Signal is computed on FACE-LOCAL vertices (+z out of face),
        // so nose = max z holds regardless of head pose.
        let signals = FaceMeshSignal.vertexSignals(vertices: vertices)

        // Project via ARKit's camera into a square portrait viewport
        // (HaarScope pattern) — matches the centered-crop geometry.
        let viewport = CGSize(width: outSize, height: outSize)
        var positions = [SIMD2<Float>](repeating: .zero, count: vertices.count)
        for i in 0..<vertices.count {
            let local = SIMD4<Float>(vertices[i], 1)
            let world = face.transform * local
            let pt = camera.projectPoint(
                simd_float3(world.x, world.y, world.z),
                orientation: .portrait,
                viewportSize: viewport
            )
            // Mirror x to match the mirrored selfie RGB grid.
            positions[i] = SIMD2<Float>(Float(outSize) - Float(pt.x), Float(pt.y))
        }

        let triangles = geo.triangleIndices.map(Int.init)
        return FaceMeshSignal.rasterize(
            positions: positions,
            signals: signals,
            triangles: triangles,
            gridSize: outSize
        )
    }

    // MARK: - YCbCr → RGB Grid

    /// Convert a 420f YCbCr CVPixelBuffer to outSize² RGB [0,1] over the
    /// largest centered square crop, box-averaging luma and chroma, with
    /// BT.601 full-range conversion. Output is portrait-rotated and
    /// mirrored (selfie), matching the projected face positions.
    nonisolated private static func convertToGrid(
        _ pixelBuffer: CVPixelBuffer, outSize: Int
    ) -> [(Float, Float, Float)]? {
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let w = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        else { return nil }

        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let chromaW = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let chromaH = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let luma = lumaBase.assumingMemoryBound(to: UInt8.self)
        let chroma = chromaBase.assumingMemoryBound(to: UInt8.self)  // interleaved CbCr

        // Largest centered square crop, integer block step.
        let side = min(w, h)
        let step = side / outSize
        guard step >= 1 else { return nil }
        let sampled = step * outSize
        let offX = (w - sampled) / 2
        let offY = (h - sampled) / 2

        var pixels = [(Float, Float, Float)]()
        pixels.reserveCapacity(outSize * outSize)

        for y in 0..<outSize {
            for x in 0..<outSize {
                // Portrait rotation + horizontal mirror:
                // output (x, y) ← source block (col = y, row = x).
                let srcX0 = offX + y * step
                let srcY0 = offY + x * step

                // Box-average luma over the step×step block.
                var ySum = 0
                for sy in srcY0..<(srcY0 + step) {
                    let row = sy * lumaStride
                    for sx in srcX0..<(srcX0 + step) {
                        ySum += Int(luma[row + sx])
                    }
                }
                let yAvg = Float(ySum) / Float(step * step)

                // Box-average chroma over the corresponding half-res block.
                let cx0 = srcX0 / 2
                let cy0 = srcY0 / 2
                let cExt = max(1, step / 2)
                var cbSum = 0, crSum = 0, cCount = 0
                for cy in cy0..<min(cy0 + cExt, chromaH) {
                    let row = cy * chromaStride
                    for cx in cx0..<min(cx0 + cExt, chromaW) {
                        cbSum += Int(chroma[row + cx * 2])
                        crSum += Int(chroma[row + cx * 2 + 1])
                        cCount += 1
                    }
                }
                let cb = cCount > 0 ? Float(cbSum) / Float(cCount) - 128 : 0
                let cr = cCount > 0 ? Float(crSum) / Float(cCount) - 128 : 0

                // BT.601 full range.
                let yf = yAvg / 255.0
                let r = yf + 1.402 * cr / 255.0
                let g = yf - 0.344136 * cb / 255.0 - 0.714136 * cr / 255.0
                let b = yf + 1.772 * cb / 255.0
                pixels.append((
                    max(0, min(1, r)),
                    max(0, min(1, g)),
                    max(0, min(1, b))
                ))
            }
        }

        return pixels
    }

    // MARK: - GIF Encoding (capture-then-compute, mirrors CameraManager)

    private func encodeGIF() {
        let capturedFrames = frameBuffer.exportCapturedFrames()
        let totalFrames = capturedFrames.count

        Task.detached(priority: .userInitiated) {
            // Quantize all frames (0% → 80%) — PerfectQuantizer with the
            // anatomical face signal riding in .depths.
            await MainActor.run {
                self.processProgress = 0
                self.processPhase = "Quantizing face tesseract..."
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
                    self.processProgress = Float(i + 1) / Float(max(1, totalFrames)) * 0.8
                    self.processPhase = "Quantizing frame \(i + 1)/\(totalFrames)"
                }
            }

            // Encode GIF (80% → 100%).
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

            // Pass 2: the anatomical signal rides the depth slot, so face
            // mass = mesh weight here. Frames without rawRGB reduce to the
            // canonical identity — safe either way.
            let refined = CentroidRefiner.refineAuto(frames: quantizedFrames)
            let gifData = GIFEncoder.encode(
                frames: quantizedFrames, measure: measure, upscale: CameraConfig.exportUpscale,
                refined: refined
            )

            await MainActor.run {
                self.processProgress = 1.0
                self.processPhase = ""
                self.gifData = gifData
                self.gifMeasure = measure
                self.state = .done
            }
        }
    }

    // MARK: - Preview Image (mirrors CameraManager.buildPreviewImage)

    nonisolated private static func buildPreviewImage(indices: [UInt8], size: Int) -> CGImage? {
        var rgba = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<min(size * size, indices.count) {
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

// MARK: - ARSessionDelegate

extension FaceCaptureManager: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Drop frame if still processing previous — prevents ARFrame
        // retention buildup (HaarScope pattern).
        guard !isProcessingFrame else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        processFrame(frame)
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        logger.error("FaceCapture: session failed — \(message)")
        Task { @MainActor in
            self.state = .error(message)
        }
    }
}
