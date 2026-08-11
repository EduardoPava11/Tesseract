import SwiftUI
import simd

/// A 256-entry GIF color table rendered as a 16×16 cell swatch — the
/// palette made visible (Daniel, 2026-08-10: "I want to see the color
/// palette creation as we create the GIF"). Row-major by palette index,
/// so the DYAD structure reads directly: primaries fill the top half
/// (binomial shells outward from the centroid at index 0), Wada grounds
/// mirror them in the bottom half — T[255−i] = ground(T[i]): hue+180°,
/// dictionary-muted chroma, ensemble-shifted lightness (v5-W).
struct CellPalette: View {
    /// 768 bytes: 256 × RGB. Short/absent data renders the checker.
    let table: Data?
    /// Cells per palette entry (2 = a 32×32-cell swatch = 128 pt).
    var entryCells: Int = 2

    var body: some View {
        let side = 16 * entryCells
        CellSprite(cols: side, rows: side, cellPt: Lattice.gifPx) { c, r in
            guard let table, table.count >= 768 else { return CellChecker.dark }
            let idx = (r / entryCells) * 16 + (c / entryCells)
            let o = table.startIndex + idx * 3
            return SIMD3(table[o], table[o + 1], table[o + 2])
        }
        .accessibilityLabel("Color palette, 256 entries")
    }
}
