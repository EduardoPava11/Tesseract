// BinomialCadence.swift
// Tesseract
//
// Port of TemporalBinomial.hs — The R1 axis as a binomial cadence.
// P(epoch d | frame z) ∝ exp(-(z - μ_d)² / 2σ²)
// One model governs epoch placement, counts, and transitions.

import Foundation
import simd

/// The binomial temporal cadence: soft epoch transitions via Gaussian mixing.
struct BinomialCadence {

    // MARK: - Constants

    /// Gaussian width (same for all epochs)
    static let sigma: Float = 63.0 / 8.0  // = 7.875

    /// Epoch centers: equispaced across [0, 63]
    /// μ_d = (2d + 1) × 63 / 8
    static let centers: SIMD4<Float> = SIMD4(7.875, 23.625, 39.375, 55.125)

    // MARK: - P(epoch | frame)

    /// Compute P(epoch d | frame z) for all 4 epochs.
    /// Returns a normalized probability vector (sums to 1).
    static func epochProbabilities(frame z: Int) -> SIMD4<Float> {
        let zf = Float(z)
        let s2 = 2.0 * sigma * sigma
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

    /// Sample an epoch from P(d|z) using a deterministic hash.
    /// Each pixel (x, y) in frame z gets its own hash → its own epoch.
    static func sampleEpoch(frame z: Int, x: Int, y: Int, seed: UInt32 = 42) -> UInt8 {
        let probs = epochProbabilities(frame: z)
        let u = Self.pixelHashFloat(x: x, y: y, seed: seed &+ UInt32(z) &* 997)
        return cdfSample(probs: probs, u: u)
    }

    // MARK: - Crossover Frames

    /// Frame where P(d) = P(d+1) (the soft boundary)
    static func crossoverFrame(epoch d: Int) -> Float {
        guard d < 3 else { return 63 }
        return (centers[d] + centers[d + 1]) / 2.0
    }

    /// All 3 crossover frames
    static let crossovers: [Float] = [
        (centers[0] + centers[1]) / 2,
        (centers[1] + centers[2]) / 2,
        (centers[2] + centers[3]) / 2
    ]

    // MARK: - Precomputed table (64 frames)

    /// Precompute P(d|z) for all 64 frames → fast lookup
    static let table: [SIMD4<Float>] = (0..<64).map { epochProbabilities(frame: $0) }

    // MARK: - Hash PRNG

    /// SplitMix-style hash: deterministic float in [0, 1) from (x, y, seed)
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
