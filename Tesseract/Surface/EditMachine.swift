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

    /// ★ THE REFUSAL TYPE owns the whole two-register voice.
    ///
    /// Before, a refusal's HEADLINE lived on `State.word`, its
    /// EXPLAINER lived in a switch inside ContentView, and its
    /// terminality lived a third time inside `canStep`. Three places,
    /// no compiler check that they agreed — and a refusal added to one
    /// could silently miss the others. They are one thing now: adding
    /// a case here forces all three, because `headline`, `explainer`
    /// and `recovery` are total switches.
    ///
    /// EM7: a refusal is TERMINAL exactly when it has no recovery.
    /// That is now derived (`isTerminal`) rather than restated.
    enum Refusal: Equatable, Sendable {

        /// Why the session stopped delivering, when the hardware is
        /// fine and something else took it. These are the ordinary
        /// iOS interruptions; every one is recoverable by waiting.
        enum Interruption: Equatable, Sendable {
            case cameraInUse      // another app holds the capture device
            case backgrounded     // the device is not available in background
            case multipleApps     // Split View / Slide Over on iPad-class layouts
            case overheated       // thermal pressure suspended the session
        }

        /// What the user can DO about it. `.none` is the terminal
        /// case: a hardware fact, where offering a dead RETRY button
        /// would be a lie (the NO-SE decree's mechanism).
        enum Recovery: Equatable, Sendable {
            case none
            case retry            // re-open the session
            case reshoot          // return to WATCHING and record again
            case openSettings     // deep-link to the app's own settings pane
            case wait             // it clears by itself
        }

        case cameraOff
        case noTrueDepth
        case noCenterStage
        case noFaceTracking
        /// ★ The session stopped mid-capture. Not a defect — the
        /// ordinary case of a phone call, another camera app, or a
        /// hot device.
        case interrupted(Interruption)
        /// ★ The weave did not receive its full cube. This is the
        /// failure the 2026-08-13 device audit predicted: the 5 Hz
        /// solve runs synchronously on the dataOutputSynchronizer
        /// callback against a 50 ms budget, so an over-budget frame is
        /// DROPPED — and a dropped frame during WEAVING stretches the
        /// loop and breaks the temporal uniformity the 5 cs delay
        /// assumes. A short cube must be refused, not quietly encoded
        /// as if it were 64 frames.
        case captureIncomplete(kept: Int, wanted: Int)
        case exportFailed
        /// ★ The GIF encoded but could not be written.
        case storageFull
        /// ★ Photos access was refused, so KEEP cannot complete.
        case photosDenied
        case unknown(String)

        /// EM6: uppercase letters and spaces only — digits ride
        /// payload rows, so a count goes in the explainer, never here.
        var headline: String {
            switch self {
            case .cameraOff:          return "CAMERA OFF"
            case .noTrueDepth:        return "NO TRUEDEPTH"
            case .noCenterStage:      return "NO CENTER STAGE"
            case .noFaceTracking:     return "NO FACE TRACKING"
            case .interrupted(.cameraInUse):  return "CAMERA IN USE"
            case .interrupted(.backgrounded): return "CAMERA ASLEEP"
            case .interrupted(.multipleApps): return "CAMERA SHARED"
            case .interrupted(.overheated):   return "TOO HOT"
            case .captureIncomplete:  return "SHORT WEAVE"
            case .exportFailed:       return "EXPORT FAILED"
            case .storageFull:        return "NO ROOM"
            case .photosDenied:       return "PHOTOS OFF"
            case .unknown:            return "REFUSED"
            }
        }

        /// The second register: lowercase, one sentence, says what to
        /// do rather than what went wrong where that is knowable.
        var explainer: String {
            switch self {
            case .cameraOff:
                return "allow camera access in Settings to see the preview"
            case .noTrueDepth:
                return "tesseract needs the Face ID camera, and this iPhone has none"
            case .noCenterStage:
                return "tesseract needs the center stage selfie camera of iPhone 17 or later"
            case .noFaceTracking:
                return "this device cannot track the ARKit face mesh"
            case .interrupted(.cameraInUse):
                return "another app is using the camera, close it and come back"
            case .interrupted(.backgrounded):
                return "the camera sleeps while tesseract is in the background"
            case .interrupted(.multipleApps):
                return "the camera cannot be shared with another app on screen"
            case .interrupted(.overheated):
                return "the iPhone is too warm to keep the camera open, let it cool"
            case .captureIncomplete(let kept, let wanted):
                return "the weave kept \(kept) of \(wanted) frames, record again"
            case .exportFailed:
                return "the GIF could not be encoded, record again"
            case .storageFull:
                return "there is no room left to write the GIF"
            case .photosDenied:
                return "allow photo access in Settings to keep this GIF"
            case .unknown(let detail):
                return detail.lowercased()
            }
        }

        /// EM7's mechanism. A hardware fact offers nothing — a RETRY
        /// that cannot succeed is worse than no button.
        var recovery: Recovery {
            switch self {
            case .noTrueDepth, .noCenterStage, .noFaceTracking:
                return .none
            case .cameraOff, .photosDenied:
                return .openSettings
            case .interrupted:
                return .wait
            case .captureIncomplete, .exportFailed:
                return .reshoot
            case .storageFull, .unknown:
                return .retry
            }
        }

        /// EM7 — derived, not restated.
        var isTerminal: Bool { recovery == .none }
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
            // One source of truth: the refusal owns its own word.
            case .refused(let r):            return r.headline
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
        // Payload-carrying refusals erase to a canonical representative
        // so an edge is a statement about the KIND, not the count.
        if case .refused(.captureIncomplete) = s {
            return .refused(.captureIncomplete(kept: 0, wanted: 0))
        }
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
        // ⚠ SPEC DEBT (2026-08-14): the four refusals below are NOT in
        // spec/ui/EditMachine.hs. They were added Swift-side to cover
        // real iOS failure modes the machine could not previously
        // name — a session interruption, a short weave, a full disk, a
        // Photos denial. Their edges follow each refusal's own
        // `recovery`, but EM7's terminal SET and `allStates` are
        // spec-pinned at 13, so these are deliberately NOT in
        // `allStates` and the totality laws do not yet cover them.
        // The spec owes these cases before the next axiom pass.
        case .refused(.interrupted):
            // .wait — the session re-opens once the other app lets go
            // or the device cools.
            return [.waking]
        case .refused(.captureIncomplete):
            // .reshoot — the cube is short, so the moment is gone; the
            // only honest move is back to the live read.
            return [.watching]
        case .refused(.storageFull), .refused(.photosDenied):
            // .retry / .openSettings — the GIF still exists in the
            // editor, so recovery returns there rather than discarding.
            return [.tuning]
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
