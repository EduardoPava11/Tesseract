// Lattice.swift
// Tesseract
//
// The SOLE OWNER of cell↔point math. Every view expresses sizes as
// Lattice.gif(n) (atoms — content and widget sizes) or Lattice.pt(n)
// (half-atoms — fine spacing, gutters). Raw numeric literals in
// .frame/.padding/spacing are banned by scripts/lint-grid.sh.
//
// Re-basing the atom re-lays the entire app with zero call-site edits.

import SwiftUI

enum Lattice {

    /// The atom in points (4 pt = 1 displayed GIF pixel).
    static let gifPx = CGFloat(TesseractLattice.gifPx)

    /// The half-atom in points (2 pt).
    static let cellPt = CGFloat(TesseractLattice.subPt)

    /// Exact grid extent — the scene canvas.
    static let gridWidthPt = CGFloat(TesseractLattice.cols * TesseractLattice.gifPx)
    static let gridHeightPt = CGFloat(TesseractLattice.rows * TesseractLattice.gifPx)

    /// Atoms → points. Content and widget sizes.
    static func gif(_ cells: Int) -> CGFloat {
        CGFloat(cells) * gifPx
    }

    /// Half-atoms → points. Spacing, gutters, text nudges.
    static func pt(_ subcells: Int) -> CGFloat {
        CGFloat(subcells) * cellPt
    }
}
