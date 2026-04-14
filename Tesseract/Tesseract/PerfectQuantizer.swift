// PerfectQuantizer.swift
// Tesseract
//
// Offline CPU perfect pass: re-quantize raw RGB + depth frames
// with distribution-exact epoch assignment.
//
// The GPU preview uses per-pixel hash sampling (fast, approximate).
// This pass uses GLOBAL distribution matching (deterministic, exact):
//   1. Group pixels by display color (a,b,c)
//   2. Compute exact target epoch counts from Gaussian cadence
//   3. Sort pixels by depth (near first)
//   4. Assign epochs: near → dominant (stable), far → non-dominant (variable)
//
// Properties:
//   PQ1: All 4096 pixels assigned (bijection)
//   PQ2: Epoch distribution matches Gaussian cadence ±1 rounding
//   PQ3: Deterministic (no randomness)
//   PQ4: Near-depth pixels get dominant epoch (depth-SNR maximized)
//   PQ5: Color (a,b,c) unchanged from floor quantization

import Foundation

struct PerfectQuantizer {

    // MARK: - Perfect Pass

    /// Re-quantize all frames with distribution-exact epoch assignment.
    /// Frames must have rawRGB and depths populated (recording mode).
    /// Returns new frames with perfected paletteIndices.
    static func perfectPass(frames: [QuantizedFrame]) -> [QuantizedFrame] {
        return frames.map { frame in
            guard let rawRGB = frame.rawRGB else {
                // No raw data — return frame unchanged (GPU indices)
                return frame
            }

            let perfectedIndices = perfectFrame(
                frameIndex: frame.index,
                rgb: rawRGB,
                depths: frame.depths
            )

            let measure = BirkhoffMeasure(paletteIndices: perfectedIndices)
            let subject = analyzeSubject(depths: frame.depths)
            let anchors = findAnchors(indices: perfectedIndices)

            return QuantizedFrame(
                index: frame.index,
                paletteIndices: perfectedIndices,
                rawRGB: rawRGB,
                depths: frame.depths,
                measure: measure,
                subjectAnalysis: subject,
                anchorTrace: anchors,
                timestamp: frame.timestamp
            )
        }
    }

    // MARK: - Per-Frame Algorithm

    /// Tesseract cell centers: (level + 0.5) / 4.0
    private static let cellCenters: [Float] = [0.125, 0.375, 0.625, 0.875]

    /// Quantize one channel to nearest cell center {0,1,2,3}.
    private static func nearestLevel(_ v: Float) -> Int {
        min(3, max(0, Int(round(v * 3.0))))
    }

