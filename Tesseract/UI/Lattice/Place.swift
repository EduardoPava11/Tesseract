// Place.swift
// Tesseract
//
// The ONE placement primitive. A view claims a GridRegion; the frame
// and position derive from the atom. The two .position calls below are
// the only sanctioned ones in the app (see scripts/lint-grid.sh).

import SwiftUI

extension View {

    /// Place this view in its proven rectangular claim.
    func place(_ region: GridRegion) -> some View {
        self
            .frame(width: Lattice.gif(region.w), height: Lattice.gif(region.h))
            .position( // LINT-ALLOW-POSITION
                x: Lattice.gif(region.col) + Lattice.gif(region.w) / 2,
                y: Lattice.gif(region.row) + Lattice.gif(region.h) / 2
            )
    }

    /// Center the exact 400×872 grid canvas in the live screen; the
    /// sub-atom bleed splits symmetrically, so cell coordinates stay
    /// device-independent.
    func gridCentered(in size: CGSize) -> some View {
        self
            .frame(width: Lattice.gridWidthPt, height: Lattice.gridHeightPt)
            .position(x: size.width / 2, y: size.height / 2) // LINT-ALLOW-POSITION
    }
}
