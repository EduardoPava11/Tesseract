// EditMachineTests.swift
// Tesseract
//
// Swift mirrors of spec/ui/EditMachine.hs (EM1–EM13) plus the one law
// only the port can check: the machine's words, rasterized by CellText
// at their actual registers, FIT their GridRegions — the strict grid
// admits no off-grid ink. Pure logic + UIKit raster — runs on the
// simulator.
//
// ★ THIS FILE IS SurfaceMachineTests RENAMED, NOT REPLACED. Every
// XCTAssert in it has a destination here. Two INVERT by spec, and both
// inversions are recorded below with the strictly stronger assertion
// that replaces them — no assertion was deleted for being
// inconvenient:
//
//   1. `state(.done, ·) == .sealed`  →  `== .tuning`
//      Forced by EM3 (`not (canStep Solving Sealed)`) and EM10
//      (SEALED is a COMMIT, not an arrival). The old intent — ".done
//      surfaces a finished artifact" — is preserved and strengthened:
//      it now surfaces that artifact INSIDE the editor, where EM10
//      can fork it.
//   2. `canStep(.solving, .sealed) == true`  →  `== false`
//      Replaced by a strictly stronger triple (solving→tuning,
//      tuning→sealed, ¬solving→sealed) PLUS EM3's depth-5 path
//      enumeration proving SOLVING precedes TUNING on every
//      WEAVING ⟶ SEALED path. The old test proved one edge; this
//      proves the whole arc.
//
// And one redirection: `canStep(.refused(.exportFailed), .watching)`
// becomes `→ .tuning` (EditMachine.hs:161) — correct by EM10, since
// the capture is still held and a failed export returns to the
// editor, not to a re-shoot.

import XCTest
@testable import Tesseract

final class EditMachineTests: XCTestCase {

    private var allStates: [EditMachine.State] { EditMachine.allStates }

    /// Payload-erased equality — `.refused(.unknown(msg))` is ONE
    /// state whatever the system string says.
    private func same(_ a: EditMachine.State, _ b: EditMachine.State) -> Bool {
        EditMachine.erased(a) == EditMachine.erased(b)
    }

    /// The spec's `pathsFrom`: simple paths of bounded length, self
    /// loops excluded (a loop adds no new state to a path).
    private func paths(from s: EditMachine.State, depth: Int) -> [[EditMachine.State]] {
        guard depth > 0 else { return [[s]] }
        var out: [[EditMachine.State]] = [[s]]
        for t in EditMachine.successors(of: s) where !same(t, s) {
            for p in paths(from: t, depth: depth - 1) { out.append([s] + p) }
        }
        return out
    }

    // MARK: - EM6 (SM1 preserved): voice

    func testEveryStateSpeaksADistinctSquareWord() {
        let words = allStates.map(\.word)
        XCTAssertEqual(words.count, 13, "the state set widened 11 → 13")
        XCTAssertEqual(Set(words).count, words.count, "words must be distinct")
        for w in words {
            XCTAssertFalse(w.isEmpty)
            XCTAssertTrue(w.allSatisfy { $0.isUppercase || $0 == " " },
                          "\(w): uppercase letters and spaces only (EM6)")
        }
        // ⚠ RULING R1: the newer spec supersedes — Refused Unknown
        // speaks REFUSED where SurfaceMachine.hs said ERROR. This
        // CHANGES shipped copy on the error scene.
        XCTAssertEqual(EditMachine.State.refused(.unknown("boom")).word, "REFUSED")
    }