    /// Perfect quantization for a single frame.
    ///
    /// Stage 1: Depth-weighted Floyd-Steinberg error diffusion.
    ///   - Quantize to nearest tesseract cell center (not floor)
    ///   - Diffuse error to neighbors weighted by depth:
    ///     near (subject) → low diffusion (preserve accuracy, more detail)
    ///     far (background) → full diffusion (fill the tesseract)
    ///
    /// Stage 2: Distribution-exact epoch assignment (unchanged).
    ///   - Group by dithered (a,b,c), compute Gaussian targets, assign by depth
    static func perfectFrame(
        frameIndex z: Int,
        rgb: [(Float, Float, Float)],
        depths: [Float]
    ) -> [UInt8] {
        let n = rgb.count  // 4096
        let w = 64

        // ════════════════════════════════════════════
        // Stage 1: Depth-weighted error-diffusion dithering
        // ════════════════════════════════════════════

        // Error accumulator (3 channels per pixel)
        var errorR = [Float](repeating: 0, count: n)
        var errorG = [Float](repeating: 0, count: n)
        var errorB = [Float](repeating: 0, count: n)

        // Dithered quantization result per pixel
        var quantA = [Int](repeating: 0, count: n)
        var quantB = [Int](repeating: 0, count: n)
        var quantC = [Int](repeating: 0, count: n)

        for y in 0..<w {
            for x in 0..<w {
                let i = y * w + x
                let (r, g, b) = rgb[i]
                let depth = i < depths.count ? depths[i] : Float(0.5)

                // Adjusted color = true color + accumulated error
                let adjR = r + errorR[i]
                let adjG = g + errorG[i]
                let adjB = b + errorB[i]

                // Quantize to nearest cell center
                let a = nearestLevel(adjR)
                let bq = nearestLevel(adjG)
                let c = nearestLevel(adjB)
                quantA[i] = a; quantB[i] = bq; quantC[i] = c

                // Quantization error (true adjusted - cell center)
                let errR = adjR - cellCenters[a]
                let errG = adjG - cellCenters[bq]
                let errB = adjB - cellCenters[c]

                // Depth-weighted diffusion strength:
                //   near (depth=1, face): 30% diffusion → preserve subject detail
                //   far  (depth=0, wall): 100% diffusion → fill the tesseract
                let strength = 1.0 - depth * 0.7

                // Floyd-Steinberg diffusion kernel
                let diffR = errR * strength
                let diffG = errG * strength
                let diffB = errB * strength

                // Right: (x+1, y) weight 7/16
                if x + 1 < w {
                    let j = i + 1
                    errorR[j] += diffR * 7.0 / 16.0
                    errorG[j] += diffG * 7.0 / 16.0
                    errorB[j] += diffB * 7.0 / 16.0
                }
                // Below-left: (x-1, y+1) weight 3/16
                if x > 0 && y + 1 < w {
                    let j = (y + 1) * w + (x - 1)
                    errorR[j] += diffR * 3.0 / 16.0
                    errorG[j] += diffG * 3.0 / 16.0
                    errorB[j] += diffB * 3.0 / 16.0
                }
                // Below: (x, y+1) weight 5/16
                if y + 1 < w {
                    let j = (y + 1) * w + x
                    errorR[j] += diffR * 5.0 / 16.0
                    errorG[j] += diffG * 5.0 / 16.0
                    errorB[j] += diffB * 5.0 / 16.0
                }
                // Below-right: (x+1, y+1) weight 1/16
                if x + 1 < w && y + 1 < w {
                    let j = (y + 1) * w + (x + 1)
                    errorR[j] += diffR * 1.0 / 16.0
                    errorG[j] += diffG * 1.0 / 16.0
                    errorB[j] += diffB * 1.0 / 16.0
                }
            }
        }

        // ════════════════════════════════════════════
        // Stage 2: Distribution-exact epoch assignment
        // ════════════════════════════════════════════

        struct PixelInfo {
            let pixelIndex: Int
            let a: Int, b: Int, c: Int
            let depth: Float
        }

        // Build pixel groups from dithered (a,b,c) values
        var groups = [Int: [PixelInfo]]()
        for i in 0..<n {
            let a = quantA[i], b = quantB[i], c = quantC[i]
            let depth = i < depths.count ? depths[i] : Float(0.5)
            let key = a * 16 + b * 4 + c
            groups[key, default: []].append(
                PixelInfo(pixelIndex: i, a: a, b: b, c: c, depth: depth)
            )
        }

        // Assign epochs per group
        var result = [UInt8](repeating: 0, count: n)

        for (_, group) in groups {
            guard !group.isEmpty else { continue }
            let a = group[0].a, b = group[0].b, c = group[0].c
            let groupN = group.count

            let avgDepth = group.reduce(Float(0)) { $0 + $1.depth } / Float(groupN)
            let sigma = BinomialCadence.sigmaForDepth(avgDepth)
            let probs = BinomialCadence.gaussianProbs(frame: z, sigma: sigma)
            let targets = largestRemainder(total: groupN, weights: probs)

            let sorted = group.sorted { $0.depth > $1.depth }
            let epochOrder = (0..<4).sorted { targets[$0] > targets[$1] }

            var offset = 0
            for epochIdx in epochOrder {
                let count = targets[epochIdx]
                for j in offset..<(offset + count) {
                    guard j < sorted.count else { break }
                    let px = sorted[j]
                    result[px.pixelIndex] = UInt8(epochIdx * 64 + a * 16 + b * 4 + c)
                }
                offset += count
            }
        }

        return result
    }

    // MARK: - Largest Remainder Method

    /// Distribute `total` items across 4 bins proportional to `weights`,
    /// ensuring exact sum via largest-remainder rounding.
    private static func largestRemainder(total: Int, weights: SIMD4<Float>) -> [Int] {
        // Compute ideal (fractional) counts
        let ideal = (0..<4).map { Double(weights[$0]) * Double(total) }

        // Floor each
        var result = ideal.map { Int($0) }
        var remainders = (0..<4).map { ideal[$0] - Double(result[$0]) }

        // Distribute leftover to bins with largest remainders
        var leftover = total - result.reduce(0, +)
        while leftover > 0 {
            if let maxIdx = remainders.enumerated().max(by: { $0.element < $1.element })?.offset {
                result[maxIdx] += 1
                remainders[maxIdx] = -1  // don't pick again
                leftover -= 1
            } else {
                break
            }
        }

        return result
    }

