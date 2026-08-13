// MetalPipeline.swift
// Tesseract
//
// Metal compute pipeline: camera-resolution downsample to the 64² grid
// plus the aerialPreview kernel dispatch (the 20 Hz GPU preview twin).
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
    private let downsampleRGBState: MTLComputePipelineState
    private let downsampleDepthState: MTLComputePipelineState
    /// The 20 Hz preview assignment under the Aerial Mirror Law —
    /// optional: absent kernel ⇒ CPU fallback (DyadPipeline.Live.assign).
    private let aerialState: MTLComputePipelineState?

    // MARK: - Textures (64×64 working buffers)

    private var rgb64Texture: MTLTexture?
    private var depth64Texture: MTLTexture?

    // MARK: - Params

    private var downsampleParamsBuffer: MTLBuffer?
    private var downsampleDepthParamsBuffer: MTLBuffer?

    // Aerial preview buffers (128 primaries + params + 4096 indices)
    private var aerialPrimsBuffer: MTLBuffer?
    private var aerialParamsBuffer: MTLBuffer?
    private var aerialOutBuffer: MTLBuffer?
    /// ★PAIR TREE P2: 16 depth-4 node means (w = canonical leaf).
    private var aerialNodesBuffer: MTLBuffer?
    /// CVMetalTexture wrappers for the in-flight frame (see
    /// makeTexture) — filled per frame, cleared after the wait.
    private var liveCVTextures: [CVMetalTexture] = []

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

            // Aerial preview kernel (optional — CPU fallback if absent)
            if let aerialFn = library.makeFunction(name: "aerialPreview") {
                self.aerialState = try device.makeComputePipelineState(function: aerialFn)
                logger.info("MetalPipeline: aerialPreview pipeline created")
            } else {
                self.aerialState = nil
                logger.warning("MetalPipeline: aerialPreview not found — preview assignment on CPU")
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
        let dsSize = MemoryLayout<DownsampleParamsSwift>.stride
        logger.info("MetalPipeline: DownsampleParams size=\(dsSize)")

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

        // Params buffers — use STRIDE not size to match Metal alignment
        downsampleParamsBuffer = device.makeBuffer(length: MemoryLayout<DownsampleParamsSwift>.stride, options: .storageModeShared)
        downsampleDepthParamsBuffer = device.makeBuffer(length: MemoryLayout<DownsampleParamsSwift>.stride, options: .storageModeShared)

        // Aerial preview: 128 float4 primaries + 48-byte params + indices
        aerialPrimsBuffer = device.makeBuffer(
            length: 128 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)
        aerialParamsBuffer = device.makeBuffer(
            length: MemoryLayout<AerialParamsSwift>.stride, options: .storageModeShared)
        aerialOutBuffer = device.makeBuffer(length: size * size, options: .storageModeShared)
        // ★PAIR TREE P2: the 32-level node targets (16 × float4).
        aerialNodesBuffer = device.makeBuffer(
            length: 16 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)

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

        // Hold the wrapper until this frame's GPU work completes —
        // dropping it here let the pixel-buffer pool recycle the
        // texture's backing mid-read (line pass 2026-08-12).
        liveCVTextures.append(cvTex)
        return texture
    }

    /// Convert a depth CVPixelBuffer to a Metal texture.
    /// Detects Float16 vs Float32 format dynamically (TrueDepth delivers Float16).
    func makeDepthTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let metalFmt: MTLPixelFormat = (fmt == kCVPixelFormatType_DepthFloat16) ? .r16Float : .r32Float
        return makeTexture(from: pixelBuffer, pixelFormat: metalFmt)
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
        // The frame's GPU reads are done: release the CVMetalTexture
        // wrappers (their backing buffers may now be recycled).
        liveCVTextures.removeAll(keepingCapacity: true)

        if commandBuffer.error != nil { return nil }

        // ── Read back both textures ──
        // No depth texture this frame → neutral fill. Reading depth64Texture
        // here would resurrect the PREVIOUS frame's depth (stale contents).

        guard let rgbData = readbackRGB() else { return nil }
        let depthData: [Float]
        if depthTexture != nil {
            guard let d = readbackDepth() else { return nil }
            depthData = d
        } else {
            depthData = [Float](repeating: DepthSignal.fill,
                                count: CameraConfig.outputSize * CameraConfig.outputSize)
        }

        if logThis {
            logger.debug("MetalPipeline: downsample \(rgbTexture.width)×\(rgbTexture.height) → 64×64, depth=\(depthTexture != nil)")
        }

        return (rgb: rgbData, depth: depthData)
    }

    // MARK: - Aerial Preview Assignment (20 Hz GPU twin of Live.assign)

    /// Run the aerialPreview kernel against the CURRENT rgb64/depth64
    /// working textures (call immediately after downsampleFrame on the
    /// same serial queue — the textures are that frame's). Returns the
    /// 4096 palette indices, or nil (kernel absent / not ready) so the
    /// caller falls back to the CPU reference. Preview-only: near-tie
    /// fp32 flips vs the CPU are the only permitted difference.
    func aerialAssign(state: DyadPipeline.MetalState) -> [UInt8]? {
        guard isReady,
              let aerialState,
              let rgb64 = rgb64Texture, let depth64 = depth64Texture,
              let primsBuf = aerialPrimsBuffer,
              let paramsBuf = aerialParamsBuffer,
              let outBuf = aerialOutBuffer,
              let nodesBuf = aerialNodesBuffer,
              state.primaries.count == 128,
              state.nodes.count <= 16 else { return nil }

        var prims = state.primaries
        primsBuf.contents().copyMemory(
            from: &prims, byteCount: 128 * MemoryLayout<SIMD4<Float>>.stride)
        if !state.nodes.isEmpty {
            var nodes = state.nodes
            nodesBuf.contents().copyMemory(
                from: &nodes,
                byteCount: state.nodes.count * MemoryLayout<SIMD4<Float>>.stride)
        }
        var params = AerialParamsSwift(
            centroid: SIMD4<Float>(state.centroid.x, state.centroid.y,
                                   state.centroid.z, 0),
            scalars: SIMD4<Float>(state.sStar, state.tau,
                                  1 / Float(DepthSignal.dNear),
                                  1 / Float(DepthSignal.dFar)),
            flags: SIMD4<UInt32>(state.twoPhase ? 1 : 0,
                                 UInt32(CameraConfig.outputSize),
                                 UInt32(state.nodes.count),
                                 state.bleed ? 1 : 0))
        paramsBuf.contents().copyMemory(
            from: &params, byteCount: MemoryLayout<AerialParamsSwift>.stride)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(aerialState)
        encoder.setTexture(rgb64, index: 0)
        encoder.setTexture(depth64, index: 1)
        encoder.setBuffer(primsBuf, offset: 0, index: 0)
        encoder.setBuffer(paramsBuf, offset: 0, index: 1)
        encoder.setBuffer(outBuf, offset: 0, index: 2)
        encoder.setBuffer(nodesBuf, offset: 0, index: 3)
        let side = CameraConfig.outputSize
        encoder.dispatchThreads(MTLSize(width: side, height: side, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }

        let ptr = outBuf.contents().bindMemory(to: UInt8.self, capacity: side * side)
        return Array(UnsafeBufferPointer(start: ptr, count: side * side))
    }

    // MARK: - Texture Readback (for CPU perfect pass)

    /// Read back the downsampled 64×64 RGB texture after GPU processing.
    /// Call only after a downsample pass succeeds (textures are filled).
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

        // Texture holds raw TrueDepth METERS; every CPU consumer speaks
        // the [0,1] 1=near signal contract (spec/temporal/DepthSignal.hs).
        return (0..<pixelCount).map { i in
            DepthSignal.signalOrFill(meters: Float(Float16(bitPattern: rawData[i * 4])))
        }
    }

}