    func testTotalityOverCameraStates() {
        // Every CameraState surfaces exactly one machine state on the
        // capture axis — and the FACE twin maps case for case.
        let cap = EditMachine.Surface.capture
        XCTAssertEqual(EditMachine.state(for: CameraState.idle, surface: cap,
                                         hasPreview: false), .waking)
        XCTAssertEqual(EditMachine.state(for: CameraState.previewing, surface: cap,
                                         hasPreview: false),
                       .waking, "graceful arrival: no first frame = still waking")
        XCTAssertEqual(EditMachine.state(for: CameraState.previewing, surface: cap,
                                         hasPreview: true), .watching)
        XCTAssertEqual(EditMachine.state(for: CameraState.recording(7), surface: cap,
                                         hasPreview: true), .weaving)
        XCTAssertEqual(EditMachine.state(for: CameraState.processing, surface: cap,
                                         hasPreview: true), .solving)
        // ★ INVERSION 1 (ruled): .done lands in the EDITOR.
        XCTAssertEqual(EditMachine.state(for: CameraState.done, surface: cap,
                                         hasPreview: true), .tuning)
        XCTAssertEqual(
            EditMachine.state(for: CameraState.error(CameraManager.noTrueDepthMessage),
                              surface: cap, hasPreview: false),
            .refused(.noTrueDepth))
        XCTAssertEqual(
            EditMachine.state(for: CameraState.error(CameraManager.noCenterStageMessage),
                              surface: cap, hasPreview: false),
            .refused(.noCenterStage))
        XCTAssertEqual(
            EditMachine.state(for: CameraState.error("boom"),
                              surface: cap, hasPreview: false),
            .refused(.unknown("boom")))
        XCTAssertEqual(EditMachine.state(for: FaceCaptureState.processing,
                                         surface: cap, hasPreview: true), .solving)
        XCTAssertEqual(EditMachine.state(for: FaceCaptureState.recording(3),
                                         surface: cap, hasPreview: true), .weaving)
    }

    /// The edit axis: the surface decides SHELVING / TUNING / SEALED,
    /// which `CameraState` alone cannot distinguish — and a REFUSAL
    /// dominates any surface (the clause order is load-bearing, so it
    /// is tested, not merely commented).
    func testTheEditAxisAndRefusalDominance() {
        XCTAssertEqual(EditMachine.state(for: CameraState.previewing,
                                         surface: .shelf, hasPreview: true), .shelving)
        XCTAssertEqual(EditMachine.state(for: CameraState.done,
                                         surface: .editing(sealed: false),
                                         hasPreview: true), .tuning)
        XCTAssertEqual(EditMachine.state(for: CameraState.done,
                                         surface: .editing(sealed: true),
                                         hasPreview: true), .sealed)
        for surface: EditMachine.Surface in [.shelf, .capture,
                                             .editing(sealed: false),
                                             .editing(sealed: true)] {
            XCTAssertEqual(
                EditMachine.state(for: CameraState.error(CameraManager.noCenterStageMessage),
                                  surface: surface, hasPreview: true),
                .refused(.noCenterStage),
                "a hardware refusal must dominate every surface")
            XCTAssertEqual(
                EditMachine.state(for: FaceCaptureState.error(
                                    FaceCaptureManager.faceTrackingUnsupportedMessage),
                                  surface: surface, hasPreview: true),
                .refused(.noFaceTracking))
        }
    }

    // MARK: - EM1: the shelf is home

    func testShelfIsHome() {
        XCTAssertTrue(EditMachine.canStep(from: .waking, to: .shelving))
        for s in allStates where !EditMachine.hardwareRefusals.contains(s) {
            XCTAssertTrue(EditMachine.reachable(from: s).contains(.shelving),
                          "\(s.word) must be able to reach the shelf (EM1)")
        }
        for t in EditMachine.hardwareRefusals {
            XCTAssertFalse(EditMachine.reachable(from: t).contains(.shelving),
                           "\(t.word) is terminal — it reaches nothing (EM1/EM7)")
        }
    }

    // MARK: - EM2: exactly two loops

    func testExactlyTwoLoops() {
        let loops = allStates.filter { EditMachine.canStep(from: $0, to: $0) }
        XCTAssertEqual(loops, EditMachine.loops,
                       "exactly WATCHING (the live read) and TUNING (the tick)")
        for s in loops {
            XCTAssertTrue(s.interruptible, "\(s.word): a loop you cannot exit is a hang")
            XCTAssertGreaterThanOrEqual(EditMachine.successors(of: s).count, 2,
                                        "\(s.word) must be leavable")
        }
    }

    // MARK: - EM3 (SM2 preserved): the capture arc admits no skips

