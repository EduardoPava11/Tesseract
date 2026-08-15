// ResolutionGateTests.swift
// Tesseract
//
// P1's gate: parity with spec/quantization/ResolutionLadder.hs RL1 to
// RL4, plus the budget the amendment exists to produce.
//
// The point of the amendment is that the fine rung goes to the
// BOUNDARY rather than to the subject, so the tests that matter are
// the symmetry (RL1's ridge) and the budget on a realistic depth
// field. Pure logic, runs on the simulator.

import XCTest
@testable import Tesseract

final class ResolutionGateTests: XCTestCase {

    // MARK: - RL1: the ridge

    func testGateIsSymmetricAboutTheBand() {
        // Solid figure and solid ground are the SAME case. This is
        // the whole amendment, so it is the first thing gated.
        for i in 0...512 {
            let t = Double(i) / 512
            XCTAssertEqual(ResolutionGate.rung(coverage: t),
                           ResolutionGate.rung(coverage: 1 - t),
                           "the gate must not care WHICH side of the edge a cell is on")
        }
    }

    func testSolidEndsTakeTheFloorRungAndTheBandCoreTheFine() {
        XCTAssertEqual(ResolutionGate.rung(coverage: 0), 16)
        XCTAssertEqual(ResolutionGate.rung(coverage: 1), 16)
        XCTAssertEqual(ResolutionGate.rung(coverage: 0.5), 64)
    }

    func testThresholdsAreTheBayerLevelsExactly() {
        let g = ResolutionGate.self
        XCTAssertEqual(g.bayerMin, 1.0 / 32, accuracy: 1e-15)
        XCTAssertEqual(g.bayerMax, 31.0 / 32, accuracy: 1e-15)
        XCTAssertEqual(g.bayerIn1, 3.0 / 32, accuracy: 1e-15)
        XCTAssertEqual(g.bayerIn2, 29.0 / 32, accuracy: 1e-15)
        // and the gate switches AT them, not near them
        XCTAssertEqual(g.rung(coverage: g.bayerMin - 1e-9), 16)
        XCTAssertEqual(g.rung(coverage: g.bayerMin), 32)
        XCTAssertEqual(g.rung(coverage: g.bayerIn1 - 1e-9), 32)
        XCTAssertEqual(g.rung(coverage: g.bayerIn1), 64)
        XCTAssertEqual(g.rung(coverage: g.bayerMax), 32)
        XCTAssertEqual(g.rung(coverage: g.bayerMax + 1e-9), 16)
    }

    func testTheGateIsARidgeNotARamp() {
        let sweep = (0...512).map { Double($0) / 512 }
        let rs = sweep.map { ResolutionGate.rung(coverage: $0) }
        XCTAssertEqual(rs, rs.reversed(), "a ridge reads the same backwards")
        XCTAssertEqual(rs.first, 16)
        XCTAssertEqual(rs.last, 16)
        XCTAssertEqual(rs.max(), 64)
        // NOT monotone: that was the old gate, and its failure here is
        // the amendment working.
        XCTAssertFalse(zip(rs, rs.dropFirst()).allSatisfy { $0 <= $1 },
                       "the amended gate must NOT be monotone in coverage")
    }

    // MARK: - RL3: occupancy survives the amendment

    func testOccupancyUnchanged() {
        XCTAssertEqual(ResolutionGate.rungs.map { ResolutionGate.occupancy(rung: $0) },
                       [1, 4, 16])
    }

    // MARK: - The budget the amendment exists to produce

    /// A realistic coverage field: a subject with a soft silhouette,
    /// which is what the depth mixture actually produces.
    private func coverageField(side: Int = 64, radius: Double = 18,
                               edge: Double = 4) -> [Double] {
        var out: [Double] = []
        let cx = 32.0, cy = 32.0
        for y in 0..<side {
            for x in 0..<side {
                let dx = Double(x) - cx, dy = Double(y) - cy
                let r = (dx * dx + dy * dy).squareRoot()
                // 0 deep inside the subject, 1 far outside, soft between.
                out.append(max(0, min(1, (r - (radius - edge / 2)) / edge)))
            }
        }
        return out
    }

    func testTheFineRungGoesToTheBoundaryAndIsASmallMinority() {
        let sel = ResolutionGate.select(coverage: coverageField())
        XCTAssertEqual(sel.rungs.count, 64 * 64)
        XCTAssertEqual(sel.budget.reduce(0, +), 1.0, accuracy: 1e-12)

        // The band is a thin shell, so the fine rung must be a small
        // minority. If this ever grows past a third of the frame the
        // capture has no clean figure/ground split, and that is worth
        // failing on rather than paying for silently.
        XCTAssertLessThan(sel.fineShare, 0.33,
                          "the fine rung is for the boundary, not the subject")
        XCTAssertGreaterThan(sel.budget[0], 0.5,
                             "solid regions are the majority and belong at rung 16")
        print(String(format: "  BUDGET  rung16 %.1f%%  rung32 %.1f%%  rung64 %.1f%%",
                     sel.budget[0] * 100, sel.budget[1] * 100, sel.budget[2] * 100))
    }

    func testAFlatSceneSpendsNothingOnTheFineRung() {
        // No subject at all: coverage is solid ground everywhere, so
        // there is no edge and the fine rung must go unused.
        let flat = [Double](repeating: 1.0, count: 64 * 64)
        let sel = ResolutionGate.select(coverage: flat)
        XCTAssertEqual(sel.fineShare, 0)
        XCTAssertEqual(sel.budget[0], 1.0, accuracy: 1e-12)
    }

    func testEmptyFieldIsTotal() {
        let sel = ResolutionGate.select(coverage: [])
        XCTAssertTrue(sel.rungs.isEmpty)
        XCTAssertEqual(sel.budget, [0, 0, 0])
    }
}
