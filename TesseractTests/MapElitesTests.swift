// MapElitesTests.swift
// Tesseract
//
// Tests for MAP-Elites + Sobol + Decision pipeline.
// Matches MapElites.hs axioms ME1-ME8 and Decision.hs axioms D1-D9.

import XCTest
@testable import Tesseract

final class MapElitesTests: XCTestCase {

    // ── ME1: Place only replaces if beauty improves ──

    func testMapElites_onlyReplacesIfBetter() {
        let map = EliteMap()
        let gene = GeneWeights.defaultWeights()
        let desc = Descriptor(rhythm: 0.5, spread: 0.5)
        let entropy = EntropyFeedback.uniform
        let gif = Data([0x47, 0x49, 0x46])  // dummy

        // First placement: always succeeds
        XCTAssertTrue(map.place(gene: gene, beauty: 10, descriptor: desc, gifData: gif, entropy: entropy))

        // Worse beauty: rejected
        XCTAssertFalse(map.place(gene: gene, beauty: 5, descriptor: desc, gifData: gif, entropy: entropy))

        // Better beauty: accepted
        XCTAssertTrue(map.place(gene: gene, beauty: 15, descriptor: desc, gifData: gif, entropy: entropy))

        // Cell should have beauty 15
        let cell = map.cells[desc.gridRow][desc.gridCol]
        XCTAssertEqual(cell?.beauty, 15)
    }

    // ── ME2: Sobol directions are distinct ──

    func testSobol_noDuplicateDirections() {
        var explorer = SobolExplorer(dim: 100)
        let d0 = explorer.nextDirection()
        let d1 = explorer.nextDirection()
        let d2 = explorer.nextDirection()

        XCTAssertNotEqual(d0, d1, "Sobol directions 0 and 1 must differ")
        XCTAssertNotEqual(d1, d2, "Sobol directions 1 and 2 must differ")
        XCTAssertNotEqual(d0, d2, "Sobol directions 0 and 2 must differ")
    }

    // ── ME3: Diverse descriptors fill the grid ──

    func testMapElites_coverageWithDiverseSwipes() {
        let map = EliteMap()
        let gene = GeneWeights.defaultWeights()
        let gif = Data([0x47])
        let entropy = EntropyFeedback.uniform

        // 9 descriptors spanning the grid
        let descs: [(Float, Float, Float)] = [
            (0.1, 0.1, 5), (0.5, 0.1, 8), (0.9, 0.1, 6),
            (0.1, 0.5, 7), (0.5, 0.5, 12), (0.9, 0.5, 9),
            (0.1, 0.9, 4), (0.5, 0.9, 11), (0.9, 0.9, 10),
        ]

        for (r, s, b) in descs {
            let desc = Descriptor(rhythm: r, spread: s)
            map.place(gene: gene, beauty: b, descriptor: desc, gifData: gif, entropy: entropy)
        }

        XCTAssertGreaterThanOrEqual(map.coverage, 3, "9 diverse swipes → ≥3 cells")
        // With perfectly spread descriptors, should fill all 9
        XCTAssertEqual(map.coverage, 9)
    }

    // ── ME4: Boldness check rejects duplicates ──

    func testMapElites_rejectsDuplicateDescriptor() {
        let map = EliteMap()
        let gene = GeneWeights.defaultWeights()
        let gif = Data([0x47])
        let entropy = EntropyFeedback.uniform

        let desc = Descriptor(rhythm: 0.5, spread: 0.5)
        map.place(gene: gene, beauty: 10, descriptor: desc, gifData: gif, entropy: entropy)

        // Same descriptor again → not bold
        XCTAssertFalse(map.isBold(desc))

        // Different descriptor → bold
        let farDesc = Descriptor(rhythm: 0.9, spread: 0.9)
        XCTAssertTrue(map.isBold(farDesc))
    }

    // ── Descriptor grid placement ──

    func testDescriptor_gridPlacement() {
        XCTAssertEqual(Descriptor(rhythm: 0.1, spread: 0.1).gridRow, 0)
        XCTAssertEqual(Descriptor(rhythm: 0.1, spread: 0.1).gridCol, 0)
        XCTAssertEqual(Descriptor(rhythm: 0.5, spread: 0.5).gridRow, 1)
        XCTAssertEqual(Descriptor(rhythm: 0.5, spread: 0.5).gridCol, 1)
        XCTAssertEqual(Descriptor(rhythm: 0.99, spread: 0.99).gridRow, 2)
        XCTAssertEqual(Descriptor(rhythm: 0.99, spread: 0.99).gridCol, 2)
    }

    // ── Sobol values in [-1, 1] ──

    func testSobol_valuesInRange() {
        var explorer = SobolExplorer(dim: 50)
        for _ in 0..<20 {
            let dir = explorer.nextDirection()
            for v in dir {
                XCTAssertGreaterThanOrEqual(v, -1.0)
                XCTAssertLessThanOrEqual(v, 1.0)
            }
        }
    }

    // ── Sobol perturbation preserves CORE ──

    func testSobol_perturbPreservesCORE() {
        var explorer = SobolExplorer()
        let original = GeneWeights.defaultWeights()
        let perturbed = explorer.perturb(original, scale: 0.1)
        XCTAssertTrue(perturbed.coreMatches(original),
                      "Sobol perturbation must preserve CORE weights")
    }

    // ── Decision: level probabilities sum to 1 ──

    func testDecision_levelProbsSumToOne() {
        let hists = [
            CountedHist.fromCounts([100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            CountedHist.fromCounts([10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 5, 5]),
            CountedHist.fromCounts([0, 0, 0, 0, 50, 50, 0, 0, 0, 0, 0, 0, 0, 0]),
        ]
        for h in hists {
            let (p0, p1, p2, p3) = h.levelProbabilities()
            XCTAssertEqual(p0 + p1 + p2 + p3, 1.0, accuracy: 1e-5)
        }
    }

    // ── Decision: confidence + dither = 1 ──

    func testDecision_confidencePlusDitherIsOne() {
        let h = CountedHist.fromCounts([0, 0, 0, 0, 50, 50, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(h.levelConfidence + h.ditherBudget, 1.0, accuracy: 1e-5)
    }

    // ── Decision: R,G,B independent ──

    func testDecision_channelsIndependent() {
        let hG = CountedHist.fromCounts([0,0,0,0,0,0,50,50,0,0,0,0,0,0])
        let hB = CountedHist.fromCounts([0,0,0,0,0,0,0,0,0,0,0,50,50,0])
        let hR1 = CountedHist.fromCounts([100,0,0,0,0,0,0,0,0,0,0,0,0,0])
        let hR2 = CountedHist.fromCounts([0,0,0,0,0,0,0,0,0,0,0,0,0,100])

        let bd1 = BlockDecision(histR: hR1, histG: hG, histB: hB, epoch: 0)
        let bd2 = BlockDecision(histR: hR2, histG: hG, histB: hB, epoch: 0)

        // Changing R doesn't affect G or B decisions
        XCTAssertEqual(bd1.g.level, bd2.g.level, "G level unchanged when R changes")
        XCTAssertEqual(bd1.b.level, bd2.b.level, "B level unchanged when R changes")
    }
}
