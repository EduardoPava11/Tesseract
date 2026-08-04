// BirkhoffGauge.swift
// Tesseract
//
// The Birkhoff beauty gauge (M = O / C) — shared by the LIVE and FACE
// preview scenes. Lit-cells meter + metric pairs, opaque ink only.

import SwiftUI

struct BirkhoffGauge: View {
    let measure: BirkhoffMeasure?

    var body: some View {
        VStack(spacing: Lattice.pt(2)) {
            if let m = measure {
                HStack(spacing: Lattice.gif(2)) {
                    CellText("M", rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
                    meter(normalized: min(1, Double(m.beauty) / 600))
                    CellText(String(format: "%.0f", m.beauty), rows: TypeRows.label)
                }
                HStack(spacing: Lattice.gif(4)) {
                    pair("O", String(format: "%.0f", m.order))
                    pair("C", String(format: "%.2f", m.complexity))
                    pair("dim", String(format: "%.1f", m.manifoldDim))
                    pair("col", "\(m.colorsUsed)")
                }
            } else {
                CellText("M = O / C", rows: TypeRows.label,
                         ink: Color(srgb8: Ink.ledGhost))
            }
        }
    }

    // 30-atom lit-cells meter — the alpha gradient bar, now opaque ink.
    private func meter(normalized: Double) -> some View {
        let lit = max(0, min(30, Int((normalized * 30).rounded())))
        return CellSprite(cols: 30, rows: 1, cellPt: Lattice.gifPx) { c, _ in
            c < lit ? Ink.ink : Ink.ledGhost
        }
        .accessibilityHidden(true)
    }

    private func pair(_ label: String, _ value: String) -> some View {
        VStack(spacing: Lattice.pt(1)) {
            CellText(value, rows: TypeRows.label)
            CellText(label, rows: TypeRows.micro, ink: Color(srgb8: Ink.ledGhost))
        }
    }
}
