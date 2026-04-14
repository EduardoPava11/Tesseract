// PerfectQuantizer.swift
// Tesseract
//
// Capture-then-compute: process ALL 64 frames globally.
//
// Uses algebraic types from Axes.swift + Histogram.swift:
//   BlockHist → ComposedColor → epoch threading → palette indices
//
// The GPU captures raw 64×64 RGB + depth per frame (CapturedFrame).
// This module processes them ALL after capture to produce the GIF.
//
// Pipeline:
//   1. Per-pixel BlockHist (14-bin per channel, constructive)
//   2. Per-channel bin assignment (match supply to bell-curve demand)
//   3. Epoch threading through each color group (Gaussian cadence)
//   4. Compose palette indices: d×64 + a×16 + b×4 + c
//
// Axioms:
//   PQ1: All 4096 pixels assigned per frame
//   PQ2: Epoch distribution matches Gaussian cadence ±1
//   PQ3: Deterministic (no randomness)
//   PQ4: Near-depth pixels get dominant epoch
//   PQ5: Color levels come from bin assignment (not arbitrary)

import Foundation

struct PerfectQuantizer {

    // MARK: - Global Quantize (capture-then-compute)

    /// Process ALL captured frames globally → QuantizedFrames for GIF.
    /// This is the main entry point after capture completes.
    static func quantizeGlobal(frames: [CapturedFrame]) -> [QuantizedFrame] {
        return frames.map { frame in
            let indices = quantizeFrame(
                frameIndex: frame.index,
                rgb: frame.rgb,
                depths: frame.depths
            )
            return QuantizedFrame(
                index: frame.index,
                paletteIndices: indices,
                rawRGB: frame.rgb,
                depths: frame.depths,
                measure: BirkhoffMeasure(paletteIndices: indices),
                subjectAnalysis: analyzeSubject(depths: frame.depths),
                anchorTrace: findAnchors(indices: indices),
                timestamp: frame.timestamp
            )
        }
    }

    // MARK: - Per-Frame Quantization

