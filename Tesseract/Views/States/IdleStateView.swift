// IdleStateView.swift
// Tesseract
//
// CameraState.idle — camera is configuring on the session queue.
// This screen should only be visible for the first few hundred ms.
// Every widget occupies a proven GridRegion (GridLayout.idleScene).

import SwiftUI

struct IdleStateView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            CellText("TESSERACT", rows: TypeRows.display)
                .place(GridLayout.idleTitle)
            CellText("4⁴ = 256", rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
                .place(GridLayout.idleSub)
            CellBusyTile(sideCells: GridLayout.idleBusy.w)
                .place(GridLayout.idleBusy)
            CellText("initializing camera...", rows: TypeRows.label,
                     ink: Color(srgb8: Ink.ledGhost))
                .place(GridLayout.idleHint)
        }
    }
}
