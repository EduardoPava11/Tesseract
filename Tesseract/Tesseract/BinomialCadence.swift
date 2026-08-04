// BinomialCadence.swift
// Tesseract
//
// Port of ContinuousDepthCadence.hs + Block.hs epoch scaling.
// σ_base(K) = (K-1) / 8. Epoch centers = (2d+1) × σ_base.
// σ(depth) = σ_base × (2 - depth). No zones. No lookup table.
//
// The formula scales with frame count K:
//   64 frames: σ_base = 7.875,  centers = [7.875, 23.625, 39.375, 55.125]
//   32 frames: σ_base = 3.875,  centers = [3.875, 11.625, 19.375, 27.125]
//   16 frames: σ_base = 1.875,  centers = [1.875,  5.625,  9.375, 13.125]
//
// Verified by Block.hs axioms C9 (probs sum to 1) and C15 (crossovers proportional).

import Foundation
import simd

struct BinomialCadence {

    // MARK: - Scale-aware constants
    // Pure in K (Block.hs style) so the scale laws stay testable at every
    // cube size even though the app pins CameraConfig.mode to 64³.

    /// σ_base(K) = (K - 1) / 8
    static func sigmaBase(frameCount k: Int) -> Float {
        Float(k - 1) / 8.0
    }

    /// σ_base for the active capture config
    static var sigmaBase: Float {
        sigmaBase(frameCount: CameraConfig.totalFrames)
    }

    /// 4 epoch centers = (2d + 1) × σ_base for d ∈ {0,1,2,3}
    static func centers(frameCount k: Int) -> SIMD4<Float> {
        let sb = sigmaBase(frameCount: k)
        return SIMD4(1 * sb, 3 * sb, 5 * sb, 7 * sb)
    }

    /// Centers for the active capture config
    static var centers: SIMD4<Float> {
        centers(frameCount: CameraConfig.totalFrames)
    }

    /// Crossover points (midpoints between adjacent epoch centers)
    static var crossovers: [Float] {
        let c = centers
        return [
            (c[0] + c[1]) / 2,
            (c[1] + c[2]) / 2,
            (c[2] + c[3]) / 2
        ]
    }

    // MARK: - σ from continuous depth

    /// σ(depth) = σ_base × (2 - depth)
    /// depth=1 (near): σ = σ_base → sharp. depth=0 (far): σ = 2×σ_base → flat.
    static func sigmaForDepth(_ depth: Float, frameCount k: Int) -> Float {
        sigmaBase(frameCount: k) * (2.0 - depth)
    }

    static func sigmaForDepth(_ depth: Float) -> Float {
        sigmaForDepth(depth, frameCount: CameraConfig.totalFrames)
    }

    // MARK: - P(epoch | frame, depth)

    /// Continuous depth → epoch probabilities. No zones. Pure in K.
    static func epochProbabilities(frame z: Int, depth: Float, frameCount k: Int) -> SIMD4<Float> {
        gaussianProbs(frame: z, sigma: sigmaForDepth(depth, frameCount: k), frameCount: k)
    }

    static func epochProbabilities(frame z: Int, depth: Float) -> SIMD4<Float> {
        epochProbabilities(frame: z, depth: depth, frameCount: CameraConfig.totalFrames)
    }

    /// No-depth version (preview mode, uses base σ)
    static func epochProbabilities(frame z: Int) -> SIMD4<Float> {
        gaussianProbs(frame: z, sigma: sigmaBase)
    }

    /// Gaussian probability computation — accepts sigma directly.
    /// Used by PerfectQuantizer for per-group depth-averaged sigma.
    static func gaussianProbs(frame z: Int, sigma s: Float) -> SIMD4<Float> {
        gaussianProbs(frame: z, sigma: s, frameCount: CameraConfig.totalFrames)
    }

    static func gaussianProbs(frame z: Int, sigma s: Float, frameCount k: Int) -> SIMD4<Float> {
        let zf = Float(z)
        let s2 = 2.0 * s * s
        let c = centers(frameCount: k)
        let raw = SIMD4<Float>(
            exp(-(zf - c[0]) * (zf - c[0]) / s2),
            exp(-(zf - c[1]) * (zf - c[1]) / s2),
            exp(-(zf - c[2]) * (zf - c[2]) / s2),
            exp(-(zf - c[3]) * (zf - c[3]) / s2)
        )
        let total = raw[0] + raw[1] + raw[2] + raw[3]
        return raw / max(total, 1e-10)
    }
}
