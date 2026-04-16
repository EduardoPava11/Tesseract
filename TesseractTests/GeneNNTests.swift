// GeneNNTests.swift
// Tesseract
//
// Tests for GeneNN — the 137→32→4 forward pass.
// Matches Gene.hs axioms G2, G6, G7, G14.

import XCTest
@testable import Tesseract

final class GeneNNTests: XCTestCase {

    // ── G6: total parameter count = 4548 ──

    func testGeneParamCount_is4581() {
        XCTAssertEqual(GeneWeights.totalCount, 4581)
        let gene = GeneWeights.defaultWeights()
        XCTAssertEqual(gene.weights.count, 4581)
    }

    // ── G7: ATTENTION = 4416, CORE = 165 ──

    func testGeneParamSplit_attentionAndCore() {
        XCTAssertEqual(GeneWeights.attentionCount, 4416)
        XCTAssertEqual(GeneWeights.coreCount, 165)
        XCTAssertEqual(GeneWeights.attentionCount + GeneWeights.coreCount,
                       GeneWeights.totalCount)
    }

    // ── G2: output ∈ {0,1,2,3}⁴ → palette index ∈ [0,255] ──

    func testGeneForward_outputInRange() {
        let gene = GeneWeights.defaultWeights()

        // Test with various input vectors
        let inputs: [[Float]] = [
            syntheticInput(depth: 0.0, frame: 0.0),
            syntheticInput(depth: 0.5, frame: 0.5),
            syntheticInput(depth: 1.0, frame: 1.0),
            syntheticInput(depth: 0.8, frame: 0.25),
        ]

        for (i, input) in inputs.enumerated() {
            let (idx, g) = gene.forward(input)
            XCTAssertGreaterThanOrEqual(idx, 0,
                "Input \(i): palette index must be ≥ 0, got \(idx)")
            XCTAssertLessThanOrEqual(idx, 255,
                "Input \(i): palette index must be ≤ 255, got \(idx)")

            // Verify decomposition
            let d = idx / 64
            let a = (idx % 64) / 16
            let b = (idx % 16) / 4
            let c = idx % 4
            XCTAssertLessThanOrEqual(d, 3)
            XCTAssertLessThanOrEqual(a, 3)
            XCTAssertLessThanOrEqual(b, 3)
            XCTAssertLessThanOrEqual(c, 3)

            // Global weight ∈ [0,1]
            XCTAssertGreaterThanOrEqual(g, 0, "g must be ≥ 0")
            XCTAssertLessThanOrEqual(g, 1, "g must be ≤ 1")
        }
    }

    // ── G14: forward = flatten >>> encode >>> relu >>> head >>> clamp ──

    func testGeneForward_deterministic() {
        let gene = GeneWeights.defaultWeights()
        let input = syntheticInput(depth: 0.5, frame: 0.5)

        let (idx1, g1) = gene.forward(input)
        let (idx2, g2) = gene.forward(input)
        XCTAssertEqual(idx1, idx2,
                       "Same weights + same input must produce same palette index")
        XCTAssertEqual(g1, g2,
                       "Same weights + same input must produce same global weight")
    }

    // ── Perturbation changes ATTENTION, keeps CORE ──

    func testGenePerturb_changesAttentionOnly() {
        let original = GeneWeights.defaultWeights()
        let perturbed = original.perturbed(scale: 0.1, seed: 42)

        // CORE must be identical
        XCTAssertTrue(perturbed.coreMatches(original),
                      "Perturbation must not change CORE weights")

        // ATTENTION must differ
        var attentionDiffers = false
        for i in 0..<GeneWeights.attentionCount {
            if original.weights[i] != perturbed.weights[i] {
                attentionDiffers = true
                break
            }
        }
        XCTAssertTrue(attentionDiffers,
                      "Perturbation must change at least one ATTENTION weight")
    }

    // ── Perturbed gene produces different output ──

    func testGenePerturb_producesDifferentOutput() {
        let original = GeneWeights.defaultWeights()
        let perturbed = original.perturbed(scale: 0.5, seed: 123)

        // Run many inputs — at least some should differ (index or global weight)
        var anyDifferent = false
        for depth in stride(from: Float(0), through: 1.0, by: 0.1) {
            for frame in stride(from: Float(0), through: 1.0, by: 0.1) {
                let inp = syntheticInput(depth: depth, frame: frame)
                let (idx1, g1) = original.forward(inp)
                let (idx2, g2) = perturbed.forward(inp)
                if idx1 != idx2 || abs(g1 - g2) > 0.001 { anyDifferent = true; break }
            }
            if anyDifferent { break }
        }
        XCTAssertTrue(anyDifferent,
                      "Perturbed gene should produce at least one different output")
    }

    // ── Input dimension matches spec ──

    func testInputDim_matches137() {
        XCTAssertEqual(GeneWeights.inputDim, 137)
        XCTAssertEqual(GeneWeights.inputDim, BlockPyramid.inputDim)
    }

    // ── HELPERS ──

    /// Build a synthetic 137-float input vector with known structure
    private func syntheticInput(depth: Float, frame: Float) -> [Float] {
        var v = [Float]()
        // 126 histogram bins: uniform across all scales
        let uniformBin = 1.0 / Float(CountedHist.numBins)
        for _ in 0..<(3 * 3) {  // 3 channels × 3 scales
            v.append(contentsOf: [Float](repeating: uniformBin, count: CountedHist.numBins))
        }
        // depth + frame
        v.append(depth)
        v.append(frame)
        // 4 sample counts
        v.append(144)  // n_rgb @ Level64
        v.append(36)   // n_rgb @ Level128
        v.append(9)    // n_rgb @ Level256
        v.append(16)   // n_depth
        // 5 entropy feedback (uniform)
        v.append(contentsOf: [Float](repeating: 1.0, count: 5))

        assert(v.count == 137, "Expected 137, got \(v.count)")
        return v
    }
}