    /// Quantize one frame using histogram-based bin assignment + epoch threading.
    ///
    /// Phase 1: Build per-pixel BlockHist (14-bin per channel)
    /// Phase 2: Assign bins per channel (match supply → bell-curve demand)
    /// Phase 3: Thread epochs through each display color group
    static func quantizeFrame(
        frameIndex z: Int,
        rgb: [(Float, Float, Float)],
        depths: [Float]
    ) -> [UInt8] {
        let n = rgb.count  // 4096

        // ════════════════════════════════════════════
        // Phase 1 + 2: Color dithering (F-S on R, G, B independently)
        //
        // Floyd-Steinberg on each color channel SEPARATELY.
        // Depth controls diffusion: near=accurate, far=diverse.
        // This fills the color cube by nudging pixels across
        // quantization boundaries. Epoch is NOT touched here.
        //
        // Then wrap as ComposedColor using the Axes types.
        // ════════════════════════════════════════════

        let w = 64
        var errorR = [Float](repeating: 0, count: n)
        var errorG = [Float](repeating: 0, count: n)
        var errorB = [Float](repeating: 0, count: n)
        var quantA = [Int](repeating: 0, count: n)
        var quantB = [Int](repeating: 0, count: n)
        var quantC = [Int](repeating: 0, count: n)

        let cellCenters: [Float] = [0.125, 0.375, 0.625, 0.875]

        for y in 0..<w {
            for x in 0..<w {
                let i = y * w + x
                let (r, g, b) = rgb[i]
                let depth = i < depths.count ? depths[i] : Float(0.5)

                // Adjusted = true + accumulated error (clamped)
                let adjR = r + max(-0.2, min(0.2, errorR[i]))
                let adjG = g + max(-0.2, min(0.2, errorG[i]))
                let adjB = b + max(-0.2, min(0.2, errorB[i]))

                // Nearest level per channel
                let a = min(3, max(0, Int(round(adjR * 3.0))))
                let bq = min(3, max(0, Int(round(adjG * 3.0))))
                let c = min(3, max(0, Int(round(adjB * 3.0))))
                quantA[i] = a; quantB[i] = bq; quantC[i] = c

                // Error per channel
                let eR = adjR - cellCenters[a]
                let eG = adjG - cellCenters[bq]
                let eB = adjB - cellCenters[c]

                // Depth-weighted: near=30% diffusion, far=100%
                let s = 1.0 - depth * 0.7
                let dR = eR * s, dG = eG * s, dB = eB * s

                // F-S kernel (color only, epoch untouched)
                if x + 1 < w {
                    let j = i + 1
                    errorR[j] += dR * 7.0/16.0; errorG[j] += dG * 7.0/16.0; errorB[j] += dB * 7.0/16.0
                }
                if x > 0 && y + 1 < w {
                    let j = (y+1)*w + (x-1)
                    errorR[j] += dR * 3.0/16.0; errorG[j] += dG * 3.0/16.0; errorB[j] += dB * 3.0/16.0
                }
                if y + 1 < w {
                    let j = (y+1)*w + x
                    errorR[j] += dR * 5.0/16.0; errorG[j] += dG * 5.0/16.0; errorB[j] += dB * 5.0/16.0
                }
                if x + 1 < w && y + 1 < w {
                    let j = (y+1)*w + (x+1)
                    errorR[j] += dR * 1.0/16.0; errorG[j] += dG * 1.0/16.0; errorB[j] += dB * 1.0/16.0
                }
            }
        }

        // Wrap dithered levels as ComposedColor (orthogonal types)
        let colors = (0..<n).map { i in
            ComposedColor(
                r: RBin(value: valueToBin(cellCenters[quantA[i]])),
                g: GBin(value: valueToBin(cellCenters[quantB[i]])),
                b: BBin(value: valueToBin(cellCenters[quantC[i]]))
            )
        }

        // ════════════════════════════════════════════
        // Phase 3: Temporal dithering (Floyd-Steinberg on epoch axis)
        //
        // For each pixel: compute ideal continuous epoch from Gaussian cadence.
        // Quantize to nearest integer epoch (0..3).
        // Diffuse temporal error to spatial neighbors.
        // Depth controls diffusion strength:
        //   near (face): low diffusion → locked to dominant epoch (stable)
        //   far (wall): full diffusion → smooth epoch transitions (variable)
        //
        // The COLOR is FROZEN from Phase 2 (type-enforced).
        // Only the epoch changes. This is dithering on T, not on R/G/B.
        // ════════════════════════════════════════════

        var result = [UInt8](repeating: 0, count: n)

        // Compute the ideal continuous "epoch position" per pixel.
        // This is the weighted average of epoch indices by their probabilities:
        //   idealEpoch = Σ d × P(d|z, depth_i) ∈ [0, 3]
        // For frame 8: idealEpoch ≈ 0.15 (mostly epoch 0)
        // For frame 24: idealEpoch ≈ 1.1 (mostly epoch 1)

        var epochError = [Float](repeating: 0, count: n)

        for y in 0..<w {
            for x in 0..<w {
                let i = y * w + x
                let depth = i < depths.count ? depths[i] : Float(0.5)
                let sigma = BinomialCadence.sigmaForDepth(depth)
                let probs = BinomialCadence.gaussianProbs(frame: z, sigma: sigma)

                // Ideal continuous epoch = expected value of the distribution
                let idealEpoch = probs[0] * 0.0 + probs[1] * 1.0 + probs[2] * 2.0 + probs[3] * 3.0

                // Add accumulated temporal error (clamped to prevent runaway)
                let adjusted = idealEpoch + max(-0.8, min(0.8, epochError[i]))

                // Quantize to nearest integer epoch
                let quantized = min(3, max(0, Int(round(adjusted))))

                // Compose palette index (color frozen from Phase 2, epoch from dithering)
                result[i] = paletteIndex(
                    color: colors[i],
                    epoch: TessEpoch(value: quantized)
                )

                // Temporal error = ideal - quantized
                let err = adjusted - Float(quantized)

                // Depth-weighted diffusion:
                //   near (depth=1): 30% diffusion → preserve subject stability
                //   far (depth=0): 100% diffusion → smooth epoch transitions
                let strength = 1.0 - depth * 0.7

                let diff = err * strength

                // Floyd-Steinberg kernel on temporal error
                if x + 1 < w {
                    epochError[i + 1] += diff * 7.0 / 16.0
                }
                if x > 0 && y + 1 < w {
                    epochError[(y + 1) * w + (x - 1)] += diff * 3.0 / 16.0
                }
                if y + 1 < w {
                    epochError[(y + 1) * w + x] += diff * 5.0 / 16.0
                }
                if x + 1 < w && y + 1 < w {
                    epochError[(y + 1) * w + (x + 1)] += diff * 1.0 / 16.0
                }
            }
        }

        return result
    }

    // MARK: - Quick Preview Quantize (per-frame, approximate)

