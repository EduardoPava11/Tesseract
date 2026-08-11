// LatticeLawTests.swift
// Tesseract
//
// The grid constitution, exercised in CI — previously these laws ran
// only as launch-time preconditions (TesseractApp.init, DEBUG), so a
// layout regression could pass the test suite and die on first launch.
// Pure logic: runs on simulator.

import XCTest
@testable import Tesseract

final class LatticeLawTests: XCTestCase {

    /// All three constitutions: lattice numbers, scene claims
    /// (disjoint ∧ in-bounds ∧ touch-floor ∧ faces total), mechanics.
    func testConstitutionSelfChecks() {
        TesseractLattice.selfCheck()
        GridLayout.selfCheck()
        CellMechanics.selfCheck()
    }

    /// The 2026-08-10 upscale: every interactive region clears the raised
    /// button-row height, not just the 44pt HIG floor.
    func testButtonsMeetTheUpscaledRow() {
        for (scene, regions) in GridLayout.allScenes {
            for r in regions where r.interactive {
                XCTAssertGreaterThanOrEqual(
                    min(r.w, r.h), TesseractLattice.touchFloorCells,
                    "\(scene).\(r.name) breaks the touch floor")
                XCTAssertGreaterThanOrEqual(
                    max(r.w, r.h), TesseractLattice.buttonRowCells,
                    "\(scene).\(r.name) is smaller than the button row")
            }
        }
    }

    /// The shutter closure law: disc + ring band tile the footprint.
    func testRecordButtonClosure() {
        XCTAssertEqual(TesseractLattice.recordDiscCells + 2 * 2,
                       TesseractLattice.recordCells,
                       "disc(2r) + ring(2t) must equal the footprint")
    }
}