    func testCaptureArcAdmitsNoSkips() {
        XCTAssertTrue(EditMachine.canStep(from: .watching, to: .weaving))
        XCTAssertTrue(EditMachine.canStep(from: .weaving, to: .solving))
        XCTAssertFalse(EditMachine.canStep(from: .weaving, to: .sealed),
                       "after capture the machine MUST surface the solve")
        XCTAssertFalse(EditMachine.canStep(from: .weaving, to: .tuning))
        XCTAssertFalse(EditMachine.canStep(from: .watching, to: .solving))
        XCTAssertFalse(EditMachine.canStep(from: .watching, to: .sealed))

        // ★ INVERSION 2 (ruled), with the stronger triple that
        // replaces the old single edge.
        XCTAssertFalse(EditMachine.canStep(from: .solving, to: .sealed))
        XCTAssertTrue(EditMachine.canStep(from: .solving, to: .tuning))
        XCTAssertTrue(EditMachine.canStep(from: .tuning, to: .sealed))

        // WEAVING is re-entered only through WATCHING (in-edge
        // exactness — the same set equality the spec asserts).
        for s in allStates where s != .watching {
            XCTAssertFalse(EditMachine.canStep(from: s, to: .weaving),
                           "\(s.word) must not start a weave")
        }

        // The whole arc, by enumeration: every path from WEAVING that
        // reaches SEALED passes SOLVING and THEN TUNING.
        let arcs = paths(from: .weaving, depth: 5).filter { $0.contains(.sealed) }
        XCTAssertFalse(arcs.isEmpty, "at least one WEAVING ⟶ SEALED path must exist")
        for p in arcs {
            let upto = Array(p.prefix { $0 != .sealed })
            guard let iSolve = upto.firstIndex(of: .solving),
                  let iTune = upto.firstIndex(of: .tuning) else {
                return XCTFail("path \(p.map(\.word)) skipped SOLVING or TUNING")
            }
            XCTAssertLessThan(iSolve, iTune,
                              "SOLVING must precede TUNING on \(p.map(\.word))")
        }
    }

    // MARK: - EM4 / EM5: the SM3 split

    func testExactlyTheWorkingStatesRefuseInterruption() {
        for s in allStates {
            let working = (s == .weaving || s == .solving)
            XCTAssertEqual(s.interruptible, !working,
                           "\(s.word): interruptible must be \(!working) (EM4)")
        }
        // EM5 ★ — the half that bends: TUNING works AND may be left.
        XCTAssertTrue(EditMachine.State.tuning.interruptible)
        XCTAssertTrue(EditMachine.canStep(from: .tuning, to: .tuning))
        XCTAssertGreaterThan(EditMachine.successors(of: .tuning).count, 1)
        for s in allStates {
            XCTAssertTrue(s.interruptible || !EditMachine.canStep(from: s, to: s),
                          "\(s.word): an un-interruptible loop is a hang (EM5)")
        }
    }

    // MARK: - EM7 (SM4 preserved): terminals

    func testHardwareRefusalsAreTerminal() {
        let terminals: [EditMachine.State] =
            [.refused(.noTrueDepth), .refused(.noCenterStage),
             .refused(.noFaceTracking)]
        XCTAssertEqual(terminals, EditMachine.hardwareRefusals)
        for t in terminals {
            for s in allStates {
                XCTAssertFalse(EditMachine.canStep(from: t, to: s),
                               "\(t.word) is terminal (EM7)")
            }
            XCTAssertTrue(EditMachine.successors(of: t).isEmpty)
        }
        // EXACTNESS: nothing else is a dead end.
        let deadEnds = allStates.filter { EditMachine.successors(of: $0).isEmpty }
        XCTAssertEqual(deadEnds, terminals,
                       "the terminals are EXACTLY the hardware refusals")
        // Soft refusals recover — with the one ruled redirection.
        XCTAssertTrue(EditMachine.canStep(from: .refused(.cameraOff), to: .waking))
        XCTAssertTrue(EditMachine.canStep(from: .refused(.exportFailed), to: .tuning),
                      "a failed export returns to the EDITOR: the capture is still held")
        XCTAssertTrue(EditMachine.canStep(from: .refused(.unknown("boom")), to: .shelving))
    }

