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
import AVFoundation
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

    @Published var state: FaceCaptureState = .idle {
        didSet {
            // Preview work is gated off-state (line pass 2026-08-12):
            // the full CPU pipeline used to keep running at 20 Hz
            // through SOLVING, SEALED, and REFUSED.
            switch state {
            case .previewing, .recording: surfaceLive = true
            default: surfaceLive = false
            }
        }
    }
    @Published var previewImage: CGImage?       // quantized S×S preview
    @Published var faceDetected: Bool = false
    @Published var gifData: Data?
    @Published var gifMeasure: BirkhoffMeasure?
    /// Tri-scale ladder telemetry (mirrors CameraManager) —
    /// measurement only; the anatomical signal rides the same cube.
    @Published private(set) var rungTelemetry: RungTelemetry?
    /// Dissonance telemetry (mirrors CameraManager) — the anatomical
    /// signal rides the depth slot, so urgency reads face-vs-ground.
    @Published private(set) var dissonance: DissonanceTelemetry?
    @Published var processProgress: Float = 0
    @Published var processPhase: String = ""
    /// Palette-creation visibility (Daniel, 2026-08-10): the current
    /// frame's 768-byte DYAD table, published as each is solved.
    @Published var liveTable: Data?

    // ── THE LIVE INSTRUMENTS (spec/ui/WidgetGrid.hs WG12) ────────
    // The FACE twin of CameraManager's instruments — ONE machine and
    // ONE widget surface serve both capture systems, so both must
    // publish the same three values on the same 5 Hz solve cadence
    // (TL8/TL9, keyed on Live.solveSerial).

    /// The 256 entries the surface is DRAWING WITH, packed to 768 B.
    @Published private(set) var liveFrameTable: Data?
    /// The mid read (32² = Rung.mid): pooled feed, export assignment.
    @Published private(set) var preview32: CGImage?
    /// The coarse read (16² = Rung.coarse): THE RESOLUTION OF DEPTH.
    @Published private(set) var preview16: CGImage?

    // MARK: - ARKit Session

    private let session = ARSession()
    private let delegateQueue = DispatchQueue(label: "com.tesseract.arface", qos: .userInteractive)

    // Delegate-queue-only state (all delegate callbacks arrive serially
    // on delegateQueue; never touched from any other context).
    nonisolated(unsafe) private var lastAcceptedTime: Double = -.greatestFiniteMagnitude
    /// Mirrors `state` for the delegate queue: true only while the
    /// surface consumes frames (previewing/recording).
    nonisolated(unsafe) private var surfaceLive = false

    /// Accept a frame only if ≥ 1/21 s after the last accepted one (~20fps).
    nonisolated private static let minFrameSpacing: Double = 1.0 / 21.0

    private let frameBuffer = FrameBuffer()
    /// ★EM12/EM13: the export encoder driven live (CPU; ARKit frames
    /// have no Metal pipeline). Touched ONLY on delegateQueue
    /// (serial) — no locking.
    nonisolated(unsafe) private let live = DyadPipeline.Live()
    /// The last solve serial the instruments were published at —
    /// delegate-queue-only state, like `live` itself.
    nonisolated(unsafe) private var publishedSolveSerial = 0

    // MARK: - Lifecycle

    /// Terminal: no ARKit face tracking on this hardware. ContentView
    /// keys off this string to render the gate (no retry).
    nonisolated static let faceTrackingUnsupportedMessage = "face tracking unsupported"

    func start() {
        guard state == .idle else { return }
        // Same denial handling as the LIVE path: reuse the exact message
        // ContentView keys the Open Settings action off. Without this,
        // a revoked permission surfaces as a raw ARKit error string.
        if case .denied = AVCaptureDevice.authorizationStatus(for: .video) {
            state = .error(CameraManager.cameraDeniedMessage)
            return
        }
        // CENTER STAGE gate — same hardware predicate as the LIVE path
        // (CameraManager.configureSession): the app is for iPhones with
        // the square-sensor Center Stage front camera (iPhone 17 line).
        guard AVCaptureDevice.default(
            .builtInUltraWideCamera, for: .video, position: .front
        ) != nil else {
            state = .error(CameraManager.noCenterStageMessage)
            return
        }
        guard ARFaceTrackingConfiguration.isSupported else {
            state = .error(Self.faceTrackingUnsupportedMessage)
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
        // A second capture's SOLVING screen must not open on the
        // previous capture's palette (line pass 2026-08-12).
        liveTable = nil
        frameBuffer.startRecording()
        state = .recording(0)
    }

    // MARK: - Frame Processing (delegate queue)

    nonisolated private func processFrame(_ frame: ARFrame) {
        // Only the live surface consumes frames — SOLVING, SEALED,
        // and REFUSED do not pay the 20 Hz preview pipeline.
        guard surfaceLive else { return }
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

        // 3. Preview — the export encoder itself (EM13; the anatomical
        // signal rides the depth slot, so γ staging and the mixture
        // posterior apply unchanged); lattice quick-quantize until the
        // first solve. FACE has no Metal pipeline: CPU path.
        let frameIdx = frameBuffer.frameCount
        let previewIndices: [UInt8]
        let previewTable: [(UInt8, UInt8, UInt8)]?
        if let dyadIdx = live.process(rgb: rgb, depths: signalGrid) {
            previewIndices = dyadIdx
            previewTable = live.table
        } else {
            previewIndices = PerfectQuantizer.previewQuantize(
                rgb: rgb, depths: signalGrid, frameIndex: frameIdx)
            previewTable = nil
        }
        let img = Self.buildPreviewImage(indices: previewIndices, size: outSize,
                                         table: previewTable)
        let instruments = liveInstruments(rgb: rgb, depths: signalGrid)

        Task { @MainActor in
            self.previewImage = img
            self.faceDetected = hasFace
            if let instruments {
                self.liveFrameTable = instruments.table
                self.preview32 = instruments.mid
                self.preview16 = instruments.coarse
            }
        }

        // 4. Recording: store raw data ONLY — no heavy analysis during capture.
        if frameBuffer.frameCount < CameraConfig.totalFrames {
            let captured = CapturedFrame(
                index: frameIdx,
                rgb: rgb,
                depths: signalGrid,
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
                    subjectAnalysis: nil,   // no readers (line pass 2026-08-12)
                    anchorTrace: nil,
                    timestamp: frame.timestamp
                ))

                await MainActor.run {
                    self.processProgress = Float(i + 1) / Float(max(1, totalFrames)) * 0.8
                    self.processPhase = "indexing frame \(i + 1)/\(totalFrames)"
                }
            }

            // Encode GIF (80% → 100%).
            await MainActor.run {
                self.processPhase = "solving palettes"
                self.processProgress = 0.85
            }

            // Encode through the 64³ machine: DYAD per-frame palettes,
            // or nil surfaced honestly. The anatomical signal rides the
            // depth slot, so DYAD's face mass = mesh weight here too.
            // The measure describes the EMITTED cube (line pass); the
            // palette solve owns the 85→100% progress span.
            let export = GIFMachine.makeGIF(frames: quantizedFrames,
                                             settings: ExportSettings.load(),
                                             onFrameTable: { [frameTotal = quantizedFrames.count] f, table in
                Task { @MainActor in
                    self.liveTable = table
                    self.processProgress = 0.85 + 0.15 * Float(f + 1) / Float(max(1, frameTotal))
                    self.processPhase = "palette \(f + 1)/\(frameTotal)"
                }
            })

            // Archive every successful export — the library reviews old
            // GIFs + their palettes from the exact encoded bytes.
            if let export { GIFLibrary.archive(export.data) }

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
                self.gifData = export?.data
                self.gifMeasure = export?.measure
                self.rungTelemetry = rungs
                self.dissonance = diss
                // A nil encode is a failure, not a result (mirrors LIVE).
                self.state = export == nil
                    ? .error(CameraManager.encodeFailedMessage) : .done
            }
        }
    }

    // MARK: - Preview Image (mirrors CameraManager.buildPreviewImage)

    /// With a 256-entry `table`, colors come from the live DYAD table
    /// (the unified preview); without, from the tesseract lattice.
    /// The surface's instruments (WG12), read at the SOLVE cadence —
    /// the FACE twin of CameraManager.liveInstruments, calling the
    /// SAME `DyadPipeline.Live` methods. nil when the solve has not
    /// moved since the last publish.
    nonisolated private func liveInstruments(
        rgb: [(Float, Float, Float)], depths: [Float]
    ) -> (table: Data?, mid: CGImage?, coarse: CGImage?)? {
        guard live.solveSerial != publishedSolveSerial else { return nil }
        publishedSolveSerial = live.solveSerial
        let table = live.table
        guard let packed = QuantizedImage.packed(table) else { return nil }
        guard let reads = live.coarseReads(rgb: rgb, depths: depths) else {
            return (packed, nil, nil)
        }
        return (packed,
                QuantizedImage.make(indices: reads.mid,
                                    side: Rung.mid.side, table: table),
                QuantizedImage.make(indices: reads.coarse,
                                    side: Rung.coarse.side, table: table))
    }

    nonisolated private static func buildPreviewImage(
        indices: [UInt8], size: Int,
        table: [(UInt8, UInt8, UInt8)]? = nil
    ) -> CGImage? {
        var rgba = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<min(size * size, indices.count) {
            let (r, g, b): (UInt8, UInt8, UInt8)
            if let table, table.count == 256 {
                (r, g, b) = table[Int(indices[i])]
            } else {
                (r, g, b) = TesseractCoord(index: indices[i]).sRGB8
            }
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

        processFrame(frame)
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        // Permission revocation arrives here as ARError.cameraUnauthorized;
        // map it to the shared denied message so the error surface offers
        // Open Settings instead of echoing a raw system string.
        let message: String
        if let arError = error as? ARError, arError.code == .cameraUnauthorized {
            message = CameraManager.cameraDeniedMessage
        } else {
            // The second register is lowercase by law (line pass).
            message = error.localizedDescription.lowercased()
        }
        logger.error("FaceCapture: session failed — \(message)")
        Task { @MainActor in
            self.state = .error(message)
        }
    }
}
