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
