// BinomialCadence.swift
// Tesseract
//
// Port of TemporalBinomial.hs — The R1 axis as a binomial cadence.
// P(epoch d | frame z, depth k) ∝ exp(-(z - μ_d)² / 2σ_k²)
//
// Depth drives SNR: near pixels (face) are stable, far pixels (background) shimmer.
// σ_k = σ_base × snrFactor(k)
//   k=0 (near):  snrFactor=0.5  → sharp epoch peaks → temporally crisp
//   k=3 (far):   snrFactor=2.0  → flat distribution → temporally volatile

import Foundation
import simd

/// The binomial temporal cadence with depth-driven signal-to-noise ratio.
struct BinomialCadence {

    // MARK: - Constants

    /// Base Gaussian width
    static let sigma: Float = 63.0 / 8.0  // = 7.875

    /// Epoch centers: equispaced across [0, 63]
    static let centers: SIMD4<Float> = SIMD4(7.875, 23.625, 39.375, 55.125)

    /// SNR factors per depth zone.
    /// Near (signal) → narrow σ → stable. Far (noise) → wide σ → volatile.
    static let snrFactors: [Float] = [0.5, 0.75, 1.25, 2.0]

    // MARK: - P(epoch | frame) — without depth (backward compatible)

    /// Compute P(epoch d | frame z) for all 4 epochs (no depth).
    static func epochProbabilities(frame z: Int) -> SIMD4<Float> {
        gaussianProbs(frame: z, sigma: sigma)
    }

    // MARK: - P(epoch | frame, depth) — depth-aware SNR

    /// Compute P(epoch d | frame z, depth zone k).
    /// Near pixels get narrow σ (stable), far pixels get wide σ (volatile).
    static func epochProbabilities(frame z: Int, depthZone: UInt8) -> SIMD4<Float> {
        let k = Int(min(3, depthZone))
        let depthSigma = sigma * snrFactors[k]
        return gaussianProbs(frame: z, sigma: depthSigma)
    }

    /// Core Gaussian computation with parameterized σ.
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
        return raw / total
    }

    /// Get P(epoch d | frame z) for a single epoch.
    static func epochProb(frame z: Int, epoch d: Int) -> Float {
        epochProbabilities(frame: z)[d]
    }

    // MARK: - Epoch Sampling

    /// Sample epoch WITHOUT depth (backward compatible for preview).
    static func sampleEpoch(frame z: Int, x: Int, y: Int, seed: UInt32 = 42) -> UInt8 {
        let probs = epochProbabilities(frame: z)
        let u = pixelHashFloat(x: x, y: y, seed: seed &+ UInt32(z) &* 997)
        return cdfSample(probs: probs, u: u)
    }

    /// Sample epoch WITH depth-driven SNR.
    /// Near pixels (depthZone=0) stick to their epoch.
    /// Far pixels (depthZone=3) randomly jump between epochs.
    static func sampleEpoch(frame z: Int, x: Int, y: Int,
                             depthZone: UInt8, seed: UInt32 = 42) -> UInt8 {
        let probs = epochProbabilities(frame: z, depthZone: depthZone)
        let u = pixelHashFloat(x: x, y: y, seed: seed &+ UInt32(z) &* 997)
        return cdfSample(probs: probs, u: u)
    }

    // MARK: - Crossover Frames

    static func crossoverFrame(epoch d: Int) -> Float {
        guard d < 3 else { return 63 }
        return (centers[d] + centers[d + 1]) / 2.0
    }

    static let crossovers: [Float] = [
        (centers[0] + centers[1]) / 2,
        (centers[1] + centers[2]) / 2,
        (centers[2] + centers[3]) / 2
    ]

    // MARK: - Precomputed table (no depth, for preview)

    static let table: [SIMD4<Float>] = (0..<64).map { epochProbabilities(frame: $0) }

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
