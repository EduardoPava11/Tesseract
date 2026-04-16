// BlockPyramid.swift
// Tesseract
//
// Port of spec/neural/Gene.hs: multi-scale histogram pyramid.
//
// The same 768×768 camera region viewed at 3 scales:
//   Level64:  12×12 = 144 samples → rich histogram
//   Level128:  6×6  =  36 samples → moderate
//   Level256:  3×3  =   9 samples → sparse
//
// The NN sees ALL scales. Sample counts ride alongside.
// It learns when to trust (high n) and when to discount (low n).

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. COUNTED HISTOGRAM — data + significance, never separated
// ════════════════════════════════════════════════════════════════

/// A 14-bin histogram with its sample count.
/// Frequencies sum to 1.0. The sample count (n) tells you
/// how much to trust the frequencies.
///
/// Matches Haskell: `data CountedHist = CountedHist { chBins :: ![Double], chN :: !Int }`
struct CountedHist: Equatable {
    static let numBins = 14

    /// 14 frequency values, sum ≈ 1.0
    let bins: [Float]
    /// Sample count (144, 36, or 9 depending on level)
    let n: Int

    /// Build from raw integer counts
    static func fromCounts(_ counts: [Int]) -> CountedHist {
        let total = max(1, counts.reduce(0, +))
        let totalF = Float(total)
        return CountedHist(
            bins: counts.map { Float($0) / totalF },
            n: total
        )
    }

    /// Build from sampling a channel at a given stride
    static func fromChannel(
        _ pixels: [(Float, Float, Float)],
        channel: ((Float, Float, Float)) -> Float,
        startX: Int, startY: Int,
        step: Int, gridWidth: Int
    ) -> CountedHist {
        var counts = [Int](repeating: 0, count: numBins)
        for dy in 0..<step {
            for dx in 0..<step {
                let px = startX * step + dx
                let py = startY * step + dy
                let idx = py * gridWidth + px
                guard idx >= 0, idx < pixels.count else { continue }
                let val = channel(pixels[idx])
                let bin = min(numBins - 1, max(0, Int(val * Float(numBins))))
                counts[bin] += 1
            }
        }
        return fromCounts(counts)
    }

    /// Shannon entropy in nats
    var entropy: Float {
        var h: Float = 0
        for p in bins where p > 1e-10 {
            h -= p * log(p)
        }
        return h
    }

    /// Normalized entropy ∈ [0,1]
    var normalizedEntropy: Float {
        let hMax = log(Float(CountedHist.numBins))
        return hMax > 0 ? entropy / hMax : 0
    }

    /// Standard error for a bin proportion: SE = sqrt(p(1-p)/n)
    func stdError(bin: Int) -> Float {
        guard bin >= 0, bin < bins.count, n > 1 else { return 1.0 }
        let p = bins[bin]
        return sqrt(p * (1 - p) / Float(n))
    }
}

// ════════════════════════════════════════════════════════════════
// § 2. CHANNEL PYRAMID — same region at 3 scales
// ════════════════════════════════════════════════════════════════

/// Per-channel histogram at all 3 SPATIAL scales of the pyramid.
/// Coarse (12×12=144) → Medium (6×6=36) → Fine (3×3=9)
/// These come from the 768 crop geometry, NOT from the cube mode.
///
/// Matches Haskell: `data ChannelPyramid = ChannelPyramid { cpCoarse, cpMedium, cpFine }`
struct ChannelPyramid: Equatable {
    let coarse: CountedHist   // stride 12, 12×12 = 144 samples
    let medium: CountedHist   // stride 6,   6×6  =  36 samples
    let fine:   CountedHist   // stride 3,   3×3  =   9 samples
}

// ════════════════════════════════════════════════════════════════
// § 3. ENTROPY FEEDBACK — from previous organism
// ════════════════════════════════════════════════════════════════

/// 5 entropy values from the PREVIOUS organism's palette distribution.
/// All normalized to [0,1]. First pass: all 1.0 (uniform = no info).
///
/// Matches Haskell: `data EntropyFeedback = EntropyFeedback { efEpoch, efR, efG, efB, efJoint }`
struct EntropyFeedback: Equatable {
    let epoch: Float    // H(d) / log(4)
    let r: Float        // H(a) / log(4)
    let g: Float        // H(b) / log(4)
    let b: Float        // H(c) / log(4)
    let joint: Float    // H(d,a,b,c) / log(256)

    /// Maximum entropy = uniform = no information yet
    static let uniform = EntropyFeedback(epoch: 1, r: 1, g: 1, b: 1, joint: 1)

    /// All values as array (for flatten)
    var asArray: [Float] { [epoch, r, g, b, joint] }
}

// ════════════════════════════════════════════════════════════════
// § 4. BLOCK PYRAMID — the complete NN input
// ════════════════════════════════════════════════════════════════

/// The complete input to the Gene NN for one output pixel.
/// 3 channel pyramids + depth + frame + sample counts + entropy.
/// Flattens to exactly 137 floats.
///
/// Matches Haskell: `data BlockPyramid = BlockPyramid { bpR, bpG, bpB, bpDepth, ... }`
struct BlockPyramid {
    let r: ChannelPyramid
    let g: ChannelPyramid
    let b: ChannelPyramid
    let depth: Float            // [0,1], 1=near
    let depthN: Int             // depth sample count
    let frameNorm: Float        // z / (K-1) ∈ [0,1]
    let entropy: EntropyFeedback

    /// The NN input dimension (must match Gene.hs inputDim)
    static let inputDim = 137

