// TriScaleLadderTests.swift
// TesseractTests
//
// Swift-side gates for the TriScaleLadder port — each test mirrors an
// axiom of spec/output/TriScaleLadder.hs (the authority). Pure logic:
// no camera, no simulator dependency beyond XCTest itself.

import XCTest
@testable import Tesseract

final class TriScaleLadderTests: XCTestCase {

    // Deterministic LCG, same constants as the spec's uniforms.
    private func indexStream(seed: Int) -> AnyIterator<UInt8> {
        var s = seed
        return AnyIterator {
            s = (1103515245 &* s &+ 12345) % 2147483648
            return UInt8(s % 256)
        }
    }

    private func makeFrames(seed: Int) -> [QuantizedFrame] {
        let stream = indexStream(seed: seed)
        return (0..<64).map { f in
            let indices = (0..<4096).map { _ in stream.next()! }
            return QuantizedFrame(
                index: f, paletteIndices: indices, rawRGB: nil,
                depths: [Float](repeating: 0, count: 4096),
                measure: BirkhoffMeasure(paletteIndices: indices),
                subjectAnalysis: nil, anchorTrace: nil, timestamp: 0)
        }
    }

    private func makeFrames(constant idx: UInt8) -> [QuantizedFrame] {
        (0..<64).map { f in
            let indices = [UInt8](repeating: idx, count: 4096)
            return QuantizedFrame(
                index: f, paletteIndices: indices, rawRGB: nil,
                depths: [Float](repeating: 0, count: 4096),
                measure: BirkhoffMeasure(paletteIndices: indices),
                subjectAnalysis: nil, anchorTrace: nil, timestamp: 0)
        }
    }

    // Brute-force k×k×k sum pool, independent of poolL's loop shape.
    private func poolBrute(_ cube: RungCube, k: Int) -> RungCube {
        let s = cube.side, h = s / k, n = h * h * h
        var d = [UInt64](repeating: 0, count: n)
        var a = [UInt64](repeating: 0, count: n)
        var b = [UInt64](repeating: 0, count: n)
        var c = [UInt64](repeating: 0, count: n)
        for f in 0..<s {
            for r in 0..<s {
                for col in 0..<s {
                    let src = f * s * s + r * s + col
                    let dst = (f / k) * h * h + (r / k) * h + (col / k)
                    d[dst] &+= cube.d[src]; a[dst] &+= cube.a[src]
                    b[dst] &+= cube.b[src]; c[dst] &+= cube.c[src]
                }
            }
        }
        return RungCube(side: h, d: d, a: a, b: b, c: c)
    }

    // TL1: pool₂ ∘ pool₂ == pool₄, exactly, per axis.
    func testSumsCompose() throws {
        let r64 = try XCTUnwrap(TriScaleLadder.rung64(frames: makeFrames(seed: 1)))
        XCTAssertEqual(TriScaleLadder.poolL(TriScaleLadder.poolL(r64)),
                       poolBrute(r64, k: 4))
    }

    // TL3: mass invariant down the ladder; telemetry reports it.
    func testMassConserved() throws {
        let frames = makeFrames(seed: 2)
        let r64 = try XCTUnwrap(TriScaleLadder.rung64(frames: frames))
        let r32 = TriScaleLadder.poolL(r64)
        let r16 = TriScaleLadder.poolL(r32)
        XCTAssertEqual(TriScaleLadder.mass(r64), TriScaleLadder.mass(r32))
        XCTAssertEqual(TriScaleLadder.mass(r64), TriScaleLadder.mass(r16))
        let t = try XCTUnwrap(TriScaleLadder.telemetry(frames: frames))
        XCTAssertTrue(t.massConserved)
        XCTAssertEqual(t.mass, TriScaleLadder.mass(r64))
    }

    // TL4: side × delay = 320 cs at every rung; no 128 rung exists.
    func testTimeLaw() {
        XCTAssertEqual(RungTelemetry.delayCs, [64: 5, 32: 10, 16: 20])
        for (side, delay) in RungTelemetry.delayCs {
            XCTAssertEqual(side * delay, RungTelemetry.loopCs)
        }
        XCTAssertNotEqual(RungTelemetry.loopCs % 128, 0)
    }

    // TL8/TL9: rung equivalence (compute time) + the resolution of
    // depth — 64 samples per judgment, 4096 judgments/loop at 5 Hz.
    // (Orbit mass invariance is testMassConserved; here the rates.)
    func testDepthResolution() {
        let base = RungTelemetry.baseRungSide
        let depth = RungTelemetry.depthRungSide
        for s in [16, 32, 64] {                      // ×8 per rung
            XCTAssertEqual((2 * s) * (2 * s) * (2 * s), 8 * s * s * s)
        }
        let perJudgment = (base / depth) * (base / depth) * (base / depth)
        XCTAssertEqual(perJudgment, RungTelemetry.samplesPerJudgment)
        XCTAssertEqual(RungTelemetry.samplesPerJudgment, 8 * 8)   // two rungs
        XCTAssertEqual(depth * depth * depth, RungTelemetry.judgmentsPerLoop)
        XCTAssertEqual(base * base * base,
                       RungTelemetry.samplesPerJudgment * RungTelemetry.judgmentsPerLoop)
        XCTAssertEqual(100 / RungTelemetry.delayCs[depth]!, 5)    // 5 Hz judge
        XCTAssertEqual(100 / RungTelemetry.delayCs[base]!, 20)    // 20 Hz RGB
    }

    // TL7: the free-block meter — W = 1 ⇔ ≤1 nonzero child.
    func testFreeBlockMeter() throws {
        // Index 0 = lattice origin (0,0,0,0): zero mass everywhere,
        // every block on both transitions is free.
        let zero = try XCTUnwrap(TriScaleLadder.telemetry(frames: makeFrames(constant: 0)))
        XCTAssertEqual(zero.freeBlocks3264, 32 * 32 * 32)
        XCTAssertEqual(zero.freeBlocks1632, 16 * 16 * 16)
        XCTAssertEqual(zero.mass, 0)
        XCTAssertTrue(zero.massConserved)

        // Two nonzero voxels inside ONE 2×2×2 block: exactly that
        // block stops being free on 64→32; pooled to a single voxel,
        // the 32→16 transition stays entirely free.
        var frames = makeFrames(constant: 0)
        var indices = frames[0].paletteIndices
        indices[0] = 255   // (3,3,3,3)
        indices[1] = 255   // same spacetime block (col neighbor)
        frames[0] = QuantizedFrame(
            index: 0, paletteIndices: indices, rawRGB: nil,
            depths: frames[0].depths,
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil, anchorTrace: nil, timestamp: 0)
        let two = try XCTUnwrap(TriScaleLadder.telemetry(frames: frames))
        XCTAssertEqual(two.freeBlocks3264, 32 * 32 * 32 - 1)
        XCTAssertEqual(two.freeBlocks1632, 16 * 16 * 16)
        XCTAssertEqual(two.mass, 24)   // 2 × (3+3+3+3)
        XCTAssertTrue(two.massConserved)
    }

    // Base-rung guard: the ladder refuses anything but the full 64³.
    func testRejectsPartialBursts() {
        XCTAssertNil(TriScaleLadder.telemetry(frames: Array(makeFrames(seed: 3).prefix(63))))
        XCTAssertNil(TriScaleLadder.telemetry(frames: []))
    }
}
