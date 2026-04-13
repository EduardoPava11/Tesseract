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

            logger.info("MetalPipeline: all 3 pipeline states created")
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
        let size = CameraConfig.captureSize  // 64

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

    /// Convert a depth CVPixelBuffer (Float32) to a Metal texture.
    func makeDepthTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        return makeTexture(from: pixelBuffer, pixelFormat: .r32Float)
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
            let srcW = rgbTexture.width
            let srcH = rgbTexture.height
            let cropSize = min(srcW, srcH)
            let cropX = (srcW - cropSize) / 2
            let cropY = (srcH - cropSize) / 2

            var dsParams = DownsampleParamsSwift(
                srcWidth: UInt32(srcW), srcHeight: UInt32(srcH),
                dstWidth: 64, dstHeight: 64,
                cropX: UInt32(cropX), cropY: UInt32(cropY),
                cropSize: UInt32(cropSize)
            )
            downsampleParamsBuffer?.contents().copyMemory(
                from: &dsParams, byteCount: MemoryLayout<DownsampleParamsSwift>.stride
            )

            encoder.setComputePipelineState(downsampleRGBState)
            encoder.setTexture(rgbTexture, index: 0)
            encoder.setTexture(rgb64, index: 1)
            encoder.setBuffer(downsampleParamsBuffer, offset: 0, index: 0)

            let gridSize = MTLSize(width: 64, height: 64, depth: 1)
            let groupSize = MTLSize(width: 8, height: 8, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)

            // Downsample Depth (if available)
            if let depthTex = depthTexture {
                let depthW = depthTex.width
                let depthH = depthTex.height
                let dCropSize = min(depthW, depthH)

                var ddsParams = DownsampleParamsSwift(
                    srcWidth: UInt32(depthW), srcHeight: UInt32(depthH),
                    dstWidth: 64, dstHeight: 64,
                    cropX: UInt32((depthW - dCropSize) / 2),
                    cropY: UInt32((depthH - dCropSize) / 2),
                    cropSize: UInt32(dCropSize)
                )
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
                epochCenters: SIMD4<Float>(7.875, 23.625, 39.375, 55.125),
                sigmaBase: 7.875,
                frameIndex: UInt32(frameIndex),
                seed: seed,
                width: UInt32(CameraConfig.captureSize),
                height: UInt32(CameraConfig.captureSize),
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

            let gridSize = MTLSize(width: 64, height: 64, depth: 1)
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

struct DownsampleParamsSwift {
    var srcWidth: UInt32
    var srcHeight: UInt32
    var dstWidth: UInt32
    var dstHeight: UInt32
    var cropX: UInt32
    var cropY: UInt32
    var cropSize: UInt32
}
