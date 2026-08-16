// MetalGeometryParityTests.swift
// Tesseract
//
// ★ THE THIRD PORT OF THE FUNNEL'S ENTRANCE.
//
// Daniel, 2026-08-15: "the function map our axioms and theorems to
// test the swift and metal."
//
// One law, three ports: spec/output/FrameGeometry.hs (authoritative),
// Signal/FrameGeometry.swift (the port), Solve/Quantize.metal (the
// kernel that actually runs at capture). Until now the third had no
// gate at all, and no test file in this suite touched Metal's
// downsample path.
//
// ★ WHY THE KERNEL'S OWN CLAIM WAS NOT A GATE. Quantize.metal:188-192
// says "Port of FrameGeometry.hs rgbSource/depthSource ... Verified by
// Haskell axioms G5-G10 for all 4096 output pixels." G5 is bounds, G6
// is alignment, G7 is spacing, and every one of them is invariant
// under a relabelling of the output grid. The kernel applies a 90
// degree rotation that the spec's `rgbSource` does not, and those
// axioms pass either way. They could not have caught it being wrong.
// G11-G13 were added to state the rotation; this file checks that the
// running kernel obeys it.
//
// ★ HOW: THE TEST CHECKS ADDRESSES, NOT COLOURS. The source texture is
// painted so every texel carries its OWN coordinates as its red and
// green channels, in rgba32Float, exactly. So whatever the kernel
// writes to output pixel (i, j) IS the coordinate it chose to read.
// Comparing that to FrameGeometry.sourceRGB is an exact check of the
// address law at all 4096 output pixels, with no tolerance anywhere.
// A colour check would have passed for any read inside a smooth
// region, which is the failure the old comment was resting on.

import XCTest
import Metal
@testable import Tesseract

final class MetalGeometryParityTests: XCTestCase {

    private let outputSize = 64

    // MARK: - Harness

    private struct Rig {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let state: MTLComputePipelineState
    }

