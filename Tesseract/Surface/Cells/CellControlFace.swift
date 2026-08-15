import SwiftUI
import UIKit
import simd

/// The control language's two faces (ported from SixFour; `ControlFrame`
/// is the frame-face component SixFour re-baked inline at three sites —
/// extracted here as the missing twin of `ControlBrackets`).
///
/// States are the closed `CellMechanics` algebra — OPAQUE ink transforms,
/// never alpha:
///   idle    → ghost, going LIT for exactly 1 tick in 4 (the BEAT; under
///             reduce-motion the caller passes `reduceMotion: true` and
///             the beat is pinned off — treatments evaluate at tick 1,
///             provably beat-free: `goldenBeat[1] == false`);
///   pressed → full control-ink inversion;
///   busy    → the reject red;
///   disabled→ the 2×2 checker over the face cells only.
///
/// PERF: the bitmap is baked ONCE per treatment change (1 rebake per 4
/// ticks at worst, and only while idle) — never per publish.

/// Shared treatment → per-cell ink for face geometry. `nil` off-face.
private func faceInk(treatment: Int, c: Int, r: Int) -> SIMD3<UInt8> {
    switch treatment {
    case 0: return Ink.ledGhost          // ghost (idle between beats)
    case 1: return Ink.ink               // lit (the BEAT tick)
    case 2: return Ink.ink               // inverted (pressed — tile inverts too)
    case 3: return Ink.reject            // busy
    default:                             // checker (disabled)
        return CellChecker.ink(c, r, lit: Ink.ink, ghost: Ink.ledGhost)
    }
}

/// **BRACKETS** — the face for controls whose content IS an image
/// (today: the library's GIF tiles). Never obscures a
/// content pixel: four corner brackets in the GUTTER OUTSIDE the tile,
/// arms `armCells` × 1 cell thick, footprint `side + 2·(gutter+1)`.
/// The bracket rect IS the hit rect (caller adds `.contentShape(Rectangle())`).
struct ControlBrackets: View {
    /// The content tile's side in cells.
    let side: Int
    /// Ordinal into `CellMechanics.controlStates` (0 idle · 1 pressed ·
    /// 2 busy · 3 disabled).
    let state: Int
    /// The ONE 20 Hz clock — drives the idle BEAT only.
    let tick: Int
    var reduceMotion: Bool = false
    /// Gutter cells between the tile edge and the bracket.
    var gutterCells: Int = 1
    /// Bracket arm length in cells (the D1 spec: 3).
    var armCells: Int = 3

    /// The baked face, keyed by treatment so identical states never rebake.
    @State private var baked: (treatment: Int, image: UIImage?) = (-1, nil)

    /// Total footprint per edge: tile + gutter + 1-cell bracket, both flanks.
    var footprint: Int { side + 2 * (gutterCells + 1) }

    var body: some View {
        let treatment = CellMechanics.faceTreatment(state: state,
                                                    tick: reduceMotion ? 1 : tick)
        Group {
            if let img = baked.image {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            }
        }
        // Footprint reserved even while the bake is pending — no reflow.
        .frame(width: Lattice.gif(footprint), height: Lattice.gif(footprint))
        .onChange(of: treatment, initial: true) { _, t in
            guard t != baked.treatment else { return }
            baked = (t, Self.bake(footprint: footprint, armCells: armCells, treatment: t))
        }
        .accessibilityHidden(true)
    }

    private static func bake(footprint n: Int, armCells: Int, treatment: Int) -> UIImage? {
        CellBitmap.image(cols: n, rows: n) { c, r in
            guard onBracket(c, r, n: n, arm: armCells) else { return nil }
            return faceInk(treatment: treatment, c: c, r: r)
        }
    }

    /// True iff (c,r) lies on one of the four corner brackets: the
    /// outermost ring, within `arm` cells of a corner along either axis.
    private static func onBracket(_ c: Int, _ r: Int, n: Int, arm: Int) -> Bool {
        let onEdgeCol = c == 0 || c == n - 1
        let onEdgeRow = r == 0 || r == n - 1
        guard onEdgeCol || onEdgeRow else { return false }
        let nearCornerC = c < arm || c >= n - arm
        let nearCornerR = r < arm || r >= n - arm
        return (onEdgeRow && nearCornerC) || (onEdgeCol && nearCornerR)
    }
}

/// **FRAME** — the face for solid controls (mode pills, action buttons,
/// scrubber): a 1-cell inset ring in the treatment ink, baked once per
/// treatment change. Same algebra, same bake discipline as brackets.
struct ControlFrame: View {
    let cols: Int
    let rows: Int
    /// Ordinal into `CellMechanics.controlStates`.
    let state: Int
    let tick: Int
    var reduceMotion: Bool = false

    @State private var baked: (treatment: Int, image: UIImage?) = (-1, nil)

    var body: some View {
        let treatment = CellMechanics.faceTreatment(state: state,
                                                    tick: reduceMotion ? 1 : tick)
        Group {
            if let img = baked.image {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
            }
        }
        .frame(width: Lattice.gif(cols), height: Lattice.gif(rows))
        .onChange(of: treatment, initial: true) { _, t in
            guard t != baked.treatment else { return }
            baked = (t, Self.bake(cols: cols, rows: rows, treatment: t))
        }
        .accessibilityHidden(true)
    }

    private static func bake(cols: Int, rows: Int, treatment: Int) -> UIImage? {
        CellBitmap.image(cols: cols, rows: rows) { c, r in
            let onRing = c == 0 || c == cols - 1 || r == 0 || r == rows - 1
            guard onRing else { return nil }
            return faceInk(treatment: treatment, c: c, r: r)
        }
    }
}
