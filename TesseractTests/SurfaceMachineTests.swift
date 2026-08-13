// SurfaceMachineTests.swift
// Tesseract
//
// Swift mirrors of spec/ui/SurfaceMachine.hs (SM1–SM4) plus the one
// law only the port can check: the machine's words, rasterized by
// CellText at their actual registers, FIT their GridRegions — the
// strict grid admits no off-grid ink. Pure logic + UIKit raster —
// runs on the simulator.

import XCTest
@testable import Tesseract

final class SurfaceMachineTests: XCTestCase {

    private var allStates: [SurfaceMachine.State] {
        [.waking, .watching, .weaving, .solving, .sealed,
         .refused(.cameraOff), .refused(.noTrueDepth),
         .refused(.noCenterStage), .refused(.noFaceTracking),
         .refused(.exportFailed), .refused(.unknown("boom"))]
    }

    // MARK: - SM1: voice

    func testEveryStateSpeaksADistinctSquareWord() {
        let words = allStates.map(\.word)
        XCTAssertEqual(Set(words).count, words.count, "words must be distinct")
        for w in words {
            XCTAssertFalse(w.isEmpty)
            XCTAssertTrue(w.allSatisfy { $0.isUppercase || $0 == " " },
                          "\(w): uppercase letters and spaces only (SM1)")
        }
    }

    func testTotalityOverCameraStates() {
        // Every CameraState surfaces exactly one machine state —
        // and the FACE twin maps case for case.
        XCTAssertEqual(SurfaceMachine.state(for: CameraState.idle, hasPreview: false), .waking)
        XCTAssertEqual(SurfaceMachine.state(for: CameraState.previewing, hasPreview: false),
                       .waking, "graceful arrival: no first frame = still waking")
        XCTAssertEqual(SurfaceMachine.state(for: CameraState.previewing, hasPreview: true), .watching)
        XCTAssertEqual(SurfaceMachine.state(for: CameraState.recording(7), hasPreview: true), .weaving)
        XCTAssertEqual(SurfaceMachine.state(for: CameraState.processing, hasPreview: true), .solving)
        XCTAssertEqual(SurfaceMachine.state(for: CameraState.done, hasPreview: true), .sealed)
        XCTAssertEqual(
            SurfaceMachine.state(for: CameraState.error(CameraManager.noTrueDepthMessage),
                                 hasPreview: false),
            .refused(.noTrueDepth))
        XCTAssertEqual(
            SurfaceMachine.state(for: CameraState.error(CameraManager.noCenterStageMessage),
                                 hasPreview: false),
            .refused(.noCenterStage))
        XCTAssertEqual(
            SurfaceMachine.state(for: CameraState.error("boom"), hasPreview: false),
            .refused(.unknown("boom")))
        XCTAssertEqual(SurfaceMachine.state(for: FaceCaptureState.processing,
                                            hasPreview: true), .solving)
        XCTAssertEqual(SurfaceMachine.state(for: FaceCaptureState.recording(3),
                                            hasPreview: true), .weaving)
    }

    // MARK: - SM2: the capture arc

    func testCaptureArcAdmitsNoSkips() {
        XCTAssertTrue(SurfaceMachine.canStep(from: .watching, to: .weaving))
        XCTAssertTrue(SurfaceMachine.canStep(from: .weaving, to: .solving))
        XCTAssertTrue(SurfaceMachine.canStep(from: .solving, to: .sealed))
        XCTAssertFalse(SurfaceMachine.canStep(from: .weaving, to: .sealed),
                       "after capture the machine MUST surface the solve")
        XCTAssertFalse(SurfaceMachine.canStep(from: .watching, to: .solving))
        XCTAssertFalse(SurfaceMachine.canStep(from: .watching, to: .sealed))
        // WEAVING is re-entered only through WATCHING.
        for s in allStates where s != .watching {
            XCTAssertFalse(SurfaceMachine.canStep(from: s, to: .weaving),
                           "\(s) must not start a weave")
        }
    }

    // MARK: - SM3: un-interruptible work

    func testExactlyTheWorkingStatesRefuseInterruption() {
        for s in allStates {
            let working = (s == .weaving || s == .solving)
            XCTAssertEqual(s.interruptible, !working,
                           "\(s): interruptible must be \(!working) (SM3)")
        }
    }

    // MARK: - SM4: terminals are exactly the hardware refusals

    func testHardwareRefusalsAreTerminal() {
        let terminals: [SurfaceMachine.State] =
            [.refused(.noTrueDepth), .refused(.noCenterStage),
             .refused(.noFaceTracking)]
        for t in terminals {
            for s in allStates {
                XCTAssertFalse(SurfaceMachine.canStep(from: t, to: s),
                               "\(t) is terminal (SM4)")
            }
        }
        // Soft refusals recover.
        XCTAssertTrue(SurfaceMachine.canStep(from: .refused(.cameraOff), to: .waking))
        XCTAssertTrue(SurfaceMachine.canStep(from: .refused(.exportFailed), to: .watching))
    }

    // MARK: - The strict grid: words fit their regions, exactly

    /// The one law only the port can check: rasterize each spoken
    /// word with CellText at the register its view uses, and require
    /// the ink to fit the region — mask width × cell pt ≤ region
    /// width pt. No estimates, the actual raster (SM1's teeth).
    @MainActor
    func testWordsFitTheirRegions() throws {
        // (word, register rows, region) as the state views place them.
        let placements: [(String, Int, GridRegion)] = [
            (SurfaceMachine.State.waking.word, TypeRows.label, GridLayout.idleHint),
            (SurfaceMachine.State.weaving.word + " 3.2s", TypeRows.label, GridLayout.recTime),
            (SurfaceMachine.State.solving.word, TypeRows.body, GridLayout.procTitle),
            (SurfaceMachine.State.refused(.cameraOff).word, TypeRows.body, GridLayout.errTitle),
            (SurfaceMachine.State.refused(.noTrueDepth).word, TypeRows.body, GridLayout.errTitle),
            (SurfaceMachine.State.refused(.noCenterStage).word, TypeRows.body, GridLayout.errTitle),
            (SurfaceMachine.State.refused(.noFaceTracking).word, TypeRows.body, GridLayout.errTitle),
            (SurfaceMachine.State.refused(.exportFailed).word, TypeRows.body, GridLayout.errTitle),
        ]
        for (word, rows, region) in placements {
            let mask = try XCTUnwrap(CellText.snap(word, rows: rows),
                                     "\(word) must rasterize")
            let inkWidth = mask.size.width * Lattice.pt(1)
            let regionWidth = Lattice.gif(region.w)
            XCTAssertLessThanOrEqual(inkWidth, regionWidth,
                "\(word) at \(rows) rows must fit \(region.name) " +
                "(\(inkWidth)pt ink vs \(regionWidth)pt region)")
        }
    }
}