// MARK: - Param Structs (must match Metal struct layout)

// Must match Metal AerialParams (three 16-byte rows, 48 bytes).
struct AerialParamsSwift {
    var centroid: SIMD4<Float>   // xyz = OKLab c_F
    var scalars: SIMD4<Float>    // s*, τ, 1/dNear, 1/dFar
    var flags: SIMD4<UInt32>     // twoPhase, side, node count, bleed
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
    /// Buffers narrower than the crop clamp to origin instead of
    /// trapping on UInt32(negative) (line pass 2026-08-12) — the
    /// kernel then reads a smaller region rather than crashing.
    static func fromRGBBuffer(width: Int, height: Int) -> DownsampleParamsSwift {
        let cropSize = CameraConfig.rgbCrop  // 768, always
        let cropX = max(0, (width - cropSize) / 2)
        let cropY = max(0, (height - cropSize) / 2)
        let step = CameraConfig.rgbStep     // 768 / outputSize, integer
        return DownsampleParamsSwift(
            cropX: UInt32(cropX), cropY: UInt32(cropY),
            step: UInt32(step), halfStep: UInt32(step / 2),
            outputSize: UInt32(CameraConfig.outputSize)
        )
    }

    static func fromDepthBuffer(width: Int, height: Int) -> DownsampleParamsSwift {
        let cropSize = CameraConfig.depthCrop  // 256, always
        let cropX = max(0, (width - cropSize) / 2)
        let cropY = max(0, (height - cropSize) / 2)
        let step = CameraConfig.depthStep     // 256 / outputSize, integer
        return DownsampleParamsSwift(
            cropX: UInt32(cropX), cropY: UInt32(cropY),
            step: UInt32(step), halfStep: UInt32(step / 2),
            outputSize: UInt32(CameraConfig.outputSize)
        )
    }
}
