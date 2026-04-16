// EntropyMeasure.swift
// Tesseract
//
// Port of Gene.hs §5: compute entropy feedback from palette distribution.
// 5 values: H(d), H(a), H(b), H(c), H(d,a,b,c) — all normalized to [0,1].
//
// High entropy = palette well-used = rich expression.
// Low entropy = palette collapsed = gene is failing.
// Feeds back into the Gene NN as input slots [132..136].

import Foundation

struct EntropyMeasure {

    /// Compute entropy feedback from a frame's palette indices.
    /// Returns 5 normalized entropy values ∈ [0,1].
    ///
    /// Matches Gene.hs: `computeEntropy :: Map Int Int -> Int -> EntropyFeedback`
    static func compute(paletteIndices: [UInt8]) -> EntropyFeedback {
        let total = Float(max(1, paletteIndices.count))

        // Count marginals
        var epochCounts = [Int](repeating: 0, count: 4)
        var rCounts = [Int](repeating: 0, count: 4)
        var gCounts = [Int](repeating: 0, count: 4)
        var bCounts = [Int](repeating: 0, count: 4)
        var jointCounts = [Int](repeating: 0, count: 256)

        for idx in paletteIndices {
            let i = Int(idx)
            let d = i / 64
            let a = (i % 64) / 16
            let b = (i % 16) / 4
            let c = i % 4
            epochCounts[d] += 1
            rCounts[a] += 1
            gCounts[b] += 1
            bCounts[c] += 1
            jointCounts[i] += 1
        }

        return EntropyFeedback(
            epoch: shannonNormalized(epochCounts, total: total, maxBins: 4),
            r:     shannonNormalized(rCounts, total: total, maxBins: 4),
            g:     shannonNormalized(gCounts, total: total, maxBins: 4),
            b:     shannonNormalized(bCounts, total: total, maxBins: 4),
            joint: shannonNormalized(jointCounts, total: total, maxBins: 256)
        )
    }

    /// Compute from ALL frames combined (for the organism-level entropy)
    static func computeOverall(frames: [[UInt8]]) -> EntropyFeedback {
        let all = frames.flatMap { $0 }
        return compute(paletteIndices: all)
    }

    /// Shannon entropy normalized by log(maxBins) → [0,1]
    private static func shannonNormalized(_ counts: [Int], total: Float, maxBins: Int) -> Float {
        var h: Float = 0
        for c in counts where c > 0 {
            let p = Float(c) / total
            h -= p * log(p)
        }
        let hMax = log(Float(maxBins))
        return hMax > 0 ? min(1.0, h / hMax) : 0
    }
}
