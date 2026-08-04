// CellMechanicsParityTests.swift
// Tesseract
//
// Swift↔Haskell golden parity for the control-face algebra
// (spec/ui/CellMechanics.hs, UM1–UM6). The golden vectors below are the
// spec's printed output.

import XCTest
@testable import Tesseract

final class CellMechanicsParityTests: XCTestCase {

    // UM6: the flat table (index = state×2 + beat).
    func testGoldenTable() {
        XCTAssertEqual(CellMechanics.faceTreatmentTable, [0, 1, 2, 2, 3, 3, 4, 4])
        XCTAssertEqual(CellMechanics.faceTreatmentTable.count,
                       CellMechanics.controlStates.count * 2)
    }

    // UM4: the 16-tick beat pin; tick 1 is the reduce-motion anchor.
    func testGoldenBeat() {
        let expected = [true, false, false, false,
                        true, false, false, false,
                        true, false, false, false,
                        true, false, false, false]
        XCTAssertEqual(CellMechanics.goldenBeat, expected)
        XCTAssertFalse(CellMechanics.goldenBeat[1])
    }

    // UM5: idle folds ghost(0) off-beat, lit(1) on-beat.
    func testIdleFold() {
        for t in 0..<16 {
            let expected = t % 4 == 0 ? 1 : 0
            XCTAssertEqual(CellMechanics.faceTreatment(state: 0, tick: t), expected,
                           "idle at tick \(t)")
        }
    }

    // UM3: only idle reads the tick.
    func testNonIdleTickInvariant() {
        for s in 1...3 {
            let base = CellMechanics.faceTreatment(state: s, tick: 0)
            for t in 0..<16 {
                XCTAssertEqual(CellMechanics.faceTreatment(state: s, tick: t), base,
                               "state \(s) at tick \(t)")
            }
        }
        XCTAssertEqual(CellMechanics.faceTreatment(state: 1, tick: 0), 2)  // pressed → inverted
        XCTAssertEqual(CellMechanics.faceTreatment(state: 2, tick: 0), 3)  // busy → busy ink
        XCTAssertEqual(CellMechanics.faceTreatment(state: 3, tick: 0), 4)  // disabled → checker
    }

    // M6 + structural laws (the selfCheck body, assertable in tests too).
    func testSelfCheck() {
        CellMechanics.selfCheck()
        XCTAssertTrue(CellMechanics.controlFaces.values.allSatisfy {
            CellMechanics.faceKinds.contains($0)
        })
    }
}
