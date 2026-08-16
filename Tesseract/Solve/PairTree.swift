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
    /// The tree's full depth: 7 generations, 128 leaves. Named so the
    /// identity of the eFig dial is a constant with a reason rather
    /// than a 7 someone has to recognise.
    static let fullDepth = 7

    struct Figures: Sendable {
        /// 128 clamped figure bytes in leaf (bit) order.
        let figures8: [(UInt8, UInt8, UInt8)]
        /// OKLab of the clamped figure bytes — the assignment prims.
        let figures: [OKLabColor]
        /// Analytic depth-4 node means (16, one per leaf octet).
        /// Equal to `levels[4]`; kept as its own field because the
        /// sigma-side 32-level target and the Metal buffer both name it.
        let nodes16: [OKLabColor]
        /// ★ EVERY LEVEL OF THE TREE, depth 0 through 7, added
        /// 2026-08-16. `levels[d]` holds 2^d node means in left-to-right
        /// order, so `levels[7]` is the leaves and `levels[0]` is the
        /// centroid. 255 colours in total, which is less than the
        /// palette it describes.
        ///
        /// WHY IT EXISTS. The descent already VISITED every level and
        /// recorded exactly one of them, so the edit space's two
        /// truncation dials had nothing to truncate to. Reweave.swift
        /// says so in its own header: "the shipped solver exposes
        /// depth-4 nodes only (PairTree `nodes16`), so general depths
        /// need the descent to record every level". Every non-identity
        /// edit refused for want of about two kilobytes.
        ///
        /// With the levels recorded, PT5's prefix law becomes
        /// executable rather than merely proved: truncating an index to
        /// d bits names `levels[d]`, so a dial position IS a lookup.
        let levels: [[OKLabColor]]
        /// Representative figure leaf per node: the octet member
        /// nearest its node's mean (deterministic, lowest index on
        /// ties). Node c covers leaves 8c ..< 8c+8.
        let canonical16: [Int]

        /// ★ THE TRUNCATION DIAL, EXECUTABLE (2026-08-16). PT5's prefix
        /// law says a truncated index names the coarser level's node, so
        /// with every level recorded the eFig dial is a LOOKUP rather than
        /// a re-solve: leaf j at depth d becomes `levels[d][j >> (7 - d)]`.
        ///
        /// The result is a lawful Figures with the same 128 slots, so
        /// nothing downstream changes shape. Distinct colours drop to
        /// 2^d, which is what the dial means: fewer, coarser figure
        /// primaries. Depth 7 is the identity and returns self.
        ///
        /// This is the function Reweave's header said needed "the descent
        /// to record every level".
        func truncated(toFigureDepth d: Int) -> Figures {
            let depth = max(0, min(7, d))
            guard depth < 7 else { return self }
            let shift = 7 - depth
            let nodes = levels[depth]
            let coarseLab = (0..<128).map { nodes[$0 >> shift] }
            let coarse8 = coarseLab.map {
                DyadPalette.srgb8(from: DyadPalette.chromaClamp(DyadPalette.clampL($0)))
            }
            return Figures(figures8: coarse8,
                           figures: coarse8.map { DyadPalette.oklab(fromSRGB8: $0) },
                           nodes16: nodes16,
                           levels: levels,
                           canonical16: canonical16)
        }
    }


    /// Build the figure half from the fitted statistics — closed
    /// form, deterministic, constant-free (PT7–PT9).
    static func solveFigures(stats: DyadPalette.Stats) -> Figures {
        let dirs = stats.pcs.map { $0.direction }
        var leaves: [OKLabColor] = []
        leaves.reserveCapacity(128)
        var levels = [[OKLabColor]](repeating: [], count: 8)
        for d in 0...7 { levels[d].reserveCapacity(1 << d) }

        func descend(_ mean: OKLabColor, _ vars: [Double], _ remaining: Int) {
            // depth 0 is the centroid, depth 7 the leaves. The descent
            // is depth-first left-then-right, so appends at a given
            // depth land in left-to-right order, which is exactly the
            // order PT5's prefix law indexes.
            levels[7 - remaining].append(mean)
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
        let nodes16 = levels[4]

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
                       nodes16: nodes16, levels: levels,
                       canonical16: canonical16)
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
