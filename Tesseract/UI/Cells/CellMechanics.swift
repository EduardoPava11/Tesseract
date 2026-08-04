import Foundation
import simd

/// The closed control-face algebra (hand-checked twin of
/// `spec/ui/CellMechanics.hs`; golden-pinned by `CellMechanicsParityTests`).
/// Ported from SixFour's CellMechanicsContract.
///
/// Every interactive region wears a FACE (frame ring or corner brackets)
/// whose treatment is an OPAQUE ink transform — never alpha:
///   idle     → ghost, going LIT for exactly 1 tick in 4 (the BEAT);
///   pressed  → full ink inversion;
///   busy     → reject red;
///   disabled → the 2×2 checker.
/// Only idle reads the tick; all other states are tick-invariant.
enum CellMechanics {
    /// Control state ordinals.
    static let controlStates = ["idle", "pressed", "busy", "disabled"]
    /// Face treatment ordinals (opaque ink transforms).
    static let faceTreatments = ["ghost", "lit", "inverted", "busy", "checker"]
    /// Face geometries: "frame" = 1-cell inset ring (solid controls);
    /// "brackets" = corner brackets in the gutter (image-content controls).
    static let faceKinds = ["frame", "brackets"]

    /// The BEAT period: lit 1 tick in 4 (5 Hz at the 20 Hz clock).
    static let beatPeriodTicks = 4

    /// treatment = table[state × 2 + (beat ? 1 : 0)].
    /// Row layout: idle→(ghost|lit), pressed→(inverted|inverted),
    /// busy→(busy|busy), disabled→(checker|checker).
    static let faceTreatmentTable = [0, 1, 2, 2, 3, 3, 4, 4]

    /// The 16-tick golden beat pin: true exactly when tick ≡ 0 (mod 4).
    /// `goldenBeat[1] == false` is the reduce-motion anchor — evaluating
    /// any treatment at tick 1 is provably beat-free.
    static let goldenBeat: [Bool] = (0..<16).map { $0 % 4 == 0 }

    /// Face inks (re-exported from `Ink` so the algebra is self-contained).
    static let faceControlInk = Ink.ink
    static let rejectInk = Ink.reject
    static let acceptInk = Ink.accept

    /// The face treatment for a control state at a clock tick.
    /// ONLY idle (state 0) reads the tick.
    static func faceTreatment(state: Int, tick: Int) -> Int {
        let s = max(0, min(controlStates.count - 1, state))
        let beat = s == 0 && tick % beatPeriodTicks == 0
        return faceTreatmentTable[s * 2 + (beat ? 1 : 0)]
    }

    /// The closed region-name → face-kind table. Every `interactive: true`
    /// region in `GridLayout` MUST appear here (LINT-CONTROL-FACE mirrors
    /// this; populated with the scene data in the layout-as-data phase).
    static let controlFaces: [String: String] = [:]

    /// DEBUG init-time law check (run alongside the lattice selfChecks).
    static func selfCheck() {
        assert(faceTreatmentTable.count == controlStates.count * 2, "M1 table shape")
        assert(faceTreatmentTable.allSatisfy { $0 >= 0 && $0 < faceTreatments.count },
               "M2 treatments total")
        for s in 1..<controlStates.count {
            assert(faceTreatmentTable[s * 2] == faceTreatmentTable[s * 2 + 1],
                   "M3 only idle reads the tick")
        }
        assert(goldenBeat[1] == false, "M4 tick 1 is beat-free (reduce-motion anchor)")
        for (t, b) in goldenBeat.enumerated() {
            assert(b == (t % beatPeriodTicks == 0), "M5 beat period")
        }
        assert(controlFaces.values.allSatisfy { faceKinds.contains($0) },
               "M6 faces are frame|brackets")
    }
}
