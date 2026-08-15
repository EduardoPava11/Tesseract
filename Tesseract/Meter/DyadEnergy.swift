// DyadEnergy.swift
// Tesseract
//
// The two energy analyses (spec/statistics/PhaseEnergy.hs is
// authoritative — PE1..PE12):
//
//   E_pal   Σ chroma² over the 256 table entries (OKLab). σ-symmetric
//           pre-clamp; also derivable in closed form from the
//           9-number state (PE1), so the STATS trace already carries
//           it — the traced value is a cross-check.
//   E_dist  the configuration Hamiltonian of an index frame: domain
//           walls over the open 64² lattice (exactly the Ising
//           energy, PE4; the 4×4 toroidal restriction is
//           PairPermutations' 32 − adjacency, PE5) plus normalized
//           occupancy entropy.
//   Order   φ (σ-side fraction), m_st (staggered — the Néel detector
//           for the Bayer band), s. The triple separates
//           SOLID / BAND / FACE (PE11).
//
// Pure; computable from an index frame and a table alone. No capture
// dependencies. (The phase-diagram sweep tool was retired in the
// 2026-08-11 unification; git history has nn/phase/sweep.py.)

import Foundation

enum DyadEnergy {

    // MARK: - E_pal (palette energy over the 256)

    /// Σ chroma² over the table, OKLab. Post-clamp (the shipped
    /// bytes); the pre-clamp closed form is `palette(stats:)`.
    static func palette(table: [(UInt8, UInt8, UInt8)]) -> Double {
        table.reduce(0) { acc, rgb in
            let lab = DyadPalette.oklab(fromSRGB8: rgb)
            return acc + lab.a * lab.a + lab.b * lab.b
        }
    }

    /// The closed 9-number form (PE1): per-shell trigonometric sums
    /// evaluated analytically. Pre-clamp; palette(table:) ≤ this,
    /// with the deficit = gamut clamp loss.
    static func palette(stats: DyadPalette.Stats) -> Double {
        let c = stats.centroid
        let d1 = stats.pcs[0].direction
        let d2 = stats.pcs[1].direction
        let g1 = DyadPalette.guardedStd(stats.pcs[0].variance)
        let g2 = DyadPalette.guardedStd(stats.pcs[1].variance)
        let cmu = c.a * c.a + c.b * c.b
        let p1 = d1.1 * d1.1 + d1.2 * d1.2
        let p2 = d2.1 * d2.1 + d2.2 * d2.2
        let crossMu1 = c.a * d1.1 + c.b * d1.2
        var half = 0.0
        for (k, n) in DyadPalette.ladder.enumerated() {
            let r = DyadPalette.rho(k)
            if n == 1 && k == 0 {
                half += cmu
            } else if n == 1 {
                half += cmu + 2 * r * g1 * crossMu1 + r * r * g1 * g1 * p1
            } else if n == 2 {
                half += 2 * cmu + 2 * r * r * g1 * g1 * p1
            } else {
                half += Double(n) * cmu + Double(n) * r * r / 2 * (g1 * g1 * p1 + g2 * g2 * p2)
            }
        }
        return 2 * half
    }

    // MARK: - E_dist (the 256 distributed onto the 64×64)

    struct FrameEnergy: Sendable {
        let walls: Int        // domain walls, open-lattice bonds (≤ 8064)
        let w: Double         // walls / bonds ∈ [0,1]
        let sOcc: Double      // occupancy entropy, normalized ∈ [0,1]
        let phi: Double       // σ-side fraction (order parameter)
        let mStag: Double     // staggered magnetization (Néel detector)
        var eDist: Double { w + sOcc }
    }

    static func frame(indices: [UInt8]) -> FrameEnergy {
        let side = Int(Double(indices.count).squareRoot())
        let bonds = 2 * side * (side - 1)
        var walls = 0
        var sigma = 0
        var staggered = 0
        var counts = [Int](repeating: 0, count: 256)
        for p in 0..<indices.count {
            let x = p % side, y = p / side
            let s = indices[p] >= 128
            counts[Int(indices[p])] += 1
            if s { sigma += 1 }
            staggered += ((x + y) % 2 == 0) == s ? 1 : -1
            if x + 1 < side && s != (indices[p + 1] >= 128) { walls += 1 }
            if y + 1 < side && s != (indices[p + side] >= 128) { walls += 1 }
        }
        let n = Double(indices.count)
        var entropy = 0.0
        for c in counts where c > 0 {
            let p = Double(c) / n
            entropy -= p * log(p)
        }
        return FrameEnergy(
            walls: walls,
            w: Double(walls) / Double(max(1, bonds)),
            sOcc: entropy / log(256),
            phi: Double(sigma) / n,
            mStag: abs(Double(staggered)) / n)
    }

    // MARK: - Trace (DYAD ENERGY v1)

    /// One line per frame: epal edist phi mstag walls socc —
    /// shortest exact round-trip doubles, walls as integer (PE13's
    /// format law lives in the tests).
    static func trace(tables: [Data], indexFrames: [[UInt8]]) -> String {
        var lines = ["DYAD ENERGY v1 frames=\(indexFrames.count)"]
        for (f, indices) in indexFrames.enumerated() {
            let entries = (0..<256).map { i -> (UInt8, UInt8, UInt8) in
                let t = tables[f]
                return (t[t.startIndex + 3 * i], t[t.startIndex + 3 * i + 1],
                        t[t.startIndex + 3 * i + 2])
            }
            let ep = palette(table: entries)
            let fe = frame(indices: indices)
            lines.append("\(ep) \(fe.eDist) \(fe.phi) \(fe.mStag) \(fe.walls) \(fe.sOcc)")
        }
        return lines.joined(separator: "\n")
    }
}
