// MetalPipeline.swift
// Tesseract
//
// Metal compute pipeline: downsample + quantize in one GPU pass.
// Logging at every step so we can catch exactly where things break.

import Metal
import MetalKit
import CoreVideo
import os.log

/// Logger for the Metal pipeline
private let logger = Logger(subsystem: "com.tesseract.app", category: "MetalPipeline")

/// Drives the Metal compute shaders for real-time tesseract quantization.
final class MetalPipeline {

    // MARK: - Metal State

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let quantizeState: MTLComputePipelineState
    private let downsampleRGBState: MTLComputePipelineState
    private let downsampleDepthState: MTLComputePipelineState
    private let geneForwardState: MTLComputePipelineState?  // Gene NN kernel (optional — may not exist in lib)

    // MARK: - Textures (64×64 working buffers)

    private var rgb64Texture: MTLTexture?
    private var depth64Texture: MTLTexture?

    // MARK: - Output Buffer

    /// 4096 palette indices (64×64)
    private var outputBuffer: MTLBuffer?

    // MARK: - Debug Buffers

    /// 4 epoch counters (atomic uint per epoch)
    private var epochCountsBuffer: MTLBuffer?
    /// 32-bin sigma histogram
    private var sigmaHistBuffer: MTLBuffer?

    // MARK: - Params

    private var paramsBuffer: MTLBuffer?
    private var downsampleParamsBuffer: MTLBuffer?
    private var downsampleDepthParamsBuffer: MTLBuffer?

    // Gene NN buffers (for geneForward kernel)
    private var geneHistogramBuffer: MTLBuffer?   // 126 floats × S² pixels
    private var geneWeightsBuffer: MTLBuffer?     // 4581 floats (gene weights)
    private var geneMetaBuffer: MTLBuffer?        // GeneMetaParams (48 bytes)
    private var geneOutputBuffer: MTLBuffer?      // S² UInt8 palette indices
    private var geneGlobalBuffer: MTLBuffer?      // S² Float global weights

    // MARK: - Texture Cache (CVPixelBuffer → MTLTexture)

    private var textureCache: CVMetalTextureCache?

    // MARK: - Status

    private(set) var isReady = false
    private(set) var lastError: String?
    private var frameCount: UInt64 = 0

    // MARK: - Init

    init?() {
        logger.info("MetalPipeline: initializing...")

        guard let device = MTLCreateSystemDefaultDevice() else {
            logger.error("MetalPipeline: no Metal device available")
            return nil
        }
        self.device = device
        logger.info("MetalPipeline: device = \(device.name)")

        guard let queue = device.makeCommandQueue() else {
            logger.error("MetalPipeline: failed to create command queue")
            return nil
        }
        self.commandQueue = queue
        logger.info("MetalPipeline: command queue created")

        // Load shader library
        guard let library = device.makeDefaultLibrary() else {
            logger.error("MetalPipeline: failed to load default Metal library — check that Quantize.metal is compiled")
            return nil
        }
        logger.info("MetalPipeline: Metal library loaded, functions: \(library.functionNames)")

        // Create compute pipeline states
        do {
            guard let quantizeFn = library.makeFunction(name: "quantizeWithDepth") else {
                logger.error("MetalPipeline: function 'quantizeWithDepth' not found")
                return nil
            }
            self.quantizeState = try device.makeComputePipelineState(function: quantizeFn)
            logger.info("MetalPipeline: quantizeWithDepth pipeline created (maxThreads=\(self.quantizeState.maxTotalThreadsPerThreadgroup))")

            guard let downsampleRGBFn = library.makeFunction(name: "downsampleRGB") else {
                logger.error("MetalPipeline: function 'downsampleRGB' not found")
                return nil
            }
            self.downsampleRGBState = try device.makeComputePipelineState(function: downsampleRGBFn)

            guard let downsampleDepthFn = library.makeFunction(name: "downsampleDepth") else {
                logger.error("MetalPipeline: function 'downsampleDepth' not found")
                return nil
            }
            self.downsampleDepthState = try device.makeComputePipelineState(function: downsampleDepthFn)

            // Gene NN kernel (optional — graceful if missing)
            if let geneForwardFn = library.makeFunction(name: "geneForward") {
                self.geneForwardState = try device.makeComputePipelineState(function: geneForwardFn)
                logger.info("MetalPipeline: geneForward pipeline created")
            } else {
                self.geneForwardState = nil
                logger.warning("MetalPipeline: geneForward not found — GPU NN disabled, CPU fallback")
            }

            logger.info("MetalPipeline: all pipeline states created")
        } catch {
            logger.error("MetalPipeline: pipeline creation failed: \(error.localizedDescription)")
            return nil
        }

        // Allocate working textures and buffers
        if !allocateResources() {
            return nil
        }

        // Verify struct alignment matches Metal expectations
        let qSize = MemoryLayout<QuantizeParamsSwift>.stride
        let qStride = MemoryLayout<QuantizeParamsSwift>.stride
        let dsSize = MemoryLayout<DownsampleParamsSwift>.stride
        logger.info("MetalPipeline: QuantizeParams size=\(qSize) stride=\(qStride) (Metal expects 48)")
        logger.info("MetalPipeline: DownsampleParams size=\(dsSize)")
        if qStride < 48 {
            logger.error("MetalPipeline: QuantizeParams stride \(qStride) < 48 — ALIGNMENT MISMATCH")
        }

        isReady = true
        logger.info("MetalPipeline: ready ✓")
    }

