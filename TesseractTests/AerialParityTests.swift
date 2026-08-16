// ════════════════════════════════════════════════════════════════
// AerialParityTests: the DEFAULT LIVE PATH gets a parity gate
//
// ★ WHY THIS FILE EXISTS. Quantize.metal:6 calls aerialPreview "the
// 20 Hz GPU twin of DyadPipeline.Live.assign", and CLAUDE.md's
// no-fallbacks decree is explicit that a twin without a live parity
// gate is just a fallback that has not been caught yet. Until
// 2026-08-15 NO TEST DISPATCHED THIS KERNEL. The only test naming it,
// DyadPipelineTests.testBleedAndPhaseReachTheMetalState, asserts five
// struct field copies and never a texture, never an index.
//
// An adversarial run found two real divergences riding on that
// blindness, and this file gates both:
//
//   P1  a DEGENERATE per-frame fit packs s* = NaN and tau = +inf, the
//       kernel had no degeneracy input, and the BLEED-off collapse
//       asks `t < 0.5`, which is FALSE for NaN. t became 1.0 and all
//       4096 pixels routed to the sigma side. FIXED in the kernel the
//       same day; this file is the gate that keeps it fixed.
//
//   P2  the staged-value convention. FIXED 2026-08-16, and it needed
//       no new ruling: CLAUDE.md already decrees "Haskell is
//       authoritative; Swift/Metal are ports", so a Swift that
//       searches a value the spec never searches is simply wrong.
//       aerialPrimary searches the CONTINUOUS staged value; the
//       kernel already matched it; DyadPipeline round-tripped to
//       8-bit first. DY17 now pins the law and
//       DyadPipeline.stagedFieldLab is the port. The gate is STRICT:
//       4096 of 4096, exact.
//
// ★ AND THIS FILE'S FIRST MEASUREMENT WAS ITS OWN BUG, recorded
// because the mistake is instructive. It reported 65.80% divergence
// by feeding METRES to both sides. MetalPipeline.readbackDepth says
// plainly: "Texture holds raw TrueDepth METERS; every CPU consumer
// speaks the [0,1] 1=near signal contract." The kernel converts
// in-kernel from the DepthSignal anchors; Live.assign is handed the
// signal already converted. Comparing them on the same units was
// comparing the kernel against a CPU run on out-of-range input. The
// number was wrong; the defect it was pointing at was real.
//
// The harness dispatches the kernel DIRECTLY rather than through
// MetalPipeline, copying MetalGeometryParityTests: the working
// textures are private, and a direct dispatch is also the only way to
// drive a state the pipeline would never construct on its own.
// ════════════════════════════════════════════════════════════════

import XCTest
import Metal
import simd
@testable import Tesseract

final class AerialParityTests: XCTestCase {

    private let side = 64

    // MARK: - Harness

    private struct Rig {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let state: MTLComputePipelineState
    }