    // MARK: - Subject Analysis

    /// Measure how depth separates subject from background.
    /// Does not change quantization — only observes the depth field.
    static func analyzeSubject(depths: [Float]) -> SubjectAnalysis {
        var subCount = 0, bgCount = 0, borderCount = 0
        var subSum: Float = 0, bgSum: Float = 0

        for d in depths {
            if d > 0.6 {
                subCount += 1; subSum += d
            } else if d < 0.4 {
                bgCount += 1; bgSum += d
            } else {
                borderCount += 1
            }
        }

        let subMean = subCount > 0 ? subSum / Float(subCount) : 0.5
        let bgMean = bgCount > 0 ? bgSum / Float(bgCount) : 0.5
        let subSigma = BinomialCadence.sigmaForDepth(subMean)
        let bgSigma = BinomialCadence.sigmaForDepth(bgMean)

        return SubjectAnalysis(
            subjectPixelCount: subCount,
            backgroundPixelCount: bgCount,
            borderPixelCount: borderCount,
            subjectMeanDepth: subMean,
            backgroundMeanDepth: bgMean,
            subjectSigma: subSigma,
            backgroundSigma: bgSigma,
            resolutionRatio: bgSigma / max(subSigma, 0.001)
        )
    }

    // MARK: - Anchor Tracking

    /// Find the singular black and white pixels at the distribution tails.
    /// Black = (a=0, b=0, c=0), White = (a=3, b=3, c=3).
    /// These cap the ends of the binomial distribution.
    static func findAnchors(indices: [UInt8]) -> AnchorTrace {
        var blackIdx: Int? = nil, whiteIdx: Int? = nil
        var blackCount = 0, whiteCount = 0

        for (i, idx) in indices.enumerated() {
            let abc = idx % 64  // strip epoch
            if abc == 0 {  // (a=0, b=0, c=0) = black
                blackCount += 1
                if blackIdx == nil { blackIdx = i }
            }
            if abc == 63 {  // (a=3, b=3, c=3) = white
                whiteCount += 1
                if whiteIdx == nil { whiteIdx = i }
            }
        }

        return AnchorTrace(
            blackPixelIndex: blackIdx,
            blackPaletteIndex: blackIdx.map { indices[$0] },
            blackEpoch: blackIdx.map { indices[$0] / 64 },
            whitePixelIndex: whiteIdx,
            whitePaletteIndex: whiteIdx.map { indices[$0] },
            whiteEpoch: whiteIdx.map { indices[$0] / 64 },
            blackCount: blackCount,
            whiteCount: whiteCount
        )
    }

    // MARK: - Gaussian Probability (matches BinomialCadence)

    private static func gaussianProbs(frame z: Int, sigma: Float) -> SIMD4<Float> {
        return BinomialCadence.gaussianProbs(frame: z, sigma: sigma)
    }
}

// MARK: - Analysis Structs

/// Depth-based subject/background separation measurement.
struct SubjectAnalysis {
    let subjectPixelCount: Int       // depth > 0.6 (near, face)
    let backgroundPixelCount: Int    // depth < 0.4 (far, wall)
    let borderPixelCount: Int        // 0.4...0.6 (transition)
    let subjectMeanDepth: Float
    let backgroundMeanDepth: Float
    let subjectSigma: Float          // σ for subject (should be ≈ 7.875)
    let backgroundSigma: Float       // σ for background (should be ≈ 15.75)
    let resolutionRatio: Float       // backgroundSigma / subjectSigma (≈ 2.0)
}

/// Tracks the singular black and white pixels at the binomial distribution tails.
/// These are temporal anchors: their epoch traces the Gaussian cadence across frames.
struct AnchorTrace {
    let blackPixelIndex: Int?        // position in 64×64 grid
    let blackPaletteIndex: UInt8?    // palette slot (encodes epoch)
    let blackEpoch: UInt8?           // d = index / 64
    let whitePixelIndex: Int?
    let whitePaletteIndex: UInt8?
    let whiteEpoch: UInt8?
    let blackCount: Int              // pixels quantized to black (≈1 at tail)
    let whiteCount: Int              // pixels quantized to white (≈1 at tail)
}