    // MARK: - Resource Allocation

    private func allocateResources() -> Bool {
        let size = CameraConfig.outputSize  // 64

        // 64×64 RGBA Float16 textures
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: size, height: size,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]

        rgb64Texture = device.makeTexture(descriptor: desc)
        depth64Texture = device.makeTexture(descriptor: desc)

        guard rgb64Texture != nil, depth64Texture != nil else {
            logger.error("MetalPipeline: failed to create 64×64 textures")
            return false
        }
        logger.info("MetalPipeline: 64×64 working textures allocated")

        // Output: 4096 bytes
        outputBuffer = device.makeBuffer(length: size * size, options: .storageModeShared)
        guard outputBuffer != nil else {
            logger.error("MetalPipeline: failed to create output buffer")
            return false
        }

        // Debug: epoch counts (4 × UInt32)
        epochCountsBuffer = device.makeBuffer(length: 4 * MemoryLayout<UInt32>.size, options: .storageModeShared)

        // Debug: sigma histogram (32 × UInt32)
        sigmaHistBuffer = device.makeBuffer(length: 32 * MemoryLayout<UInt32>.size, options: .storageModeShared)

        // Params buffers — use STRIDE not size to match Metal alignment
        paramsBuffer = device.makeBuffer(length: MemoryLayout<QuantizeParamsSwift>.stride, options: .storageModeShared)
        downsampleParamsBuffer = device.makeBuffer(length: MemoryLayout<DownsampleParamsSwift>.stride, options: .storageModeShared)
        downsampleDepthParamsBuffer = device.makeBuffer(length: MemoryLayout<DownsampleParamsSwift>.stride, options: .storageModeShared)

        // Gene NN buffers (for geneForward kernel)
        let pixelCount = size * size
        geneHistogramBuffer = device.makeBuffer(length: pixelCount * 126 * MemoryLayout<Float>.size, options: .storageModeShared)
        geneWeightsBuffer = device.makeBuffer(length: GeneWeights.totalCount * MemoryLayout<Float>.size, options: .storageModeShared)
        geneMetaBuffer = device.makeBuffer(length: MemoryLayout<GeneMetaParams>.stride, options: .storageModeShared)
        geneOutputBuffer = device.makeBuffer(length: pixelCount, options: .storageModeShared)
        geneGlobalBuffer = device.makeBuffer(length: pixelCount * MemoryLayout<Float>.size, options: .storageModeShared)

        if geneHistogramBuffer != nil && geneWeightsBuffer != nil {
            logger.info("MetalPipeline: gene NN buffers allocated (hist=\(pixelCount * 126 * 4) bytes, weights=\(GeneWeights.totalCount * 4) bytes)")
        } else {
            logger.warning("MetalPipeline: gene NN buffer allocation failed — GPU NN disabled")
        }

        // Texture cache for CVPixelBuffer → MTLTexture conversion
        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        if cacheStatus == kCVReturnSuccess, let cache = cache {
            self.textureCache = cache
            logger.info("MetalPipeline: texture cache created")
        } else {
            logger.error("MetalPipeline: failed to create texture cache (status=\(cacheStatus))")
            return false
        }