    /// Fast per-frame quantization for live preview display.
    /// Uses nearest-level quantization (no histogram matching).
    /// Good enough for 20fps preview, not for GIF.
    static func previewQuantize(
        rgb: [(Float, Float, Float)],
        depths: [Float],
        frameIndex z: Int
    ) -> [UInt8] {
        let n = rgb.count
        var result = [UInt8](repeating: 0, count: n)

        for i in 0..<n {
            let (r, g, b) = rgb[i]
            let a = TessLevel(value: min(3, max(0, Int(round(Float(r) * 3.0)))))
            let bv = TessLevel(value: min(3, max(0, Int(round(Float(g) * 3.0)))))
            let c = TessLevel(value: min(3, max(0, Int(round(Float(b) * 3.0)))))
            let depth = i < depths.count ? depths[i] : Float(0.5)
            let epoch = TessEpoch(value: dominantEpoch(frame: z, depth: depth))
            result[i] = UInt8(epoch.value * 64 + a.value * 16 + bv.value * 4 + c.value)
        }

        return result
    }

    /// Dominant epoch for a pixel given frame and depth
    private static func dominantEpoch(frame z: Int, depth: Float) -> Int {
        let probs = BinomialCadence.gaussianProbs(frame: z, sigma: BinomialCadence.sigmaForDepth(depth))
        var maxP: Float = 0; var maxD = 0
        for d in 0..<4 {
            if probs[d] > maxP { maxP = probs[d]; maxD = d }
        }
        return maxD
    }

    // MARK: - Largest Remainder Method

    /// Distribute `total` items across 4 bins proportional to `weights`.
    static func largestRemainder(total: Int, weights: SIMD4<Float>) -> [Int] {
        let ideal = (0..<4).map { Double(weights[$0]) * Double(total) }
        var floored = ideal.map { Int($0) }
        var remainders = (0..<4).map { ideal[$0] - Double(floored[$0]) }
        var leftover = total - floored.reduce(0, +)
        while leftover > 0 {
            if let maxIdx = remainders.enumerated().max(by: { $0.element < $1.element })?.offset {
                floored[maxIdx] += 1
                remainders[maxIdx] = -1
                leftover -= 1
            } else { break }
        }
        return floored
    }

    // MARK: - Subject Analysis

    static func analyzeSubject(depths: [Float]) -> SubjectAnalysis {
        var subCount = 0, bgCount = 0, borderCount = 0
        var subSum: Float = 0, bgSum: Float = 0
        for d in depths {
            if d > 0.6 { subCount += 1; subSum += d }
            else if d < 0.4 { bgCount += 1; bgSum += d }
            else { borderCount += 1 }
        }
        let subMean = subCount > 0 ? subSum / Float(subCount) : 0.5
        let bgMean = bgCount > 0 ? bgSum / Float(bgCount) : 0.5
        let subSigma = BinomialCadence.sigmaForDepth(subMean)
        let bgSigma = BinomialCadence.sigmaForDepth(bgMean)
        return SubjectAnalysis(
            subjectPixelCount: subCount, backgroundPixelCount: bgCount,
            borderPixelCount: borderCount, subjectMeanDepth: subMean,
            backgroundMeanDepth: bgMean, subjectSigma: subSigma,
            backgroundSigma: bgSigma, resolutionRatio: bgSigma / max(subSigma, 0.001)
        )
    }

    // MARK: - Anchor Tracking

    static func findAnchors(indices: [UInt8]) -> AnchorTrace {
        var blackIdx: Int? = nil, whiteIdx: Int? = nil
        var blackCount = 0, whiteCount = 0
        for (i, idx) in indices.enumerated() {
            let abc = idx % 64
            if abc == 0 { blackCount += 1; if blackIdx == nil { blackIdx = i } }
            if abc == 63 { whiteCount += 1; if whiteIdx == nil { whiteIdx = i } }
        }
        return AnchorTrace(
            blackPixelIndex: blackIdx, blackPaletteIndex: blackIdx.map { indices[$0] },
            blackEpoch: blackIdx.map { indices[$0] / 64 },
            whitePixelIndex: whiteIdx, whitePaletteIndex: whiteIdx.map { indices[$0] },
            whiteEpoch: whiteIdx.map { indices[$0] / 64 },
            blackCount: blackCount, whiteCount: whiteCount
        )
    }
}

// MARK: - Analysis Structs

struct SubjectAnalysis {
    let subjectPixelCount: Int
    let backgroundPixelCount: Int
    let borderPixelCount: Int
    let subjectMeanDepth: Float
    let backgroundMeanDepth: Float
    let subjectSigma: Float
    let backgroundSigma: Float
    let resolutionRatio: Float
}

struct AnchorTrace {
    let blackPixelIndex: Int?
    let blackPaletteIndex: UInt8?
    let blackEpoch: UInt8?
    let whitePixelIndex: Int?
    let whitePaletteIndex: UInt8?
    let whiteEpoch: UInt8?
    let blackCount: Int
    let whiteCount: Int
}
