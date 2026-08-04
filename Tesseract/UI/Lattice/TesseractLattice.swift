// TesseractLattice.swift
// Tesseract
//
// THE CONSTITUTION — the single geometric contract for the UI.
// Ported from SixFour's lattice discipline (2026-08-03).
//
// The atom IS the GIF pixel: the app displays its 64×64 output at 4×,
// so one displayed GIF pixel = 4 pt = 12 device px @3x. Every size,
// gutter, and offset in the UI is an integer number of atoms (or
// half-atoms for fine spacing). Widgets grow by MORE atoms, never a
// bigger atom.
//
// Laws (asserted by selfCheck, called at app start in DEBUG):
//   L1  atom = 4 pt = CameraConfig.displayScale (the GIF pixel)
//   L2  half-atom 2 pt is commensurate (2 × subPt = gifPx)
//   L3  the 100×218 grid tiles the 402×874 reference screen with a
//       symmetric ≤1-atom bleed per axis (400×872 grid + 2pt + 2pt)
//   L4  the HIG touch floor is an exact atom multiple: 44 = 11 × 4
//   L5  the preview widget is exactly the GIF: 64 cells = 256 pt =
//       CameraConfig.displaySize
//
// This file owns NUMBERS ONLY. Cell↔point math lives in Lattice.swift
// (the sole owner); rectangular claims live in GridLayout.swift.

import Foundation

enum TesseractLattice {

    // ── The atom ──
    static let gifPx: Int = 4        // pt per atom (= 1 displayed GIF pixel)
    static let subPt: Int = 2        // half-atom, for fine spacing/gutters

    // ── The grid (iPhone 17 Pro reference: 402 × 874 pt) ──
    static let cols: Int = 100       // 400 pt
    static let rows: Int = 218       // 872 pt
    static let hBleedPt: Int = 2     // 402 − 400, split symmetrically
    static let vBleedPt: Int = 2     // 874 − 872, split symmetrically

    // ── Widget footprints, in atoms ──
    static let touchFloorCells: Int = 11   // 44 pt — HIG minimum hit target
    static let previewCells: Int = 64      // the GIF itself: 64 atoms = 256 pt
    static let channelCells: Int = 12      // 48 pt R/G/B/D thumbs
    static let recordCells: Int = 18       // 72 pt shutter footprint
    static let recordDiscCells: Int = 14   // 56 pt shutter inner disc
    static let paletteCells: Int = 16      // 64 pt palette swatch (16×16 grid)
    static let barCells: Int = 11          // 44 pt mode bar (a touch target)

    // ── Self-check: every law, re-asserted at runtime ──

    static func selfCheck() {
        // L1: atom = displayed GIF pixel
        precondition(gifPx == CameraConfig.displayScale,
                     "L1: atom must equal the GIF display scale")
        // L2: half-atom commensurate
        precondition(2 * subPt == gifPx, "L2: subPt must be half the atom")
        // L3: grid + bleed tiles the reference screen
        precondition(cols * gifPx == 400 && rows * gifPx == 872,
                     "L3: grid extent must be 400×872 pt")
        precondition(cols * gifPx + hBleedPt == 402
                  && rows * gifPx + vBleedPt == 874,
                     "L3: grid + bleed must tile 402×874")
        precondition(hBleedPt < gifPx && vBleedPt < gifPx,
                     "L3: bleed must be sub-atom")
        // L4: touch floor is an exact atom multiple
        precondition(44 % gifPx == 0 && touchFloorCells * gifPx == 44,
                     "L4: 44pt touch floor must be an atom multiple")
        // L5: the preview IS the GIF
        precondition(previewCells * gifPx == CameraConfig.displaySize,
                     "L5: preview widget must equal the displayed GIF size")
        precondition(previewCells == CameraConfig.outputSize,
                     "L5: preview cells must equal GIF pixels (64)")
        // Widget sanity
        precondition(recordDiscCells < recordCells,
                     "shutter disc must fit its footprint")
        precondition(barCells >= touchFloorCells,
                     "mode bar hosts buttons — must meet the touch floor")
    }
}