        logger.info("MetalPipeline: all buffers allocated")
        return true
    }

    // MARK: - CVPixelBuffer → MTLTexture

    /// Convert a CVPixelBuffer (from camera) to a Metal texture.
    /// Returns nil with logged error on failure.
    func makeTexture(from pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        guard let cache = textureCache else {
            logger.error("MetalPipeline: texture cache is nil")
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            pixelFormat, width, height, 0, &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTex = cvTexture else {
            logger.error("MetalPipeline: CVMetalTexture creation failed (status=\(status), \(width)×\(height), format=\(pixelFormat.rawValue))")
            return nil
        }

        guard let texture = CVMetalTextureGetTexture(cvTex) else {
            logger.error("MetalPipeline: CVMetalTextureGetTexture returned nil")
            return nil
        }

        return texture
    }

    /// Convert a depth CVPixelBuffer to a Metal texture.
    /// Detects Float16 vs Float32 format dynamically (TrueDepth delivers Float16).
    func makeDepthTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let metalFmt: MTLPixelFormat = (fmt == kCVPixelFormatType_DepthFloat16) ? .r16Float : .r32Float
        return makeTexture(from: pixelBuffer, pixelFormat: metalFmt)
    }

    // MARK: - Process One Frame

    /// Process a camera frame: downsample + quantize → palette indices.
    /// Returns nil on failure with error logged.
    func processFrame(
        rgbTexture: MTLTexture,
        depthTexture: MTLTexture?,
        frameIndex: Int,
        seed: UInt32 = 42
    ) -> [UInt8]? {
        guard isReady else {
            logger.error("MetalPipeline: processFrame called but pipeline not ready")
            return nil
        }

        frameCount += 1
        let logThisFrame = (frameCount % 20 == 0)  // log every 20th frame

        if logThisFrame {
            logger.debug("MetalPipeline: frame \(frameIndex), src RGB=\(rgbTexture.width)×\(rgbTexture.height)")
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            logger.error("MetalPipeline: failed to create command buffer at frame \(frameIndex)")
            return nil
        }

        // ── Step 1: Downsample RGB to 64×64 ──

        guard let rgb64 = rgb64Texture, let depth64 = depth64Texture else {
            logger.error("MetalPipeline: working textures are nil at frame \(frameIndex)")
            return nil
        }

        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            // Downsample RGB
            // Dynamic crop from actual buffer dimensions
            let srcW = rgbTexture.width
            let srcH = rgbTexture.height
            var dsParams = DownsampleParamsSwift.fromRGBBuffer(width: srcW, height: srcH)
            downsampleParamsBuffer?.contents().copyMemory(
                from: &dsParams, byteCount: MemoryLayout<DownsampleParamsSwift>.stride
            )

            encoder.setComputePipelineState(downsampleRGBState)
            encoder.setTexture(rgbTexture, index: 0)
            encoder.setTexture(rgb64, index: 1)
            encoder.setBuffer(downsampleParamsBuffer, offset: 0, index: 0)

            let gridSize = MTLSize(width: CameraConfig.outputSize, height: CameraConfig.outputSize, depth: 1)
            let groupSize = MTLSize(width: 8, height: 8, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)

            // Downsample Depth (if available)
            if let depthTex = depthTexture {
                let depthW = depthTex.width
                let depthH = depthTex.height
                let _ = min(depthW, depthH)

                // Dynamic crop for depth
                var ddsParams = DownsampleParamsSwift.fromDepthBuffer(width: depthW, height: depthH)
                downsampleParamsBuffer?.contents().copyMemory(
                    from: &ddsParams, byteCount: MemoryLayout<DownsampleParamsSwift>.stride
                )

                encoder.setComputePipelineState(downsampleDepthState)
                encoder.setTexture(depthTex, index: 0)
                encoder.setTexture(depth64, index: 1)
                encoder.setBuffer(downsampleParamsBuffer, offset: 0, index: 0)
                encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)

                if logThisFrame {
                    logger.debug("MetalPipeline: depth texture \(depthW)×\(depthH) → 64×64")
                }
            } else {
                // No depth: fill with 0.5 (mid-range)
                if logThisFrame {
                    logger.debug("MetalPipeline: no depth texture, using default d=0.5")
                }
            }

            encoder.endEncoding()
        } else {
            logger.error("MetalPipeline: failed to create downsample encoder at frame \(frameIndex)")
            return nil
        }

        // ── Step 2: Quantize with depth-driven SNR ──

        // Clear debug counters
        if let buf = epochCountsBuffer {
            memset(buf.contents(), 0, buf.length)
        }
        if let buf = sigmaHistBuffer {
            memset(buf.contents(), 0, buf.length)
        }

        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            var params = QuantizeParamsSwift(
                epochCenters: BinomialCadence.centers,
                sigmaBase: BinomialCadence.sigmaBase,
                frameIndex: UInt32(frameIndex),
                seed: seed,
                width: UInt32(CameraConfig.outputSize),
                height: UInt32(CameraConfig.outputSize),
                debugFlags: logThisFrame ? 1 : 0
            )

            paramsBuffer?.contents().copyMemory(
                from: &params, byteCount: MemoryLayout<QuantizeParamsSwift>.stride
            )

            encoder.setComputePipelineState(quantizeState)
            encoder.setTexture(rgb64, index: 0)
            encoder.setTexture(depth64, index: 1)
            encoder.setBuffer(outputBuffer, offset: 0, index: 0)
            encoder.setBuffer(paramsBuffer, offset: 0, index: 1)
            encoder.setBuffer(epochCountsBuffer, offset: 0, index: 2)
            encoder.setBuffer(sigmaHistBuffer, offset: 0, index: 3)

            let gridSize = MTLSize(width: CameraConfig.outputSize, height: CameraConfig.outputSize, depth: 1)
            let groupSize = MTLSize(width: 8, height: 8, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)
            encoder.endEncoding()
        } else {
            logger.error("MetalPipeline: failed to create quantize encoder at frame \(frameIndex)")
            return nil
        }

        // ── Submit and wait ──
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            logger.error("MetalPipeline: GPU error at frame \(frameIndex): \(error.localizedDescription)")
            lastError = error.localizedDescription
            return nil
        }

        // ── Read output ──
        guard let outBuf = outputBuffer else {
            logger.error("MetalPipeline: output buffer nil at frame \(frameIndex)")
            return nil
        }

        let ptr = outBuf.contents().bindMemory(to: UInt8.self, capacity: 4096)
        let indices = Array(UnsafeBufferPointer(start: ptr, count: 4096))

        // ── Debug logging ──
        if logThisFrame {
            logDebugCounters(frameIndex: frameIndex)
        }

        return indices
    }

    // MARK: - Downsample Only (consolidated path)

    /// GPU Stage: downsample camera textures to 64×64, then read back for CPU.
    /// Does NOT run the quantize kernel — CPU handles quantization via PerfectQuantizer.
    /// Uses SEPARATE param buffers for RGB and depth to avoid the overwrite bug.
    func downsampleFrame(
        rgbTexture: MTLTexture,
        depthTexture: MTLTexture?
    ) -> (rgb: [(Float, Float, Float)], depth: [Float])? {
        guard isReady else { return nil }

        frameCount += 1
        let logThis = (frameCount % 20 == 0)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        guard let rgb64 = rgb64Texture, let depth64 = depth64Texture else { return nil }

        // ── Downsample RGB + Depth in one encoder, SEPARATE param buffers ──

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        let gridSize = MTLSize(width: CameraConfig.outputSize, height: CameraConfig.outputSize, depth: 1)
        let groupSize = MTLSize(width: 8, height: 8, depth: 1)

        // RGB downsample → rgb64Texture
        var rgbParams = DownsampleParamsSwift.fromRGBBuffer(width: rgbTexture.width, height: rgbTexture.height)
        downsampleParamsBuffer?.contents().copyMemory(
            from: &rgbParams, byteCount: MemoryLayout<DownsampleParamsSwift>.stride
        )
        encoder.setComputePipelineState(downsampleRGBState)
        encoder.setTexture(rgbTexture, index: 0)
        encoder.setTexture(rgb64, index: 1)
        encoder.setBuffer(downsampleParamsBuffer, offset: 0, index: 0)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)

        // Depth downsample → depth64Texture (separate buffer!)
        if let depthTex = depthTexture {
            var depthParams = DownsampleParamsSwift.fromDepthBuffer(width: depthTex.width, height: depthTex.height)
            downsampleDepthParamsBuffer?.contents().copyMemory(
                from: &depthParams, byteCount: MemoryLayout<DownsampleParamsSwift>.stride
            )
            encoder.setComputePipelineState(downsampleDepthState)
            encoder.setTexture(depthTex, index: 0)
            encoder.setTexture(depth64, index: 1)
            encoder.setBuffer(downsampleDepthParamsBuffer, offset: 0, index: 0)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)
        }

        encoder.endEncoding()

        // Submit and wait
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if commandBuffer.error != nil { return nil }

        // ── Read back both textures ──

        guard let rgbData = readbackRGB(), let depthData = readbackDepth() else { return nil }

        if logThis {
            logger.debug("MetalPipeline: downsample \(rgbTexture.width)×\(rgbTexture.height) → 64×64, depth=\(depthTexture != nil)")
        }

        return (rgb: rgbData, depth: depthData)
    }

    // MARK: - Texture Readback (for CPU perfect pass)

    /// Read back the downsampled 64×64 RGB texture after GPU processing.
    /// Call only after processFrame() succeeds (textures are filled).
    func readbackRGB() -> [(Float, Float, Float)]? {
        guard let tex = rgb64Texture else { return nil }
        let size = CameraConfig.outputSize  // 64
        let pixelCount = size * size

        // rgba16Float: 4 × Float16 = 8 bytes per pixel
        var rawData = [UInt16](repeating: 0, count: pixelCount * 4)
        tex.getBytes(&rawData,
                     bytesPerRow: size * 4 * MemoryLayout<UInt16>.size,
                     from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                     size: MTLSize(width: size, height: size, depth: 1)),
                     mipmapLevel: 0)

        // Convert Float16 RGBA → (Float, Float, Float) RGB
        var result = [(Float, Float, Float)]()
        result.reserveCapacity(pixelCount)
        for i in 0..<pixelCount {
            let r = Float(Float16(bitPattern: rawData[i * 4]))
            let g = Float(Float16(bitPattern: rawData[i * 4 + 1]))
            let b = Float(Float16(bitPattern: rawData[i * 4 + 2]))
            result.append((r, g, b))
        }
        return result
    }

    /// Read back the downsampled 64×64 depth texture after GPU processing.
    func readbackDepth() -> [Float]? {
        guard let tex = depth64Texture else { return nil }
        let size = CameraConfig.outputSize
        let pixelCount = size * size

        // rgba16Float for depth: only R channel used
        var rawData = [UInt16](repeating: 0, count: pixelCount * 4)
        tex.getBytes(&rawData,
                     bytesPerRow: size * 4 * MemoryLayout<UInt16>.size,
                     from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                     size: MTLSize(width: size, height: size, depth: 1)),
                     mipmapLevel: 0)

        return (0..<pixelCount).map { i in
            let f = Float(Float16(bitPattern: rawData[i * 4]))
            return f.isFinite && f > 0 ? f : 0.5
        }
    }

    // MARK: - Debug Logging

    private func logDebugCounters(frameIndex: Int) {
        // Epoch distribution
        if let buf = epochCountsBuffer {
            let ptr = buf.contents().bindMemory(to: UInt32.self, capacity: 4)
            let counts = (0..<4).map { ptr[$0] }
            logger.info("MetalPipeline: frame \(frameIndex) epochs: [\(counts[0]), \(counts[1]), \(counts[2]), \(counts[3])]")
        }

        // Sigma histogram (summary: min, max, peak)
        if let buf = sigmaHistBuffer {
            let ptr = buf.contents().bindMemory(to: UInt32.self, capacity: 32)
            let hist = (0..<32).map { ptr[$0] }
            let total = hist.reduce(0, +)
            if total > 0 {
                let minBin = hist.firstIndex(where: { $0 > 0 }) ?? 0
                let maxBin = hist.lastIndex(where: { $0 > 0 }) ?? 31
                let peakBin = hist.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
                let sigmaMin = 7.0 + Float(minBin) * 9.0 / 32.0
                let sigmaMax = 7.0 + Float(maxBin) * 9.0 / 32.0
                let sigmaPeak = 7.0 + Float(peakBin) * 9.0 / 32.0
                logger.info("MetalPipeline: frame \(frameIndex) σ range: [\(String(format: "%.1f", sigmaMin)), \(String(format: "%.1f", sigmaMax))], peak=\(String(format: "%.1f", sigmaPeak))")
            }
        }
    }

    // MARK: - Gene NN GPU Dispatch

    /// Run the geneForward kernel on GPU.
    /// Inputs: pre-computed histogram data + depths + gene weights + metadata.
    /// Outputs: palette indices + global weights.
    func processWithGene(
        histograms: [Float],    // 126 × S² floats (pre-flattened BlockPyramid histograms)
        depths: [Float],        // S² depth values
        weights: GeneWeights,   // gene weights (4581 floats)
        meta: GeneMetaParams    // frame metadata
    ) -> (indices: [UInt8], globalWeights: [Float])? {
        guard let pso = geneForwardState,
              let histBuf = geneHistogramBuffer,
              let depthBuf = geneOutputBuffer,  // reuse for depth input
              let wBuf = geneWeightsBuffer,
              let metaBuf = geneMetaBuffer,
              let outBuf = geneOutputBuffer,
              let gBuf = geneGlobalBuffer,
              let cmdBuf = commandQueue.makeCommandBuffer()
        else {
            logger.warning("MetalPipeline: gene GPU dispatch unavailable — PSO or buffers nil")
            return nil
        }

        let s = Int(meta.width)
        let pixelCount = s * s

        // Upload histogram data
        histBuf.contents().copyMemory(from: histograms, byteCount: min(histograms.count * 4, histBuf.length))

        // Upload depths into a separate section or use a dedicated buffer
        // For now: depths are passed via the gene meta or a dedicated buffer
        // TODO: allocate separate depth input buffer for geneForward

        // Upload weights
        wBuf.contents().copyMemory(from: weights.weights, byteCount: min(weights.weights.count * 4, wBuf.length))

        // Upload metadata
        var metaCopy = meta
        metaBuf.contents().copyMemory(from: &metaCopy, byteCount: MemoryLayout<GeneMetaParams>.stride)

        // Dispatch
        guard let encoder = cmdBuf.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(pso)
        encoder.setBuffer(histBuf, offset: 0, index: 0)   // histograms
        // depths at index 1 — need dedicated buffer (TODO)
        encoder.setBuffer(outBuf, offset: 0, index: 2)    // output indices
        encoder.setBuffer(gBuf, offset: 0, index: 3)      // global weights
        encoder.setBuffer(wBuf, offset: 0, index: 4)      // gene weights
        encoder.setBuffer(metaBuf, offset: 0, index: 5)   // metadata

        let gridSize = MTLSize(width: s, height: s, depth: 1)
        let groupSize = MTLSize(width: 8, height: 8, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)
        encoder.endEncoding()

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        // Read back results
        let indexPtr = outBuf.contents().bindMemory(to: UInt8.self, capacity: pixelCount)
        let indices = Array(UnsafeBufferPointer(start: indexPtr, count: pixelCount))

        let globalPtr = gBuf.contents().bindMemory(to: Float.self, capacity: pixelCount)
        let globals = Array(UnsafeBufferPointer(start: globalPtr, count: pixelCount))

        logger.info("MetalPipeline: geneForward dispatched \(s)×\(s) → \(indices.filter { $0 > 0 }.count) non-zero indices")

        return (indices, globals)
    }
}

