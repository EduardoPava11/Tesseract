// EditMachine.swift
// Tesseract
//
// PORT of spec/ui/EditMachine.hs (EM1–EM13). The Haskell is
// authoritative; this is a port and may not improve on it.
//
// ★ EDIT IS THE WHOLE APP (Daniel's decree, 2026-08-13): capture is
// an input step, the shelf is home, one moment yields many GIFs. This
// file REPLACES Tesseract/UI/SurfaceMachine.swift, which is deleted in
// the same commit. Replacement rather than widening is forced, not
// preferred: the two edge relations DISAGREE IN DIRECTION on five
// pairs (waking→watching, solving→sealed, sealed→watching,
// exportFailed→watching, unknown→waking), and EditMachine's laws are
// EXACT-SET laws (EM2 `[s | canStep s s] == loops`, EM3
// `not (canStep Solving Sealed)`, EM4 and EM7 set equalities), so no
// union of the two relations can satisfy both specs. One word also
// collides: Refused Unknown speaks "REFUSED" here and spoke "ERROR"
// there, and EM6 requires distinctness.
//
// SurfaceMachine's five laws are NOT discarded — they are re-proved
// over the larger machine: SM1 = EM6, SM2 = EM3, SM3 = EM4 (+ EM5,
// the half that bends), SM4 = EM7, SM5 = the one-scene-per-state
// switch in ContentView. Every assertion in the old
// SurfaceMachineTests has a destination in EditMachineTests; the two
// that invert (`.done → .sealed`, `canStep(.solving,.sealed)`) are
// recorded there as RULED inversions with the strictly stronger
// assertions that replace them.
//
// ── THE ONE LAW THAT BENT (EM4 / EM5) ───────────────────────────
// SM3 said the working states refuse interruption. That was one law
// doing two jobs. A capture-solve (SOLVING) owns the ONLY copy of a
// moment and must complete. A tick-solve (TUNING) owns a pure
// function of data already held, so it must be ABANDONABLE — or the
// dial does not answer. Abandonment is safe because of coherence
// (EM8): ticks are SUPERSEDED, never queued.
//
// ── EM13, AND ITS ONE DELIBERATE EXCEPTION ──────────────────────
// THE PREVIEW IS THE GIF, bit for bit (CLAUDE.md decree): WATCHING
// and WEAVING run the SAME encoder — `DyadPipeline` — and differ only
// in RETENTION (EM12). DyadPreview.swift is deleted; `DyadPipeline
// .Live` is a DRIVER, not a second law. The exception already on
// record and NOT silently inherited: the live σ-side chaos target
// pools the CURRENT frame where the export pools the 4-frame S4
// group. Closing it means feeding pooled targets to the Metal kernel
// as a buffer instead of its in-kernel 16-texel pool. Device pass
// owed on the 5 Hz pooled solve.

import Foundation

enum EditMachine {

    // ════════════════════════════════════════════════════════════
    // § 1. THE MACHINE (spec §1)
    // ════════════════════════════════════════════════════════════

    enum Refusal: Equatable, Sendable {
        case cameraOff
        case noTrueDepth
        case noCenterStage
        case noFaceTracking
        case exportFailed
        case unknown(String)
    }

    enum State: Equatable, Sendable {
        case waking      // the device opens
        case shelving    // ★ HOME: the shelf of captures and their GIFs
        case watching    // ★ loop 1 — the live read, nothing kept
        case weaving     // 64 frames being kept
        case solving     // the capture-solve; must complete
        case tuning      // ★ loop 2 — the tick: 64³ per dial stop
        case sealed      // a variant has been written to the shelf
        case refused(Refusal)

        /// EM6 (SM1 preserved) — THE word the grid speaks in squares:
        /// uppercase letters and spaces only, digits ride payload rows.
        ///
        /// ⚠ RULING R1: `Refused Unknown` speaks "REFUSED" here
        /// (EditMachine.hs:126) where SurfaceMachine.hs:72 said
        /// "ERROR". The newer spec supersedes and the spec is
        /// authoritative, so the port says REFUSED — this CHANGES
        /// shipped copy on the error scene, and the raster-fit test
        /// gains a row proving 7 characters fit `errTitle`.
        var word: String {
            switch self {
            case .waking:                    return "WAKING"
            case .shelving:                  return "SHELF"
            case .watching:                  return "WATCHING"
            case .weaving:                   return "WEAVING"
            case .solving:                   return "SOLVING"
            case .tuning:                    return "TUNING"
            case .sealed:                    return "SEALED"
            case .refused(.cameraOff):       return "CAMERA OFF"
            case .refused(.noTrueDepth):     return "NO TRUEDEPTH"
            case .refused(.noCenterStage):   return "NO CENTER STAGE"
            case .refused(.noFaceTracking):  return "NO FACE TRACKING"
            case .refused(.exportFailed):    return "EXPORT FAILED"
            case .refused(.unknown):         return "REFUSED"
            }
        }

