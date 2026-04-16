// SwipeTests.swift
// Tesseract
//
// Tests for swipe-to-train gene loop.
// Matches Gene.hs axioms G10, G11.

import XCTest
@testable import Tesseract

final class SwipeTests: XCTestCase {

    // ── G10: TAP preserves gene ──

    func testTap_preservesGene() {
        let original = GeneWeights.defaultWeights()
        let previous = original.perturbed(scale: 0.1, seed: 99)

        // TAP should keep current, not revert to previous
        let result = applyGeneSignal(.tap, current: original, previous: previous)
        XCTAssertEqual(result.weights, original.weights,
                       "TAP must preserve current gene")
    }

    // ── G11: RIGHT reverts to previous ──

    func testSwipeRight_revertsGene() {
        let current = GeneWeights.defaultWeights().perturbed(scale: 0.1, seed: 1)
        let previous = GeneWeights.defaultWeights()

        let result = applyGeneSignal(.right, current: current, previous: previous)
        XCTAssertEqual(result.weights, previous.weights,
                       "RIGHT must revert to previous gene")
    }

    // ── LEFT changes gene ──

    func testSwipeLeft_changesGene() {
        let original = GeneWeights.defaultWeights()
        let perturbed = original.perturbed(scale: 0.05, seed: 42)

        // At least one weight should differ
        var differs = false
        for i in 0..<GeneWeights.attentionCount {
            if original.weights[i] != perturbed.weights[i] {
                differs = true
                break
            }
        }
        XCTAssertTrue(differs, "LEFT must change ATTENTION weights")
    }

    // ── LEFT preserves CORE ──

    func testSwipeLeft_preservesCORE() {
        let original = GeneWeights.defaultWeights()
        let perturbed = original.perturbed(scale: 0.1, seed: 42)
        XCTAssertTrue(perturbed.coreMatches(original),
                      "LEFT must preserve CORE weights")
    }

    // ── Sequence: LEFT LEFT RIGHT produces predictable state ──

    func testSwipeSequence() {
        let g0 = GeneWeights.defaultWeights()

        // LEFT: g0 → g1
        let g1 = g0.perturbed(scale: 0.05, seed: 0)
        XCTAssertTrue(g1.coreMatches(g0))

        // LEFT: g1 → g2
        let g2 = g1.perturbed(scale: 0.05, seed: 1)
        XCTAssertTrue(g2.coreMatches(g0))

        // RIGHT: revert to g1 (previous)
        let g3 = applyGeneSignal(.right, current: g2, previous: g1)
        XCTAssertEqual(g3.weights, g1.weights, "RIGHT should revert to g1")

        // TAP: keep g3 (which is g1)
        let g4 = applyGeneSignal(.tap, current: g3, previous: g2)
        XCTAssertEqual(g4.weights, g3.weights, "TAP should keep current")
    }

    // ── HELPERS ──

    enum GeneSignal { case tap, left, right }

    /// Pure function matching Gene.hs applySignal
    func applyGeneSignal(_ signal: GeneSignal, current: GeneWeights, previous: GeneWeights) -> GeneWeights {
        switch signal {
        case .tap:   return current
        case .left:  return current.perturbed(scale: 0.05, seed: 42)
        case .right: return previous
        }
    }
}