// MARK: - Param Structs (must match Metal struct layout)

// Must match Metal struct QuantizeParams layout exactly (48 bytes).
// float4 first to avoid 16-byte alignment padding.
struct QuantizeParamsSwift {
    var epochCenters: SIMD4<Float>  // offset 0  (16 bytes)
    var sigmaBase: Float            // offset 16 (4 bytes)
    var frameIndex: UInt32          // offset 20
    var seed: UInt32                // offset 24
    var width: UInt32               // offset 28
    var height: UInt32              // offset 32
    var debugFlags: UInt32          // offset 36
    var _pad: UInt32 = 0            // offset 40 (pad to 48)
}

// Must match Metal DownsampleParams (24 bytes: 6 × UInt32)
struct DownsampleParamsSwift {
    var cropX: UInt32
    var cropY: UInt32
    var step: UInt32
    var halfStep: UInt32
    var outputSize: UInt32
    var _pad: UInt32 = 0

    /// Compute params from actual buffer dimensions + universal 768 crop.
    /// Crop is FORCED to 768 (RGB) or 256 (depth), centered in buffer.
    static func fromRGBBuffer(width: Int, height: Int) -> DownsampleParamsSwift {
        let cropSize = CameraConfig.rgbCrop  // 768, always
        let cropX = (width - cropSize) / 2
        let cropY = (height - cropSize) / 2
        let step = CameraConfig.rgbStep     // 768 / outputSize, integer
        return DownsampleParamsSwift(
            cropX: UInt32(cropX), cropY: UInt32(cropY),
            step: UInt32(step), halfStep: UInt32(step / 2),
            outputSize: UInt32(CameraConfig.outputSize)
        )
    }

    static func fromDepthBuffer(width: Int, height: Int) -> DownsampleParamsSwift {
        let cropSize = CameraConfig.depthCrop  // 256, always
        let cropX = (width - cropSize) / 2
        let cropY = (height - cropSize) / 2
        let step = CameraConfig.depthStep     // 256 / outputSize, integer
        return DownsampleParamsSwift(
            cropX: UInt32(cropX), cropY: UInt32(cropY),
            step: UInt32(step), halfStep: UInt32(step / 2),
            outputSize: UInt32(CameraConfig.outputSize)
        )
    }
}
