// WassersteinCoordinates.swift
// Tesseract
//
// Pure-Swift 1-D optimal-transport helpers for the DNG mode:
//
//   • project a 256-bin palette histogram to 16 luminance strata
//     (stratum = index / 16 for now — STRATA SEAM below)
//   • 1-D Earth Mover's Distance on normalized histograms:
//     EMD(p, q) = Σ_i |CDF_p(i) - CDF_q(i)|   (bin-unit ground metric)
//   • barycentric coordinates λ = (λ0, λ1, λ2) of a target histogram
//     against a 3-atom dictionary, by coarse grid search over the simplex,
//     minimizing EMD(target, Σ λ_k · dict_k).
//
// No Metal, no camera — unit-tested in WassersteinCoordinatesTests.

import Foundation

enum WassersteinCoordinates {

    /// Number of luminance strata the 256-bin histogram is folded into.
    static let strataCount = 16

    /// Grid resolution of the simplex search: λ components move in steps
    /// of 1/gridSteps. 16 steps → 153 candidate triples (coarse, exact
    /// at the vertices).
    static let gridSteps = 16

    // MARK: - Strata projection

    /// Fold 256 palette-bin counts into `strataCount` bins and normalize
    /// to a probability vector. Returns the uniform distribution for an
    /// all-zero histogram (degenerate input; keeps EMD well-defined).
    ///
    /// STRATA SEAM: stratum = index / 16 for now. When the bell palette
    /// constructor lands, replace this with true luminance strata.
    static func projectToStrata(_ counts: [Int]) -> [Double] {
        let k = strataCount
        var strata = [Double](repeating: 0, count: k)
        for (i, c) in counts.enumerated() where c > 0 {
            strata[min(i / (256 / k), k - 1)] += Double(c)
        }
        let total = strata.reduce(0, +)
        guard total > 0 else {
            return [Double](repeating: 1.0 / Double(k), count: k)
        }
        return strata.map { $0 / total }
    }

    // MARK: - 1-D EMD

    /// Earth Mover's Distance between two normalized histograms over the
    /// same 1-D binning: Σ |ΔCDF|. Ground metric = 1 per bin step, so the
    /// EMD between δ_i and δ_j is exactly |i - j|.
    static func emd(_ p: [Double], _ q: [Double]) -> Double {
        precondition(p.count == q.count, "EMD requires equal bin counts")
        var cdfDiff = 0.0
        var total = 0.0
        for i in 0..<p.count {
            cdfDiff += p[i] - q[i]
            total += abs(cdfDiff)
        }
        return total
    }

    // MARK: - Barycentric coordinates

    /// λ-weighted bin-wise mixture of the 3 dictionary histograms.
    static func mixture(_ dict: (a: [Double], b: [Double], c: [Double]),
                        _ lambda: SIMD3<Double>) -> [Double] {
        (0..<dict.a.count).map {
            lambda.x * dict.a[$0] + lambda.y * dict.b[$0] + lambda.z * dict.c[$0]
        }
    }

    /// Barycentric coordinates of `target` against a 3-atom dictionary by
    /// coarse simplex grid search (λ ∈ {0, 1/n, …, 1}³, Σλ = 1), minimizing
    /// EMD(target, mixture(λ)). Deterministic: ties resolve to the first
    /// candidate in (i, j) lexicographic order, and each vertex is tested
    /// exactly, so a target equal to a dictionary atom recovers its simplex
    /// vertex whenever the atoms are EMD-distinguishable.
    static func coordinates(target: [Double],
                            dictionary: (a: [Double], b: [Double], c: [Double]),
                            gridSteps n: Int = gridSteps) -> (lambda: SIMD3<Double>, emd: Double) {
        var best = SIMD3<Double>(1, 0, 0)
        var bestD = Double.infinity
        for i in 0...n {
            for j in 0...(n - i) {
                let lambda = SIMD3<Double>(
                    Double(i) / Double(n),
                    Double(j) / Double(n),
                    Double(n - i - j) / Double(n)
                )
                let d = emd(target, mixture(dictionary, lambda))
                if d < bestD {
                    bestD = d
                    best = lambda
                }
            }
        }
        return (best, bestD)
    }

    /// Full trajectory for a burst: per-frame strata histograms against the
    /// dictionary {frame 0, frame mid, frame last}. Returns one λ-triple per
    /// frame (partition of unity by construction).
    static func trajectory(strataHistograms: [[Double]]) -> [SIMD3<Double>] {
        guard let first = strataHistograms.first else { return [] }
        let mid = strataHistograms[strataHistograms.count / 2]
        let last = strataHistograms[strataHistograms.count - 1]
        let dict = (a: first, b: mid, c: last)
        return strataHistograms.map { coordinates(target: $0, dictionary: dict).lambda }
    }
}
