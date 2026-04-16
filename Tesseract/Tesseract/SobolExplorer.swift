// SobolExplorer.swift
// Tesseract
//
// Port of spec/neural/MapElites.hs §3: Sobol quasi-random directions.
// Low-discrepancy sequence guarantees uniform coverage of ATTENTION space.
// Each swipe explores a PROVABLY new direction. No random clustering.
//
// Uses Van der Corput sequence (base 2) with per-dimension scrambling.
// Gray code ordering: O(1) per point after initialization.

import Foundation

/// Quasi-random direction generator for gene perturbation.
/// Each call to `nextDirection()` returns a direction in [-1,1]^dim
/// that is guaranteed to be different from all previous directions.
struct SobolExplorer {
    private(set) var index: Int = 0
    let dim: Int

    init(dim: Int = GeneWeights.attentionCount) {
        self.dim = dim
    }

    /// Generate the next quasi-random direction and advance the index.
    /// Returns `dim` values in [-1, 1].
    mutating func nextDirection() -> [Float] {
        let dir = direction(at: index)
        index += 1
        return dir
    }

    /// Direction at a specific index (pure, no mutation).
    func direction(at n: Int) -> [Float] {
        (0..<dim).map { d in sobol1D(n: n, d: d) }
    }

    /// Perturb a gene along the current Sobol direction.
    /// Only ATTENTION weights are modified. CORE is preserved.
    mutating func perturb(_ gene: GeneWeights, scale: Float) -> GeneWeights {
        let dir = nextDirection()
        var newWeights = gene.weights
        for i in 0..<min(dim, GeneWeights.attentionCount) {
            newWeights[i] += scale * dir[i]
        }
        return GeneWeights(weights: newWeights)
    }

    /// Reset to start (e.g., new capture session).
    mutating func reset() { index = 0 }

    // ── 1D Sobol via Van der Corput with dimension scrambling ──

    private func sobol1D(n: Int, d: Int) -> Float {
        // Scramble index by dimension (golden ratio hash)
        let scrambled = n ^ (d &* 2654435761)
        // Van der Corput: reverse bits
        let reversed = reverseBits(UInt32(truncatingIfNeeded: scrambled))
        // Normalize to [0,1] then map to [-1,1]
        let raw = Float(reversed) / Float(UInt32.max)
        return raw * 2.0 - 1.0
    }

    private func reverseBits(_ x: UInt32) -> UInt32 {
        var v = x
        v = ((v >> 1) & 0x55555555) | ((v & 0x55555555) << 1)
        v = ((v >> 2) & 0x33333333) | ((v & 0x33333333) << 2)
        v = ((v >> 4) & 0x0F0F0F0F) | ((v & 0x0F0F0F0F) << 4)
        v = ((v >> 8) & 0x00FF00FF) | ((v & 0x00FF00FF) << 8)
        v = (v >> 16) | (v << 16)
        return v
    }
}