        /// EM4 + EM5 — the SM3 split. EXACTLY {WEAVING, SOLVING}
        /// refuse interruption: they own the only copy of a moment.
        /// TUNING works AND is interruptible — the combination SM3
        /// forbade, licensed here by purity (EM5).
        var interruptible: Bool {
            switch self {
            case .weaving, .solving: return false
            default: return true
            }
        }
    }

    // ════════════════════════════════════════════════════════════
    // § 2. THE EDIT AXIS
    // ════════════════════════════════════════════════════════════

    /// `CameraState` alone cannot distinguish SHELVING, TUNING and
    /// SEALED — they are all "not capturing" — so the machine reads
    /// TWO axes: the manager's capture state and the app's surface.
    enum Surface: Equatable, Sendable {
        case shelf                    // SHELVING — home (EM1)
        case capture                  // the camera decides the word
        case editing(sealed: Bool)    // TUNING / SEALED (EM10)
    }

    /// EM12 ★ — retention is the ONLY difference between the two
    /// loops. Asserted against `DyadPipeline.Disposition` in the
    /// tests (`.kept ↔ .artifact`, `.discarded ↔ .generatingState`)
    /// so the two enums cannot drift apart.
    enum Disposition: Equatable, Sendable, CaseIterable {
        case discarded
        case kept
    }

    /// EM12's correspondence, written down so the two enums cannot
    /// drift apart: the machine's disposition IS the pipeline's, and
    /// there is only ONE encoder behind both.
    ///
    ///   .kept      ↔ .artifact         (WEAVING keeps the result)
    ///   .discarded ↔ .generatingState  (WATCHING drops it)
    static func pipelineDisposition(_ d: Disposition) -> DyadPipeline.Disposition {
        switch d {
        case .kept:      return .artifact
        case .discarded: return .generatingState
        }
    }

    /// EM12 — non-nil exactly on the two dispositions the spec names.
    static func disposition(of state: State) -> Disposition? {
        switch state {
        case .watching: return .discarded
        case .weaving:  return .kept
        default:        return nil
        }
    }

    // ════════════════════════════════════════════════════════════
    // § 3. THE TOTAL MAP (SM1/EM6: every state surfaces)
    // ════════════════════════════════════════════════════════════

    /// ★ CLAUSE ORDER IS LOAD-BEARING.
    ///
    ///   1. a REFUSAL dominates any surface — a device that cannot
    ///      run must say so wherever the user happens to be, and
    ///      every refusal edge in the spec originates at WAKING;
    ///   2. `.shelf` speaks SHELF (EM1, home);
    ///   3. `.editing(sealed:)` speaks TUNING or SEALED (EM10);
    ///   4. `.capture` hands the word to the camera.
    ///
    /// ⚠ RULED INVERSION: `.done` maps to `.tuning`, not `.sealed`.
    /// Forced by EM3 (`not (canStep Solving Sealed)`) and EM10
    /// (SEALED is a COMMIT, not an arrival). The old assertion's
    /// intent — ".done surfaces a finished artifact" — is preserved
    /// and strengthened: `.done` now surfaces the finished artifact
    /// INSIDE the editor, where EM10 can fork it. The mapping keeps
    /// the map total and unambiguous whether or not the app has yet
    /// flipped `surface` to `.editing`: under EditMachine `.done`
    /// MEANS "the capture-solve completed and a capture is open".
    static func state(for camera: CameraState,
                      surface: Surface,
                      hasPreview: Bool) -> State {
        if case .error(let msg) = camera { return .refused(refusal(for: msg)) }
        switch surface {
        case .shelf:
            return .shelving
        case .editing(let sealed):
            return sealed ? .sealed : .tuning
        case .capture:
            switch camera {
            case .idle:       return .waking
            case .previewing: return hasPreview ? .watching : .waking
            case .recording:  return .weaving
            case .processing: return .solving
            case .done:       return .tuning
            case .error(let msg): return .refused(refusal(for: msg))
            }
        }
    }

    /// FACE twin: `FaceCaptureState` mirrors `CameraState` case for
    /// case — ONE machine serves both capture systems.
    static func state(for face: FaceCaptureState,
                      surface: Surface,
                      hasPreview: Bool) -> State {
        if case .error(let msg) = face { return .refused(refusal(for: msg)) }
        switch surface {
        case .shelf:
            return .shelving
        case .editing(let sealed):
            return sealed ? .sealed : .tuning
        case .capture:
            switch face {
            case .idle:       return .waking
            case .previewing: return hasPreview ? .watching : .waking
            case .recording:  return .weaving
            case .processing: return .solving
            case .done:       return .tuning
            case .error(let msg): return .refused(refusal(for: msg))
            }
        }
    }

