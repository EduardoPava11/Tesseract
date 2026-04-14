// BinomialCadence.swift
// Tesseract
//
// Port of ContinuousDepthCadence.hs
// σ(depth) = σ_base × (2 - depth). No zones. No lookup table.
// The 4 epochs EMERGE from the 4 Gaussian centers.
// Depth MODULATES the temporal axis. R1 ⊕ R3 = R4. 4⁴ = 256.

import Foundation
import simd

struct BinomialCadence {

    // MARK: - Constants

    static let sigma: Float = 63.0 / 8.0  // 7.875
    static let centers: SIMD4<Float> = SIMD4(7.875, 23.625, 39.375, 55.125)

    // MARK: - σ from continuous depth

    /// σ(depth) = σ_base × (2 - depth)
    /// depth=1 (near): σ=7.875 → sharp. depth=0 (far): σ=15.75 → flat.
    static func sigmaForDepth(_ depth: Float) -> Float {
        sigma * (2.0 - depth)
    }

    // MARK: - P(epoch | frame, depth)

    /// Continuous depth → epoch probabilities. No zones.
    static func epochProbabilities(frame z: Int, depth: Float) -> SIMD4<Float> {
        gaussianProbs(frame: z, sigma: sigmaForDepth(depth))
    }

    /// No-depth version (preview mode, uses base σ)
    static func epochProbabilities(frame z: Int) -> SIMD4<Float> {
        gaussianProbs(frame: z, sigma: sigma)
    }

    /// Gaussian probability computation — accepts sigma directly.
    /// Used by PerfectQuantizer for per-group depth-averaged sigma.
    static func gaussianProbs(frame z: Int, sigma s: Float) -> SIMD4<Float> {
        let zf = Float(z)
        let s2 = 2.0 * s * s
        let raw = SIMD4<Float>(
            exp(-(zf - centers[0]) * (zf - centers[0]) / s2),
            exp(-(zf - centers[1]) * (zf - centers[1]) / s2),
            exp(-(zf - centers[2]) * (zf - centers[2]) / s2),
            exp(-(zf - centers[3]) * (zf - centers[3]) / s2)
        )
        let total = raw[0] + raw[1] + raw[2] + raw[3]
        return raw / max(total, 1e-10)
    }

    // MARK: - Crossovers

    static let crossovers: [Float] = [
        (centers[0] + centers[1]) / 2,
        (centers[1] + centers[2]) / 2,
        (centers[2] + centers[3]) / 2
    ]
}