    // MARK: - EM9: reachability

    func testReachability() {
        let seen = EditMachine.reachable(from: .waking)
        for s in allStates {
            XCTAssertTrue(seen.contains(EditMachine.erased(s)),
                          "\(s.word) is unreachable from WAKING (EM9)")
        }
        for s in allStates where s != .waking {
            let inEdges = allStates.filter { EditMachine.canStep(from: $0, to: s) }
            XCTAssertFalse(inEdges.isEmpty, "\(s.word) is an orphan (EM9)")
        }
    }

    // MARK: - EM10: fork freedom

    func testForkFreedom() {
        XCTAssertTrue(EditMachine.canStep(from: .tuning, to: .sealed))
        XCTAssertTrue(EditMachine.canStep(from: .sealed, to: .tuning))
        let cycle: [EditMachine.State] = [.tuning, .sealed]
        XCTAssertFalse(cycle.contains(.weaving), "no re-capture is required")
        XCTAssertFalse(cycle.contains(.solving))
        XCTAssertTrue(EditMachine.reachable(from: .sealed).contains(.tuning))
    }

    // MARK: - EM12: weave = watch + keep (RETENTION ONLY)

    func testDispositionIsRetentionOnly() {
        XCTAssertEqual(EditMachine.disposition(of: .watching), .discarded)
        XCTAssertEqual(EditMachine.disposition(of: .weaving), .kept)
        let carriers = allStates.filter { EditMachine.disposition(of: $0) != nil }
        XCTAssertEqual(carriers, [.watching, .weaving])
        // The two enums cannot drift: EM12's dispositions map 1:1 onto
        // the pipeline's, and the pipeline is the ONE encoder.
        XCTAssertEqual(EditMachine.pipelineDisposition(.kept), .artifact)
        XCTAssertEqual(EditMachine.pipelineDisposition(.discarded), .generatingState)
        XCTAssertEqual(EditMachine.Disposition.allCases.count,
                       DyadPipeline.Disposition.allCases.count,
                       "a third disposition on either side re-opens EM12")
    }

    // MARK: - The strict grid: words fit their regions, exactly

    /// The one law only the port can check: rasterize each spoken
    /// word with CellText at the register its view uses, and require
    /// the ink to fit the region — mask width × cell pt ≤ region
    /// width pt. No estimates, the actual raster (EM6's teeth).
    @MainActor
    func testWordsFitTheirRegions() throws {
        // (word, register rows, region) as the state views place them.
        let placements: [(String, Int, GridRegion)] = [
            (EditMachine.State.waking.word, TypeRows.label, GridLayout.idleHint),
            (EditMachine.State.weaving.word + " 3.2s", TypeRows.label, GridLayout.recTime),
            (EditMachine.State.solving.word, TypeRows.body, GridLayout.procTitle),
            // The four words the widened state set added. SHELF and
            // SEALED ride the library/result titles; TUNING is the
            // editor's word; REFUSED is R1's copy change.
            (EditMachine.State.shelving.word, TypeRows.display, GridLayout.libTitle),
            (EditMachine.State.tuning.word, TypeRows.body, GridLayout.procTitle),
            (EditMachine.State.sealed.word, TypeRows.body, GridLayout.resultMetrics),
            (EditMachine.State.refused(.unknown("x")).word, TypeRows.body, GridLayout.errTitle),
            (EditMachine.State.refused(.cameraOff).word, TypeRows.body, GridLayout.errTitle),
            (EditMachine.State.refused(.noTrueDepth).word, TypeRows.body, GridLayout.errTitle),
            (EditMachine.State.refused(.noCenterStage).word, TypeRows.body, GridLayout.errTitle),
            (EditMachine.State.refused(.noFaceTracking).word, TypeRows.body, GridLayout.errTitle),
            (EditMachine.State.refused(.exportFailed).word, TypeRows.body, GridLayout.errTitle),
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