    /// The two-register error voice, keyed off the managers' ruled
    /// message constants — the machine owns the headline words.
    /// Unchanged from SurfaceMachine (this function is the one part
    /// of the old machine that survives verbatim).
    static func refusal(for message: String) -> Refusal {
        switch message {
        case CameraManager.cameraDeniedMessage:                 return .cameraOff
        case CameraManager.noTrueDepthMessage:                  return .noTrueDepth
        case CameraManager.noCenterStageMessage:                return .noCenterStage
        case FaceCaptureManager.faceTrackingUnsupportedMessage: return .noFaceTracking
        case CameraManager.encodeFailedMessage:                 return .exportFailed
        default:                                                return .unknown(message)
        }
    }

    // ════════════════════════════════════════════════════════════
    // § 4. THE EDGE SET (spec §1 `edges`)
    // ════════════════════════════════════════════════════════════

    /// `Refusal.unknown` carries the system string as a payload, so a
    /// literal edge table cannot compare equal to a live state. The
    /// edge relation is therefore declared ONCE, as `successors`, and
    /// compared on the payload-erased form — one declaration, so
    /// `canStep` and `successors` cannot disagree (EM2/EM7/EM9 all
    /// read the same table).
    static func erased(_ s: State) -> State {
        if case .refused(.unknown) = s { return .refused(.unknown("")) }
        return s
    }

    /// The lawful edges, transcribed from spec/ui/EditMachine.hs
    /// §1 `edges` with no additions:
    ///
    ///   WAKING  → SHELF, or any refusal
    ///   SHELF   → WATCHING (new capture) | TUNING (re-open a stored one)
    ///   WATCHING ⟲ (the live read, EM2) → WEAVING
    ///   WEAVING → SOLVING          (the arc admits no skips, EM3)
    ///   SOLVING → TUNING           (★ the solve lands in the editor)
    ///   TUNING  ⟲ (the tick, EM2) → SEALED | SHELF | WATCHING
    ///   SEALED  → TUNING (★ fork freedom, EM10) | SHELF
    ///   soft refusals recover; the three hardware refusals do not (EM7)
    static func successors(of state: State) -> [State] {
        switch state {
        case .waking:
            return [.shelving,
                    .refused(.cameraOff), .refused(.noTrueDepth),
                    .refused(.noCenterStage), .refused(.noFaceTracking),
                    .refused(.exportFailed), .refused(.unknown(""))]
        case .shelving:
            return [.watching, .tuning]
        case .watching:
            return [.watching, .weaving]
        case .weaving:
            return [.solving]
        case .solving:
            return [.tuning]
        case .tuning:
            return [.tuning, .sealed, .shelving, .watching]
        case .sealed:
            return [.tuning, .shelving]
        case .refused(.cameraOff):
            return [.waking]
        case .refused(.exportFailed):
            return [.tuning]
        case .refused(.unknown):
            return [.shelving]
        // EM7 ★ — the three hardware refusals are TERMINAL. No retry
        // edge exists, because no retry can change the hardware.
        case .refused(.noTrueDepth), .refused(.noCenterStage),
             .refused(.noFaceTracking):
            return []
        }
    }

    static func canStep(from: State, to: State) -> Bool {
        successors(of: from).contains(erased(to))
    }

    /// The 13 states, in the spec's `allStates` order.
    static let allStates: [State] = [
        .waking, .shelving, .watching, .weaving, .solving, .tuning, .sealed,
        .refused(.cameraOff), .refused(.noTrueDepth), .refused(.noCenterStage),
        .refused(.noFaceTracking), .refused(.exportFailed), .refused(.unknown("")),
    ]

    /// EM7 — terminal, no retry (SM4 preserved).
    static let hardwareRefusals: [State] = [
        .refused(.noTrueDepth), .refused(.noCenterStage), .refused(.noFaceTracking),
    ]

    /// The two continuous processes (EM2). Every other state changes
    /// by LEAVING; these two change by STAYING.
    static let loops: [State] = [.watching, .tuning]

    /// Breadth-first closure over `successors` — the reachability the
    /// EM1 / EM9 / EM10 tests quantify over.
    static func reachable(from start: State) -> [State] {
        var seen: [State] = [erased(start)]
        var queue: [State] = [erased(start)]
        while let x = queue.first {
            queue.removeFirst()
            for y in successors(of: x) where !seen.contains(erased(y)) {
                seen.append(erased(y))
                queue.append(erased(y))
            }
        }
        return seen
    }
}
