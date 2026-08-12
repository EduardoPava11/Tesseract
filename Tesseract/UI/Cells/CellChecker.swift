import SwiftUI
import simd

/// The 2×2 checker parity math (ported from SixFour's GridChecker) — the
/// opaque busy/heartbeat texture. `phase` (the SurfaceClock heartbeat
/// bit) flips which parity is "on", giving a 20 Hz shimmer with zero
/// alpha; a fixed phase gives the static disabled/busy checker.
enum CellChecker {
    /// The checker's off-parity ink — an alias of Ink.void (the one
    /// owner of the 16,16,16 byte value; UI/UX line pass 2026-08-12).
    static let dark = Ink.void

    /// Parity of the 2×2 block containing cell (c,r), flipped by `phase`.
    @inline(__always) static func on(_ c: Int, _ r: Int, phase: Int = 0) -> Bool {
        (((c / 2) + (r / 2)) & 1) == (phase & 1)
    }

    /// The standard checker ink: `lit` on on-cells, `ghost` off-cells.
    @inline(__always) static func ink(_ c: Int, _ r: Int, phase: Int = 0,
                                      lit: SIMD3<UInt8>, ghost: SIMD3<UInt8>) -> SIMD3<UInt8> {
        on(c, r, phase: phase) ? lit : ghost
    }
}

/// A square busy tile: the checker at the heartbeat phase — the opaque
/// replacement for `ProgressView` spinners.
struct CellBusyTile: View {
    /// Side in atoms (4pt cells).
    let sideCells: Int
    /// Pass `clock.heartbeat` for the live shimmer; 0 for static.
    var phase: Int = 0
    var lit: SIMD3<UInt8> = Ink.ledGhost
    var ghost: SIMD3<UInt8> = CellChecker.dark

    var body: some View {
        CellSprite(cols: sideCells, rows: sideCells, cellPt: Lattice.gifPx) { c, r in
            CellChecker.ink(c, r, phase: phase, lit: lit, ghost: ghost)
        }
        .accessibilityHidden(true)
    }
}
