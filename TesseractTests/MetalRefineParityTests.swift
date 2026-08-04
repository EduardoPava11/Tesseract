// MetalRefineParityTests.swift
// Tesseract
//
// Stage-A parity: the Metal fold (Refine.metal) must produce a
// RefineAccumulation BIT-IDENTICAL to the CPU reference
// (CentroidRefiner.stageA). Equality, not tolerance — integer
// fixed-point accumulation makes the fold order-independent, and
// MTL_FAST_MATH=NO pins the per-pixel float ops to IEEE program order.
//
// The synthetic capture is deliberately dirty: non-dyadic weights,
// out-of-cell colors (dither), NaN depths, and all 256 entries hit.

import XCTest
@testable import Tesseract

final class MetalRefineParityTests: XCTestCase {

    /// Deterministic LCG — reproducible without seeding from time.
    private struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
        mutating func float01() -> Float {
            Float(next() >> 40) / Float(1 << 24)
        }
    }

    private func makeCapture(frames frameCount: Int) -> [QuantizedFrame] {
        let n = CameraConfig.pixelCount
        var rng = LCG(state: 0x7E55E4AC7)
        return (0..<frameCount).map { f in
            var indices = [UInt8](repeating: 0, count: n)
            var rgb = [(Float, Float, Float)](repeating: (0, 0, 0), count: n)
            var depths = [Float](repeating: 0, count: n)
            for p in 0..<n {
                indices[p] = UInt8((p &+ f &* 37) % 256)
                // Colors uncorrelated with the entry's cell — dither's
                // out-of-cell means are the norm here, not the edge case.
                rgb[p] = (rng.float01(), rng.float01(), rng.float01())
                // Weights: full range, non-dyadic, with NaN holes that
                // both paths must sanitize identically.
                depths[p] = (p % 97 == 0) ? Float.nan : rng.float01() * 1.2 - 0.1
            }
            return QuantizedFrame(
                index: f, paletteIndices: indices, rawRGB: rgb, depths: depths,
                measure: BirkhoffMeasure(paletteIndices: indices),
                subjectAnalysis: nil, anchorTrace: nil, timestamp: Double(f) / 20.0)
        }
    }

    func testStageA_bitExactCPUvsGPU() throws {
        guard let gpu = RefineAccumulator() else {
            throw XCTSkip("No Metal device — Stage-A parity needs a GPU")
        }
        let capture = makeCapture(frames: 64)

        let cpuAcc = CentroidRefiner.stageA(frames: capture)
        let gpuAcc = try XCTUnwrap(gpu.stageA(frames: capture))

        // The whole claim in one line: not close — EQUAL.
        XCTAssertEqual(cpuAcc, gpuAcc,
            "GPU fold must match the CPU reference bit-for-bit")

        // And therefore the refined palettes agree exactly too.
        let cpuPal = CentroidRefiner.stageB(cpuAcc)
        let gpuPal = CentroidRefiner.stageB(gpuAcc)
        for i in 0..<256 {
            XCTAssertTrue(cpuPal.table[i] == gpuPal.table[i], "entry \(i) diverged")
            XCTAssertEqual(cpuPal.deltas[i], gpuPal.deltas[i])
        }
    }

    func testStageA_emptyAndPreviewFrames() throws {
        guard let gpu = RefineAccumulator() else {
            throw XCTSkip("No Metal device")
        }
        // No frames at all → zero accumulation.
        XCTAssertEqual(gpu.stageA(frames: []), RefineAccumulation())

        // Preview frames (no rawRGB) are skipped on both paths.
        let n = CameraConfig.pixelCount
        let indices = (0..<n).map { UInt8($0 % 256) }
        let preview = QuantizedFrame(
            index: 0, paletteIndices: indices, rawRGB: nil,
            depths: [Float](repeating: 1, count: n),
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil, anchorTrace: nil, timestamp: 0)
        XCTAssertEqual(gpu.stageA(frames: [preview]),
                       CentroidRefiner.stageA(frames: [preview]))
    }
}
