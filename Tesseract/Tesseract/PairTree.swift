// PairTree.swift
// Tesseract
//
// THE PAIR TREE (Daniel's ruling, 2026-08-12): the 256-entry table
// as pairings of pairings — a dyadic tree whose bit-triples are the
// 2×2×2 = 8:1 atom, grounded in latent axes. Port of
// spec/quantization/PairTree.hs §3b (PT7–PT9 — the Haskell spec is
// authoritative); design docs/pair-tree-palette.md.
//
// THE ANALYTIC TREE: the provenance law (DYAD STATS — 13 numbers
// regenerate every palette byte) demands the tree be a CLOSED-FORM
// function of (centroid, covariance). So the splits act on the
// FITTED GAUSSIAN, not the samples: splitting N(μ, Σ) at its mean
// along eigenaxis u (eigenvalue λ) gives two half-Gaussians with
// exact moments —
//
//   child mean      μ ± √λ·√(2/π)·u        (half-normal mean)
//   child variance  λ·(1 − 2/π) on u; other axes UNCHANGED
//
// The eigenbasis never rotates (independence in the eigenbasis), so
// the whole 7-generation tree is exact arithmetic. √(2/π) and
// (1 − 2/π) are moments of the Gaussian — not tuned constants.
// Split axis = argmax variance, ties → lowest (deterministic; the
// canonical PCA signs of DY8 make the leaf order stable frame to
// frame). Larger λ gets split more often: RL4's n ∝ √λ allocation,
// node by node.
//
// Leaf order: generation choices are the index bits, FIRST
// generation = MSB (bit 6) — low bits are the finest pairings, so
// prefix truncation pools depth-first subtrees (PT5, the rung
// alignment). σ half: T[255−i] = ground(gm, T[i]), unchanged — the
// complement preserves every pairing level (PT6).

import Foundation

enum PairTree {

    /// E[|Z|] for Z ~ N(0,1) — the half-normal mean coefficient.
    static let halfMeanC = (2.0 / Double.pi).squareRoot()
    /// Var[|Z|] — the half-normal variance coefficient.
    static let halfVarC = 1.0 - 2.0 / Double.pi

    /// The solved figure half plus the 32-level (depth-4) nodes the
    /// prefix law quantizes against (P2: chaos-blur targets).
    struct Figures: Sendable {
        /// 128 clamped figure bytes in leaf (bit) order.
        let figures8: [(UInt8, UInt8, UInt8)]
        /// OKLab of the clamped figure bytes — the assignment prims.
        let figures: [OKLabColor]
        /// Analytic depth-4 node means (16, one per leaf octet).
        let nodes16: [OKLabColor]
        /// Representative figure leaf per node: the octet member
        /// nearest its node's mean (deterministic, lowest index on
        /// ties). Node c covers leaves 8c ..< 8c+8.
        let canonical16: [Int]
    }

    /// Build the figure half from the fitted statistics — closed
    /// form, deterministic, constant-free (PT7–PT9).
    static func solveFigures(stats: DyadPalette.Stats) -> Figures {
        let dirs = stats.pcs.map { $0.direction }
        var leaves: [OKLabColor] = []
        leaves.reserveCapacity(128)
        var nodes16: [OKLabColor] = []
        nodes16.reserveCapacity(16)

        func descend(_ mean: OKLabColor, _ vars: [Double], _ remaining: Int) {
            if remaining == 3 { nodes16.append(mean) }
            if remaining == 0 { leaves.append(mean); return }
            var a = 0
            for i in 1..<3 where vars[i] > vars[a] { a = i }
            let v = vars[a]
            let off = v.squareRoot() * halfMeanC
            let d = dirs[a]
            var childVars = vars
            childVars[a] = v * halfVarC
            descend(OKLabColor(l: mean.l - off * d.0,
                               a: mean.a - off * d.1,
                               b: mean.b - off * d.2), childVars, remaining - 1)
            descend(OKLabColor(l: mean.l + off * d.0,
                               a: mean.a + off * d.1,
                               b: mean.b + off * d.2), childVars, remaining - 1)
        }
        descend(stats.centroid, stats.pcs.map { max(0, $0.variance) }, 7)

        let figures8 = leaves.map {
            DyadPalette.srgb8(from: DyadPalette.chromaClamp(DyadPalette.clampL($0)))
        }
        let figures = figures8.map { DyadPalette.oklab(fromSRGB8: $0) }
        var canonical16: [Int] = []
        canonical16.reserveCapacity(16)
        for c in 0..<16 {
            var best = c * 8
            var bestD = Double.infinity
            for j in (c * 8)..<(c * 8 + 8) {
                let d2 = DyadPalette.dLab2(figures[j], nodes16[c])
                if d2 < bestD { bestD = d2; best = j }
            }
            canonical16.append(best)
        }
        return Figures(figures8: figures8, figures: figures,
                       nodes16: nodes16, canonical16: canonical16)
    }

    /// The full v3 table: tree figures + generated grounds, laid out
    /// so T[255−i] = ground(gm, T[i]) — the DY2 form, tree leaves in
    /// place of ring shells.
    static func table(figures8: [(UInt8, UInt8, UInt8)],
                      moments: DyadPalette.GroundMoments) -> [(UInt8, UInt8, UInt8)] {
        figures8 + figures8.reversed().map { DyadPalette.ground(moments, of: $0) }
    }

    /// Rebuild entry point (DYAD STATS v3): the same 13 generating
    /// numbers as v2, solved through the tree.
    static func table(stats: DyadPalette.Stats,
                      moments: DyadPalette.GroundMoments) -> [(UInt8, UInt8, UInt8)] {
        table(figures8: solveFigures(stats: stats).figures8, moments: moments)
    }
}