    private func rig(function: String) throws -> Rig {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal unavailable: this gate runs where there is a GPU.")
        }
        guard let queue = device.makeCommandQueue() else {
            throw XCTSkip("Metal device has no command queue.")
        }
        // The kernels live in the app bundle's default library; unit
        // tests are hosted by the app, so Bundle.main is that bundle.
        guard let library = device.makeDefaultLibrary(),
              let fn = library.makeFunction(name: function) else {
            throw XCTSkip("Quantize.metal not in the default library for this host.")
        }
        return Rig(device: device, queue: queue,
                   state: try device.makeComputePipelineState(function: fn))
    }

    /// A source texture where texel (x, y) holds (Float(x), Float(y)).
    /// rgba32Float is exact for every coordinate in range, so a read
    /// address comes back as itself.
    private func addressTexture(_ device: MTLDevice, side: Int) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: side, height: side, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d) else {
            throw XCTSkip("could not allocate a \(side)² rgba32Float source")
        }
        var px = [Float](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let o = (y * side + x) * 4
                px[o] = Float(x); px[o + 1] = Float(y)
                px[o + 2] = 0; px[o + 3] = 1
            }
        }
        px.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: side * 16)
        }
        return tex
    }

    private func destination(_ device: MTLDevice) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: outputSize, height: outputSize,
            mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d) else {
            throw XCTSkip("could not allocate the destination")
        }
        return tex
    }

    /// Run one downsample kernel and return the addresses it read.
    private func addressesRead(function: String, sourceSide: Int,
                               params: DownsampleParamsSwift)
        throws -> [(x: Int, y: Int)] {
        let r = try rig(function: function)
        let src = try addressTexture(r.device, side: sourceSide)
        let dst = try destination(r.device)

        var p = params
        guard let pBuf = r.device.makeBuffer(bytes: &p,
                                             length: MemoryLayout<DownsampleParamsSwift>.stride,
                                             options: .storageModeShared),
              let cmd = r.queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else {
            throw XCTSkip("could not encode the dispatch")
        }
        enc.setComputePipelineState(r.state)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        enc.setBuffer(pBuf, offset: 0, index: 0)
        enc.dispatchThreads(MTLSize(width: outputSize, height: outputSize, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        XCTAssertNil(cmd.error, "the dispatch must not error")

        var out = [Float](repeating: 0, count: outputSize * outputSize * 4)
        out.withUnsafeMutableBytes { raw in
            dst.getBytes(raw.baseAddress!, bytesPerRow: outputSize * 16,
                         from: MTLRegionMake2D(0, 0, outputSize, outputSize),
                         mipmapLevel: 0)
        }
        return (0..<(outputSize * outputSize)).map { i in
            (x: Int(out[i * 4]), y: Int(out[i * 4 + 1]))
        }
    }

    // MARK: - ★ The gate: the kernel reads where the law says

    func testMetalRGBDownsampleReadsTheAddressTheLawGives() throws {
        let side = FrameGeometry.rgbCrop     // 768: crop offset is (0, 0)
        let params = DownsampleParamsSwift.fromRGBBuffer(width: side, height: side)
        XCTAssertEqual(Int(params.step), FrameGeometry.rgbStep(outputSize: outputSize))
        XCTAssertEqual(Int(params.halfStep), Int(params.step) / 2)
        XCTAssertEqual(Int(params.cropX), 0)

        let read = try addressesRead(function: "downsampleRGB",
                                     sourceSide: side, params: params)
        var checked = 0
        for j in 0..<outputSize {
            for i in 0..<outputSize {
                let expect = FrameGeometry.sourceRGB(x: i, y: j,
                                                     outputSize: outputSize,
                                                     crop: (0, 0))
                let got = read[j * outputSize + i]
                XCTAssertEqual(got.x, expect.x, "output (\(i),\(j)) source x")
                XCTAssertEqual(got.y, expect.y, "output (\(i),\(j)) source y")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 4096, "all 4096 output pixels, actually checked")
    }

    func testMetalDepthDownsampleReadsTheAddressTheLawGives() throws {
        let side = FrameGeometry.depthCrop   // 256
        let params = DownsampleParamsSwift.fromDepthBuffer(width: side, height: side)
        XCTAssertEqual(Int(params.step), FrameGeometry.depthStep(outputSize: outputSize))

        let read = try addressesRead(function: "downsampleDepth",
                                     sourceSide: side, params: params)
        for j in 0..<outputSize {
            for i in 0..<outputSize {
                let expect = FrameGeometry.sourceDepth(x: i, y: j,
                                                       outputSize: outputSize,
                                                       crop: (0, 0))
                let got = read[j * outputSize + i]
                XCTAssertEqual(got.x, expect.x, "depth output (\(i),\(j)) source x")
                XCTAssertEqual(got.y, expect.y, "depth output (\(i),\(j)) source y")
            }
        }
    }

    /// ★ G13, on running code: both streams take the SAME quarter
    /// turn. If they ever diverged the role law would read a pixel's
    /// depth from a place a quarter turn away from its colour, and
    /// nothing downstream would notice.
    func testRGBAndDepthTakeTheSameQuarterTurn() throws {
        let rgb = try addressesRead(
            function: "downsampleRGB", sourceSide: FrameGeometry.rgbCrop,
            params: .fromRGBBuffer(width: FrameGeometry.rgbCrop,
                                   height: FrameGeometry.rgbCrop))
        let dep = try addressesRead(
            function: "downsampleDepth", sourceSide: FrameGeometry.depthCrop,
            params: .fromDepthBuffer(width: FrameGeometry.depthCrop,
                                     height: FrameGeometry.depthCrop))
        let scale = FrameGeometry.scaleFactor
        for p in 0..<(outputSize * outputSize) {
            // Same output pixel must land within one depth step of the
            // same physical place, once scaled.
            XCTAssertLessThanOrEqual(abs(rgb[p].x - dep[p].x * scale), scale)
            XCTAssertLessThanOrEqual(abs(rgb[p].y - dep[p].y * scale), scale)
        }
    }

    /// ★ G11 on running code: the kernel's read set is a BIJECTION
    /// onto the block centres. It reads each block exactly once, so
    /// whatever the rotation is, the kernel loses nothing by it.
    func testTheKernelReadsEveryBlockCentreExactlyOnce() throws {
        let read = try addressesRead(
            function: "downsampleRGB", sourceSide: FrameGeometry.rgbCrop,
            params: .fromRGBBuffer(width: FrameGeometry.rgbCrop,
                                   height: FrameGeometry.rgbCrop))
        XCTAssertEqual(Set(read.map { "\($0.x),\($0.y)" }).count, 4096,
                       "no block centre may be read twice")

        // And it is exactly the unrotated law's set, permuted.
        let lawful = Set((0..<outputSize).flatMap { j in
            (0..<outputSize).map { i -> String in
                let s = FrameGeometry.sourceRGBUnrotated(x: i, y: j,
                                                         outputSize: outputSize,
                                                         crop: (0, 0))
                return "\(s.x),\(s.y)"
            }
        })
        XCTAssertEqual(Set(read.map { "\($0.x),\($0.y)" }), lawful)
    }

    /// ★ AND THE ONE THIS CANNOT SETTLE, said out loud. Whether the
    /// quarter turn is the RIGHT one, or should be clockwise, is a
    /// fact about pixel memory layout on a physical iPhone 17 and no
    /// simulator can answer it. What these tests buy is that the three
    /// ports agree with each other, so when a device answers, one edit
    /// answers it everywhere. This test records the direction actually
    /// shipped so a device pass has something to contradict.
    func testTheShippedTurnIsCounterClockwiseAndIsRecordedAsSuch() throws {
        let read = try addressesRead(
            function: "downsampleRGB", sourceSide: FrameGeometry.rgbCrop,
            params: .fromRGBBuffer(width: FrameGeometry.rgbCrop,
                                   height: FrameGeometry.rgbCrop))
        // Output (0,0) reads the block the unrotated law would give to
        // (0, 63): top-left of the output comes from bottom-left of the
        // source. That IS the counter-clockwise turn, stated as data.
        let corner = read[0]
        let expect = FrameGeometry.sourceRGBUnrotated(x: 0, y: outputSize - 1,
                                                      outputSize: outputSize,
                                                      crop: (0, 0))
        XCTAssertEqual(corner.x, expect.x)
        XCTAssertEqual(corner.y, expect.y)
    }
}
