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

    // MARK: - σ from continuous depth (the one formula)

    /// σ(depth) = σ_base × (2 - depth)
    /// depth=1 (near): σ=7.875 → sharp. depth=0 (far): σ=15.75 → flat.
    static func sigmaForDepth(_ depth: Float) -> Float {
        sigma * (2.0 - depth)
    }

    // MARK: - P(epoch | frame, depth)

    /// Continuous depth → epoch probabilities. No zones.
    static func epochProbabilities(frame z: Int, depth: Float) -> SIMD4<Float> {
        let s = sigmaForDepth(depth)
        return gaussianProbs(frame: z, sigma: s)
    }

    /// No-depth version (preview mode, uses base σ)
    static func epochProbabilities(frame z: Int) -> SIMD4<Float> {
        gaussianProbs(frame: z, sigma: sigma)
    }

    private static func gaussianProbs(frame z: Int, sigma s: Float) -> SIMD4<Float> {
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

    // MARK: - Epoch Sampling

    /// Sample epoch with continuous depth. The main path.
    static func sampleEpoch(frame z: Int, x: Int, y: Int,
                             depth: Float, seed: UInt32 = 42) -> UInt8 {
        let probs = epochProbabilities(frame: z, depth: depth)
        let u = pixelHashFloat(x: x, y: y, seed: seed &+ UInt32(z) &* 997)
        return cdfSample(probs: probs, u: u)
    }

    /// Sample epoch without depth (preview mode).
    static func sampleEpoch(frame z: Int, x: Int, y: Int,
                             seed: UInt32 = 42) -> UInt8 {
        let probs = epochProbabilities(frame: z)
        let u = pixelHashFloat(x: x, y: y, seed: seed &+ UInt32(z) &* 997)
        return cdfSample(probs: probs, u: u)
    }

    // MARK: - Crossovers

    static let crossovers: [Float] = [
        (centers[0] + centers[1]) / 2,
        (centers[1] + centers[2]) / 2,
        (centers[2] + centers[3]) / 2
    ]

    // MARK: - Hash PRNG

    static func pixelHashFloat(x: Int, y: Int, seed: UInt32) -> Float {
        let h0 = UInt32(bitPattern: Int32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263)) &+ seed
        let h1 = (h0 ^ (h0 >> 15)) &* 2246822519
        let h2 = (h1 ^ (h1 >> 13)) &* 3266489917
        let h3 = h2 ^ (h2 >> 16)
        return Float(h3 % 1_000_000) / 1_000_000.0
    }

    // MARK: - CDF Sampling

    private static func cdfSample(probs: SIMD4<Float>, u: Float) -> UInt8 {
        var cumul: Float = 0
        for d in 0..<3 {
            cumul += probs[d]
            if cumul >= u { return UInt8(d) }
        }
        return 3
    }
}
