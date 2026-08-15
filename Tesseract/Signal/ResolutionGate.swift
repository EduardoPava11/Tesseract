// ResolutionGate.swift
// Tesseract
//
// P1: DEPTH PICKS THE RESOLUTION. Port of the amended gate in
// spec/quantization/ResolutionLadder.hs (RL1 to RL4; the Haskell is
// authoritative). Daniel's ruling, 2026-08-14:
//
//   "we would need to use the 16x16, 32x32, 64x64 stack IN relation
//    to depth, in order to pick resolution size. NOT color."
//
// ── WHAT THE MEASUREMENT SETTLED ────────────────────────────────
//
// TesseractTests/DepthQualityHarness measured the depth field at all
// three rungs under three degradation levels, including 60% dropout
// at the silhouette where TrueDepth actually fails. Two results, and
// together they decide the whole shape of this file:
//
//   CONFIDENCE IS NOT THE CRITERION. The two phases separate at 9
//   SIGMA OR MORE at every rung, even harsh, and the posterior
//   commits (0.99) everywhere. There is nothing to be unsure about
//   in a solid region, at any resolution. So the gate does not test
//   quality, and this file contains no confidence threshold.
//
//   GEOMETRY IS. Edge error is EXACTLY the block size: 1.00, 2.00,
//   4.00 fine cells at rungs 64, 32, 16. Depth cannot place a
//   boundary more precisely than the cell it was measured in.
//
// So the fine rung is spent at the BOUNDARY, not on the subject. A
// solid figure and a solid ground are the same case: no edge, floor
// rung, nothing lost. The gate is a RIDGE, not a ramp, and RL1 proves
// that symmetry rather than asserting it.
//
// ── NO NAKED CONSTANTS ──────────────────────────────────────────
//
// The thresholds are the BAYER MATRIX'S OWN LEVELS, read off the same
// 4x4 matrix DyadPipeline already dithers with. Its extrema are
// already the app's solid/band boundaries (DepthMixture), so this
// file introduces no number that was not already derived.
//
// ── WHAT THIS COSTS ─────────────────────────────────────────────
//
// The band is a thin shell around the silhouette, so the fine rung is
// spent on a small minority of the cube. That is the same minority
// the zerotree measurement found quiet: 95.3% of subtrees say
// nothing, and those are the solid regions this gate sends to rung 16.
// The two results agree because they are the same fact seen twice.

import Foundation

/// The depth-gated resolution ladder. Pure, total, deterministic.
enum ResolutionGate {

    /// The rungs, coarsest first (RL1's rung set).
    static let rungs = [16, 32, 64]

    /// The Bayer 4x4 matrix's own levels, (2k+1)/32 for k in 0..<16.
    /// Nothing below is chosen; it is read off this list, exactly as
    /// the spec does.
    static let bayerLevels: [Double] = (0..<16).map { (2.0 * Double($0) + 1) / 32 }

    /// The solid/band boundaries, already the app's own (DepthMixture).
    static let bayerMin = bayerLevels.min()!          // 1/32
    static let bayerMax = bayerLevels.max()!          // 31/32
    /// One Bayer step inside each extreme: the band's outer shell.
    static let bayerIn1 = bayerLevels[1]              // 3/32
    static let bayerIn2 = bayerLevels[14]             // 29/32

    /// The gate: depth coverage t to a resolution rung, by DISTANCE
    /// TO THE BOUNDARY. Mirrors `rungOf` in the spec statement for
    /// statement, which is what makes the parity test meaningful.
    static func rung(coverage t: Double) -> Int {
        if t < bayerMin || t > bayerMax { return 16 }   // solid, no edge here
        if t < bayerIn1 || t > bayerIn2 { return 32 }   // the band's outer shell
        return 64                                       // the band core
    }

    /// Expected pixels per palette colour at a rung (RL3).
    static func occupancy(rung r: Int) -> Int { r * r / 256 }

    /// The gate over a whole coverage field, plus the budget it
    /// implies. `budget` is what fraction of cells each rung claims,
    /// which is the number that decides whether this pays for itself.
    struct Selection: Equatable {
        /// One rung per cell, in the field's own order.
        let rungs: [Int]
        /// Fraction of cells at 16, 32 and 64 respectively.
        let budget: [Double]

        /// The share of cells that reached the fine rung. The band is
        /// a thin shell, so this should be small; if it is not, the
        /// capture has no clean figure/ground split and the gate is
        /// reporting that honestly rather than hiding it.
        var fineShare: Double { budget[2] }
    }

    static func select(coverage: [Double]) -> Selection {
        guard !coverage.isEmpty else {
            return Selection(rungs: [], budget: [0, 0, 0])
        }
        let rs = coverage.map { rung(coverage: $0) }
        var counts = [0, 0, 0]
        for r in rs {
            switch r {
            case 16: counts[0] += 1
            case 32: counts[1] += 1
            default: counts[2] += 1
            }
        }
        let n = Double(coverage.count)
        return Selection(rungs: rs, budget: counts.map { Double($0) / n })
    }
}