    private func rig() throws -> Rig {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal unavailable: this gate runs where there is a GPU.")
        }
        guard let queue = device.makeCommandQueue() else {
            throw XCTSkip("Metal device has no command queue.")
        }
        guard let library = device.makeDefaultLibrary(),
              let fn = library.makeFunction(name: "aerialPreview") else {
            throw XCTSkip("aerialPreview not in the default library for this host.")
        }
        return Rig(device: device, queue: queue,
                   state: try device.makeComputePipelineState(function: fn))
    }

    /// A 64² rgba32Float texture. `value` supplies (r, g, b) or the
    /// depth in metres, which the kernel reads from .r.
    private func texture(_ device: MTLDevice,
                         _ value: (Int, Int) -> (Float, Float, Float)) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: side, height: side, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d) else {
            throw XCTSkip("could not allocate a \(side)² rgba32Float texture")
        }
        var px = [Float](repeating: 0, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let (a, b, c) = value(x, y)
                let o = (y * side + x) * 4
                px[o] = a; px[o + 1] = b; px[o + 2] = c; px[o + 3] = 1
            }
        }
        px.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: side * 16)
        }
        return tex
    }

    /// Dispatch aerialPreview once and return its 4096 indices.
    private func dispatch(_ r: Rig,
                          rgb: MTLTexture, depth: MTLTexture,
                          state: DyadPipeline.MetalState) throws -> [UInt8] {
        let n = side * side
        var prims = state.primaries
        var nodes = state.nodes.isEmpty ? [SIMD4<Float>(repeating: 0)] : state.nodes
        var params = AerialParamsSwift(
            centroid: SIMD4<Float>(state.centroid.x, state.centroid.y,
                                   state.centroid.z, 0),
            scalars: SIMD4<Float>(state.sStar, state.tau,
                                  1 / Float(DepthSignal.dNear),
                                  1 / Float(DepthSignal.dFar)),
            flags: SIMD4<UInt32>(state.twoPhase ? 1 : 0,
                                 UInt32(side),
                                 UInt32(state.nodes.count),
                                 state.bleed ? 1 : 0))

        guard let primsBuf = r.device.makeBuffer(
                bytes: &prims,
                length: 128 * MemoryLayout<SIMD4<Float>>.stride,
                options: .storageModeShared),
              let nodesBuf = r.device.makeBuffer(
                bytes: &nodes,
                length: nodes.count * MemoryLayout<SIMD4<Float>>.stride,
                options: .storageModeShared),
              let paramsBuf = r.device.makeBuffer(
                bytes: &params,
                length: MemoryLayout<AerialParamsSwift>.stride,
                options: .storageModeShared),
              let outBuf = r.device.makeBuffer(length: n, options: .storageModeShared),
              let cmd = r.queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else {
            throw XCTSkip("could not encode the dispatch")
        }
        enc.setComputePipelineState(r.state)
        enc.setTexture(rgb, index: 0)
        enc.setTexture(depth, index: 1)
        enc.setBuffer(primsBuf, offset: 0, index: 0)
        enc.setBuffer(paramsBuf, offset: 0, index: 1)
        enc.setBuffer(outBuf, offset: 0, index: 2)
        enc.setBuffer(nodesBuf, offset: 0, index: 3)
        enc.dispatchThreads(MTLSize(width: side, height: side, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        XCTAssertNil(cmd.error, "the dispatch must not error")
        let p = outBuf.contents().bindMemory(to: UInt8.self, capacity: n)
        return Array(UnsafeBufferPointer(start: p, count: n))
    }

    // MARK: - The fixture

    /// A figure over ground: a warm disc at 0.4 m on a cool field at
    /// 2.2 m, with a colour ramp so the argmin is not constant.
    private func fixture() -> (rgb: [(Float, Float, Float)], depth: [Float]) {
        var rgb = [(Float, Float, Float)](repeating: (0, 0, 0), count: side * side)
        var depth = [Float](repeating: 0, count: side * side)
        let cx = Float(side) / 2, cy = Float(side) / 2, radius = Float(side) / 3
        for y in 0..<side {
            for x in 0..<side {
                let dx = Float(x) - cx, dy = Float(y) - cy
                let inside = dx * dx + dy * dy < radius * radius
                let u = Float(x) / Float(side - 1), v = Float(y) / Float(side - 1)
                let i = y * side + x
                if inside {
                    rgb[i] = (0.55 + 0.30 * u, 0.34 + 0.18 * v, 0.26 + 0.10 * u)
                    depth[i] = 0.4
                } else {
                    rgb[i] = (0.16 + 0.10 * v, 0.20 + 0.12 * u, 0.38 + 0.22 * v)
                    depth[i] = 2.2
                }
            }
        }
        return (rgb, depth)
    }

    /// Drive the live driver until it has solved, then hand back the
    /// state the kernel would be given. Skips rather than fails when
    /// the ring never produces one: this file gates the KERNEL, and a
    /// change to the solve cadence is a different test's business.
    private func solvedLive() throws -> (DyadPipeline.Live, DyadPipeline.MetalState) {
        let f = fixture()
        let live = DyadPipeline.Live()
        // signal, not metres: see the note in the parity test below
        let signal = f.depth.map { DepthSignal.signal(meters: $0) }
        for _ in 0..<64 { live.read(rgb: f.rgb, depths: signal) }
        guard let state = live.metalState, state.primaries.count == 128 else {
            throw XCTSkip("the live ring produced no metalState from 64 reads")
        }
        return (live, state)
    }

    // MARK: - ★ P1: the degeneracy guard

    /// A degenerate per-frame fit must leave the surface alone, exactly
    /// as `coverage(_:fit:twoPhase:bleed:)` does with its
    /// `guard twoPhase, !fit.isDegenerate else { return 0 }`.
    ///
    /// Before the 2026-08-15 kernel fix this returned 4096 sigma-side
    /// indices out of 4096: NaN propagated through the logistic, the
    /// BLEED-off collapse asked `t < 0.5`, NaN compared false, and t
    /// became 1.0. Every pixel inverted, silently, on the default path.
    func testADegenerateFitDoesNotInvertTheWholeSurface() throws {
        let r = try rig()
        let f = fixture()
        let rgbTex = try texture(r.device) { x, y in f.rgb[y * self.side + x] }
        let depthTex = try texture(r.device) { x, y in (f.depth[y * self.side + x], 0, 0) }

        // The exact packing a degenerate fit produces.
        let degenerate = DyadPipeline.MetalState(
            primaries: (0..<128).map { j in
                SIMD4<Float>(0.2 + 0.006 * Float(j), 0.01 * Float(j % 8),
                             -0.01 * Float(j % 5), 0)
            },
            nodes: [],
            centroid: SIMD3<Float>(0.5, 0.02, -0.03),
            sStar: Float.nan,
            tau: Float.infinity,
            twoPhase: true,
            bleed: false)

        let out = try dispatch(r, rgb: rgbTex, depth: depthTex, state: degenerate)
        XCTAssertEqual(out.count, side * side)

        let sigmaSide = out.filter { $0 >= 128 }.count
        XCTAssertNotEqual(sigmaSide, out.count,
            """
            Every one of \(out.count) pixels routed to the sigma side under a \
            degenerate fit. That is the P1 defect: the kernel has no degeneracy \
            input and NaN survives the BLEED-off collapse. The CPU twin returns \
            coverage 0 here.
            """)
        XCTAssertEqual(sigmaSide, 0,
            "a degenerate fit is coverage 0, so no pixel may take the sigma side")
    }

    /// The guard must not swallow the ordinary case: a finite fit with
    /// BLEED off still routes SOME pixels to the sigma side, or the
    /// test above would pass for the wrong reason.
    func testTheGuardDoesNotSuppressAnOrdinaryTwoPhaseFit() throws {
        let r = try rig()
        let f = fixture()
        let rgbTex = try texture(r.device) { x, y in f.rgb[y * self.side + x] }
        let depthTex = try texture(r.device) { x, y in (f.depth[y * self.side + x], 0, 0) }

        // s* between the disc's and the ground's depth signals, so the
        // MAP class genuinely splits the frame.
        let ordinary = DyadPipeline.MetalState(
            primaries: (0..<128).map { j in
                SIMD4<Float>(0.2 + 0.006 * Float(j), 0.01 * Float(j % 8),
                             -0.01 * Float(j % 5), 0)
            },
            nodes: [],
            centroid: SIMD3<Float>(0.5, 0.02, -0.03),
            sStar: 0.5,
            tau: 0.05,
            twoPhase: true,
            bleed: false)

        let out = try dispatch(r, rgb: rgbTex, depth: depthTex, state: ordinary)
        let sigmaSide = out.filter { $0 >= 128 }.count
        XCTAssertGreaterThan(sigmaSide, 0,
            "the fixture must actually exercise the sigma route")
        XCTAssertLessThan(sigmaSide, out.count,
            "and must not route the whole frame, or P1's assertion proves nothing")
    }

    // MARK: - ★ P2: the staged-value convention

    /// THE REAL PARITY GATE, and it is expected to FAIL until the
    /// convention is ruled.
    ///
    /// `DyadPalette.hs:521 aerialPrimary` searches the argmin on the
    /// CONTINUOUS staged value. `DyadPipeline.stagedField` returns
    /// (UInt8, UInt8, UInt8) and both of its consumers convert those
    /// BYTES back to OKLab before the argmin, hoisting DY12's round
    /// trip onto the assignment path. Quantize.metal round-trips its
    /// INPUT and then stages in float. So the KERNEL matches the
    /// authoritative Haskell and the SWIFT does not.
    ///
    /// ★ BE PRECISE ABOUT THE TWO NUMBERS, because they are not the
    /// same measurement. Isolating the convention alone, by running
    /// both conventions side by side, gives 3.8% to 11.7% of pixels at
    /// roughly 1.9x the palette's median nearest-neighbour spacing.
    /// THIS TEST measures the whole divergence between a real dispatch
    /// and Live.assign, and prints 65.80% (2695 of 4096) on the
    /// fixture below. The remainder is NOT accounted for and must not
    /// be assumed to be more of the same cause; one known candidate is
    /// CLAUDE.md's recorded gap that the live sigma-side chaos target
    /// pools the CURRENT frame where the export pools the S4 group.
    /// Attributing the rest is owed work, and this test is where it
    /// will be measured.
    ///
    /// ★ WHY XCTExpectFailure AND NOT A TOLERANCE. A tolerance would
    /// enshrine the divergence as lawful and this file would then
    /// certify the bug. An expected failure fails in BOTH directions:
    /// it is red today, and it turns red again the moment someone
    /// makes the two agree, which is the prompt to delete this wrapper
    /// and let the assertion stand. Sixteen DyadPalette axioms are
    /// green because not one of them says which staged value the
    /// argmin consumes; the fix is a ruling plus an axiom, not a
    /// number in a test.
    func testAerialKernelMatchesTheCPUAssignmentOnEveryPixel() throws {
        let r = try rig()
        let f = fixture()
        let (live, state) = try solvedLive()
        // ★ THE UNITS DIFFER BY DESIGN AND THE FIRST VERSION OF THIS
        // TEST GOT IT WRONG, reporting 65.80% divergence that was
        // mostly its own bug. MetalPipeline.readbackDepth says it
        // outright: "Texture holds raw TrueDepth METERS; every CPU
        // consumer speaks the [0,1] 1=near signal contract." So the
        // KERNEL is handed metres and converts in-kernel from the
        // DepthSignal anchors, while Live.assign is handed the signal
        // already converted. Feeding metres to both compares the
        // kernel against a CPU run on out-of-range input.
        guard let cpu = live.assign(rgb: f.rgb,
                                    depths: f.depth.map { DepthSignal.signal(meters: $0) })
        else {
            throw XCTSkip("the CPU twin declined to assign this frame")
        }
        let rgbTex = try texture(r.device) { x, y in f.rgb[y * self.side + x] }
        let depthTex = try texture(r.device) { x, y in (f.depth[y * self.side + x], 0, 0) }
        let gpu = try dispatch(r, rgb: rgbTex, depth: depthTex, state: state)

        XCTAssertEqual(cpu.count, gpu.count)
        let disagree = zip(cpu, gpu).filter { $0 != $1 }.count
        let pct = 100.0 * Double(disagree) / Double(max(cpu.count, 1))

        // ★ THE WRAPPER IS GONE, which is what it asked for. It read:
        // "Delete this wrapper when the convention is picked and DY17
        // pins which staged value the argmin reads." DY17 now pins it
        // (spec/quantization/DyadPalette.hs) and DyadPipeline searches
        // the CONTINUOUS staged value through stagedFieldLab, so this
        // is a STRICT gate with no tolerance: every one of 4096 pixels,
        // exact. It was red the day it was written and it is green now.
        XCTAssertEqual(disagree, 0,
            "kernel and CPU disagree on \(disagree) of \(cpu.count) pixels "
            + String(format: "(%.2f%%)", pct))
    }
}
