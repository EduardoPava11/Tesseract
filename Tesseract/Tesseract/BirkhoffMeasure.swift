// BirkhoffMeasure.swift
// Tesseract
//
// Port of DeviationManifold.hs — Birkhoff's M = O/C
// O = deviation from binomial (the signal)
// C = Shannon entropy (the complexity)
// M = beauty = how efficiently the image uses its color budget

import Foundation

/// Birkhoff's Aesthetic Measure for a single frame.
/// M = O / C where O = order (deviation from binomial) and C = complexity (entropy).
struct BirkhoffMeasure {

    /// Deviation magnitude: √(Σ (count_i - E)²) where E = 4096/256 = 16
    let order: Float

    /// Shannon entropy: H = -Σ p_i log(p_i), normalized by log(256)
    let complexity: Float

    /// Manifold dimension estimate ∈ [0, 3]
    let manifoldDim: Float

    /// Number of palette entries actually used
    let colorsUsed: Int

    /// Birkhoff's aesthetic measure
    var beauty: Float {
        order / max(complexity, 0.001)
    }

    // MARK: - Binomial null model

    /// Expected count per palette entry: 4096 / 256 = 16
    static let binomialExpected: Float = 16.0

    /// Expected deviation magnitude for noise: √(256 × Var) ≈ 63.9
    static let noiseDeviation: Float = {
        let variance: Float = 4096.0 * (1.0 / 256.0) * (255.0 / 256.0)
        return sqrt(256.0 * variance)
    }()

    // MARK: - Compute from frame data

    /// Compute Birkhoff measure from a palette index histogram (256 bins).
    init(counts: [Int]) {
        let total = Float(counts.reduce(0, +))
        guard total > 0 else {
            self.order = 0; self.complexity = 0; self.manifoldDim = 3; self.colorsUsed = 0
            return
        }

        // All 256 counts (pad with zeros if needed)
        var allCounts = counts
        while allCounts.count < 256 { allCounts.append(0) }

        // Order: deviation from binomial
        let expected = total / 256.0
        let deviations = allCounts.map { Float($0) - expected }
        let sumSqDev = deviations.reduce(0) { $0 + $1 * $1 }
        self.order = sqrt(sumSqDev)

        // Complexity: normalized Shannon entropy
        let probs = allCounts.compactMap { c -> Float? in
            let p = Float(c) / total
            return p > 0 ? p : nil
        }
        let h = -probs.reduce(Float(0)) { $0 + $1 * log($1) }
        let maxH = log(Float(256))
        self.complexity = h / maxH

        // Manifold dimension
        let participation = 1.0 / probs.reduce(Float(0)) { $0 + $1 * $1 }
        let prNorm = log(max(1, participation)) / log(Float(256))
        self.manifoldDim = 3.0 * (0.6 * (h / maxH) + 0.4 * prNorm)

        // Colors used
        self.colorsUsed = allCounts.filter { $0 > 0 }.count
    }

    /// Convenience: compute from a flat array of palette indices
    init(paletteIndices: [UInt8]) {
        var histogram = [Int](repeating: 0, count: 256)
        for idx in paletteIndices {
            histogram[Int(idx)] += 1
        }
        self.init(counts: histogram)
    }
}

// MARK: - Frame Deviation (per-color breakdown)
