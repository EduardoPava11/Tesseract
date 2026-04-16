// BlockPyramidTests.swift
// Tesseract
//
// Tests for BlockPyramid — multi-scale histogram types.
// Matches Gene.hs axioms G1, G3, G4, G5.

import XCTest
@testable import Tesseract

final class BlockPyramidTests: XCTestCase {

    // ── G1: flatten produces exactly 137 floats ──

    func testFlatten_produces137Floats() {
        let bp = syntheticBlockPyramid(depth: 0.5, frameNorm: 0.5)
        let v = bp.flatten()
        XCTAssertEqual(v.count, BlockPyramid.inputDim,
                       "flatten must produce exactly \(BlockPyramid.inputDim) floats")
        XCTAssertEqual(BlockPyramid.inputDim, 137)
    }

    // ── G3: histogram frequencies sum to 1.0 ──

    func testCountedHist_sumsToOne() {
        for n in [9, 36, 144] {
            var counts = [Int](repeating: 1, count: CountedHist.numBins)
            counts[7] = n - (CountedHist.numBins - 1)  // peak at bin 7
            let hist = CountedHist.fromCounts(counts)
            let sum = hist.bins.reduce(0, +)
            XCTAssertEqual(sum, 1.0, accuracy: 1e-6,
                           "Histogram with n=\(n) must sum to 1.0, got \(sum)")
        }
    }

    // ── G4: sample counts match level geometry ──

    func testSampleCounts_matchLevel() {
        // Level64: step=12, n=144
        // Level128: step=6, n=36
        // Level256: step=3, n=9
        let bp = syntheticBlockPyramid(depth: 0.5, frameNorm: 0.0)
        XCTAssertEqual(bp.r.coarse.n, 144, "Level64 R should have 144 samples")
        XCTAssertEqual(bp.r.medium.n, 36, "Level128 R should have 36 samples")
        XCTAssertEqual(bp.r.fine.n, 9, "Level256 R should have 9 samples")
    }

    // ── G5: ChannelPyramid contains all 3 levels ──

    func testChannelPyramid_hasAllScales() {
        let cp = syntheticChannelPyramid(peakBin: 7)
        // All three levels exist and have different sample counts
        XCTAssertEqual(cp.coarse.bins.count, CountedHist.numBins)
        XCTAssertEqual(cp.medium.bins.count, CountedHist.numBins)
        XCTAssertEqual(cp.fine.bins.count, CountedHist.numBins)
        XCTAssertGreaterThan(cp.coarse.n, cp.medium.n)
        XCTAssertGreaterThan(cp.medium.n, cp.fine.n)
    }

    // ── G12/G13: entropy feedback ──

    func testEntropyFeedback_uniformIsOne() {
        let ef = EntropyFeedback.uniform
        XCTAssertEqual(ef.epoch, 1.0, accuracy: 1e-6)
        XCTAssertEqual(ef.r, 1.0, accuracy: 1e-6)
        XCTAssertEqual(ef.g, 1.0, accuracy: 1e-6)
        XCTAssertEqual(ef.b, 1.0, accuracy: 1e-6)
        XCTAssertEqual(ef.joint, 1.0, accuracy: 1e-6)
        XCTAssertEqual(ef.asArray.count, 5)
    }

    // ── Entropy of uniform histogram = maximum ──

    func testCountedHist_uniformEntropyIsMax() {
        let n = 140  // divisible by 14
        let counts = [Int](repeating: n / CountedHist.numBins, count: CountedHist.numBins)
        let hist = CountedHist.fromCounts(counts)
        XCTAssertEqual(hist.normalizedEntropy, 1.0, accuracy: 1e-5,
                       "Uniform histogram should have normalized entropy = 1.0")
    }

    // ── Flatten layout is correct ──

    func testFlatten_layoutOrder() {
        // Build a pyramid with known values to verify ordering
        let rHist = CountedHist.fromCounts([100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let gHist = CountedHist.fromCounts([0, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        let bHist = CountedHist.fromCounts([0, 0, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

        let rPyr = ChannelPyramid(coarse: rHist, medium: rHist, fine: rHist)
        let gPyr = ChannelPyramid(coarse: gHist, medium: gHist, fine: gHist)
        let bPyr = ChannelPyramid(coarse: bHist, medium: bHist, fine: bHist)

        let bp = BlockPyramid(
            r: rPyr, g: gPyr, b: bPyr,
            depth: 0.75, depthN: 16, frameNorm: 0.25,
            entropy: .uniform
        )
        let v = bp.flatten()

        // First 14 values = R @ Level64 → bin 0 should be 1.0
        XCTAssertEqual(v[0], 1.0, accuracy: 1e-6, "R Level64 bin 0 should be 1.0")
        // Values at index 42 = G @ Level64 → bin 1 should be 1.0
        XCTAssertEqual(v[42 + 1], 1.0, accuracy: 1e-6, "G Level64 bin 1 should be 1.0")
        // Values at index 84 = B @ Level64 → bin 2 should be 1.0
        XCTAssertEqual(v[84 + 2], 1.0, accuracy: 1e-6, "B Level64 bin 2 should be 1.0")
        // depth at index 126
        XCTAssertEqual(v[126], 0.75, accuracy: 1e-6, "depth should be 0.75")
        // frameNorm at index 127
        XCTAssertEqual(v[127], 0.25, accuracy: 1e-6, "frameNorm should be 0.25")
    }

    // ── HELPERS ──

    private func syntheticChannelPyramid(peakBin: Int) -> ChannelPyramid {
        func hist(n: Int) -> CountedHist {
            var counts = [Int](repeating: 1, count: CountedHist.numBins)
            counts[peakBin] = max(1, n - (CountedHist.numBins - 1))
            return CountedHist.fromCounts(counts)
        }
        return ChannelPyramid(
            coarse: hist(n: 144),
            medium: hist(n: 36),
            fine: hist(n: 9)
        )
    }

    private func syntheticBlockPyramid(depth: Float, frameNorm: Float) -> BlockPyramid {
        BlockPyramid(
            r: syntheticChannelPyramid(peakBin: 3),
            g: syntheticChannelPyramid(peakBin: 7),
            b: syntheticChannelPyramid(peakBin: 11),
            depth: depth,
            depthN: 16,
            frameNorm: frameNorm,
            entropy: .uniform
        )
    }
}
