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
        // Phase 1: Build per-pixel BlockHist
        //
        // Currently each "block" is 1 pixel (from GPU downsample).
        // Future: GPU computes real 19×19 block histograms.
        // The type is the same either way — BlockHist.
        // ════════════════════════════════════════════

        let blockHists = rgb.map { (r, g, b) in
            BlockHist(
                r: ChannelHist.from(values: [r]),
                g: ChannelHist.from(values: [g]),
                b: ChannelHist.from(values: [b]),
                blockSide: 1
            )
        }

        // ════════════════════════════════════════════
        // Phase 2: Per-channel bin assignment (independent, orthogonal)
        //
        // Uses assignAllChannels from Histogram.swift.
        // Each channel is assigned independently.
        // The type system prevents mixing (RBin ≠ GBin ≠ BBin).
        // ════════════════════════════════════════════

        let colors = assignAllChannels(blockHists)

        // ════════════════════════════════════════════
        // Phase 3: Epoch threading through each color group
        //
        // Group pixels by display color (a,b,c).
        // For each group: compute epoch targets from Gaussian cadence.
        // Sort by depth: near → dominant epoch (stable).
        // The epoch axis is SEPARATE from color (type-enforced).
        // ════════════════════════════════════════════

        var result = [UInt8](repeating: 0, count: n)

        // Group by display color key (0..63)
        var groups = [Int: [(pixelIndex: Int, depth: Float)]]()
        for i in 0..<n {
            let key = colors[i].displayKey
            let depth = i < depths.count ? depths[i] : Float(0.5)
            groups[key, default: []].append((pixelIndex: i, depth: depth))
        }

        // Thread epochs through each group
        for (_, group) in groups {
            guard !group.isEmpty else { continue }
            let groupN = group.count

            // Average depth → sigma → epoch probabilities
            let avgDepth = group.reduce(Float(0)) { $0 + $1.depth } / Float(groupN)
            let sigma = BinomialCadence.sigmaForDepth(avgDepth)
            let probs = BinomialCadence.gaussianProbs(frame: z, sigma: sigma)

            // Target epoch counts (largest-remainder for exact sum)
            let targets = largestRemainder(total: groupN, weights: probs)

            // Sort by depth descending (near first → gets dominant epoch)
            let sorted = group.sorted { $0.depth > $1.depth }

            // Assign epochs: dominant epoch (most targets) gets near pixels
            let epochOrder = (0..<4).sorted { targets[$0] > targets[$1] }

            var offset = 0
            for epochIdx in epochOrder {
                let count = targets[epochIdx]
                for j in offset..<(offset + count) {
                    guard j < sorted.count else { break }
                    let px = sorted[j]
                    let color = colors[px.pixelIndex]
                    result[px.pixelIndex] = paletteIndex(
                        color: color,
                        epoch: TessEpoch(value: epochIdx)
                    )
                }
                offset += count
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