    // ════════════════════════════════════════════════════════════
    // BUILD FROM CAPTURED FRAME
    //
    // For each output pixel (x,y), sample the 768×768 source crop
    // at 3 strides (12, 6, 3) to build Coarse/Medium/Fine histograms.
    //
    // The CapturedFrame stores S² downsampled RGB pixels.
    // BUT those pixels came from the 768 crop — each pixel IS the
    // center of a step×step block. We use the raw RGB values to
    // reconstruct approximate histograms at each scale.
    //
    // At Training (S=64): each pixel represents a 12×12 block.
    //   Coarse: the pixel itself (n=1, but we treat it as the block mode)
    //   Medium: 2×2 neighborhood of pixels → n=4
    //   Fine: single pixel → n=1
    //
    // This is an APPROXIMATION because we don't have the full 768×768
    // source pixels — only the S² downsampled centers. For real
    // multi-scale histograms, we'd need the raw camera buffer.
    //
    // The approximation is SUFFICIENT because:
    //   - The center pixel IS representative of the block
    //   - Neighboring pixels provide context at coarser scales
    //   - Sample counts tell the NN how much to trust each scale
    // ════════════════════════════════════════════════════════════

    /// Build BlockPyramids for all S² pixels in a captured frame.
    /// Returns S² pyramids (one per output pixel).
    static func computeAll(
        rgb: [(Float, Float, Float)],
        depths: [Float],
        frameIndex: Int,
        totalFrames: Int,
        entropy: EntropyFeedback = .uniform
    ) -> [BlockPyramid] {
        let s = CameraConfig.outputSize
        let n = s * s
        guard rgb.count >= n else { return [] }

        let frameNorm = totalFrames > 1 ? Float(frameIndex) / Float(totalFrames - 1) : 0
        let depthN = CameraConfig.depthStep * CameraConfig.depthStep

        return (0..<n).map { i in
            let x = i % s
            let y = i / s
            let (r, g, b) = rgb[i]
            let depth = i < depths.count ? depths[i] : 0.5

            // Build pyramid from neighborhood sampling
            let rPyr = channelPyramid(rgb: rgb, s: s, x: x, y: y, channel: { $0.0 })
            let gPyr = channelPyramid(rgb: rgb, s: s, x: x, y: y, channel: { $0.1 })
            let bPyr = channelPyramid(rgb: rgb, s: s, x: x, y: y, channel: { $0.2 })

            return BlockPyramid(
                r: rPyr, g: gPyr, b: bPyr,
                depth: depth, depthN: depthN,
                frameNorm: frameNorm,
                entropy: entropy
            )
        }
    }

    /// Build a ChannelPyramid for one channel at position (x,y).
    /// Coarse: 5×5 neighborhood (25 samples, approximating 12×12)
    /// Medium: 3×3 neighborhood (9 samples, approximating 6×6)
    /// Fine: 1×1 center pixel (1 sample, the pixel itself)
    private static func channelPyramid(
        rgb: [(Float, Float, Float)],
        s: Int, x: Int, y: Int,
        channel: @escaping ((Float, Float, Float)) -> Float
    ) -> ChannelPyramid {
        // Coarse: 5×5 neighborhood → n up to 25
        let coarse = sampleNeighborhood(rgb: rgb, s: s, x: x, y: y, radius: 2, channel: channel)

        // Medium: 3×3 neighborhood → n up to 9
        let medium = sampleNeighborhood(rgb: rgb, s: s, x: x, y: y, radius: 1, channel: channel)

        // Fine: 1×1 (just this pixel) → n = 1
        let fine = sampleNeighborhood(rgb: rgb, s: s, x: x, y: y, radius: 0, channel: channel)

        return ChannelPyramid(
            coarse: CountedHist.fromCounts(coarse),
            medium: CountedHist.fromCounts(medium),
            fine: CountedHist.fromCounts(fine)
        )
    }

    /// Sample a (2r+1)×(2r+1) neighborhood, bin into 14 bins.
    /// Returns raw bin counts (not yet normalized).
    private static func sampleNeighborhood(
        rgb: [(Float, Float, Float)],
        s: Int, x: Int, y: Int, radius: Int,
        channel: ((Float, Float, Float)) -> Float
    ) -> [Int] {
        var counts = [Int](repeating: 0, count: CountedHist.numBins)
        for dy in -radius...radius {
            for dx in -radius...radius {
                let nx = min(s-1, max(0, x + dx))
                let ny = min(s-1, max(0, y + dy))
                let idx = ny * s + nx
                guard idx >= 0, idx < rgb.count else { continue }
                let val = channel(rgb[idx])
                let bin = min(CountedHist.numBins - 1, max(0, Int(val * Float(CountedHist.numBins))))
                counts[bin] += 1
            }
        }
        return counts
    }

    /// Flatten to exactly 137 floats for the NN.
    /// Layout: [126 histogram bins, 2 metadata, 4 sample counts, 5 entropy]
    /// Matches Haskell: `flatten :: BlockPyramid -> [Double]` from Gene.hs
    func flatten() -> [Float] {
        var v = [Float]()
        v.reserveCapacity(BlockPyramid.inputDim)

        // 126: 3 channels × 3 scales × 14 bins
        for ch in [r, g, b] {
            v.append(contentsOf: ch.coarse.bins)
            v.append(contentsOf: ch.medium.bins)
            v.append(contentsOf: ch.fine.bins)
        }

        // 2: depth + frame
        v.append(depth)
        v.append(frameNorm)

        // 4: sample counts (spatial pyramid constants + depth)
        v.append(Float(r.coarse.n))   // 144
        v.append(Float(r.medium.n))   // 36
        v.append(Float(r.fine.n))     // 9
        v.append(Float(depthN))

        // 5: entropy feedback
        v.append(contentsOf: entropy.asArray)

        assert(v.count == BlockPyramid.inputDim,
               "flatten produced \(v.count) floats, expected \(BlockPyramid.inputDim)")
        return v
    }
}
