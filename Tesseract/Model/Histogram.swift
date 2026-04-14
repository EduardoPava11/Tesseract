// Histogram.swift
// Tesseract
//
// Per-block constructive histograms. Matches Haskell: TesseractAxes.hs
//
// 19×19 → 3 histograms is CONSTRUCTIVE (not destructive).
// Each histogram has 14 bins (one per fine-grained color level).
// The histogram IS the probability distribution for that block's
// output pixel level assignment.

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. CHANNEL HISTOGRAM: 14 bins for one color channel
//
// Haskell: type Hist14 = [Int]
// ════════════════════════════════════════════════════════════════

/// Per-channel histogram with 14 fine-grained bins.
/// Constructed from a square block of source pixels.
struct ChannelHist {
    /// Pixel count per bin (14 elements)
    let counts: [Int]

    /// Total pixels in the block (= step²)
    let total: Int

    /// Probability distribution [0,1] per bin
    var probabilities: [Float] {
        let t = Float(max(1, total))
        return counts.map { Float($0) / t }
    }

    /// Which bins have at least one pixel?
    var availableBins: [Int] {
        counts.enumerated().compactMap { $0.element > 0 ? $0.offset : nil }
    }

    /// Bin with the most pixels (strongest signal)
    var strongestBin: Int {
        counts.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
    }

    /// Create from an array of continuous values [0,1]
    static func from(values: [Float]) -> ChannelHist {
        var bins = [Int](repeating: 0, count: BinTarget.numBins)
        for v in values {
            let b = valueToBin(v)
            bins[b] += 1
        }
        return ChannelHist(counts: bins, total: values.count)
    }
}

// ════════════════════════════════════════════════════════════════
// § 2. BLOCK HISTOGRAM: 3 independent channel histograms
//
// Haskell: data BlockHist = BlockHist !Hist14 !Hist14 !Hist14 !Int
// ════════════════════════════════════════════════════════════════

/// Three independent per-channel histograms for one square block.
/// The channels are orthogonal: R histogram computed from R values only.
struct BlockHist {
    let r: ChannelHist
    let g: ChannelHist
    let b: ChannelHist

    /// Side length of the square block (step)
    let blockSide: Int

    /// Total pixels (step × step)
    var blockSize: Int { blockSide * blockSide }

    /// Create from an array of RGB pixels
    static func from(pixels: [(Float, Float, Float)], blockSide: Int) -> BlockHist {
        let rValues = pixels.map(\.0)
        let gValues = pixels.map(\.1)
        let bValues = pixels.map(\.2)
        return BlockHist(
            r: ChannelHist.from(values: rValues),
            g: ChannelHist.from(values: gValues),
            b: ChannelHist.from(values: bValues),
            blockSide: blockSide
        )
    }
}

// ════════════════════════════════════════════════════════════════
// § 3. BIN ASSIGNMENT: Match block supply to global demand
//
// For each channel independently:
//   1. Global demand = BinTarget.scaled(to: 4096)
//   2. Each block's histogram says which bins are available
//   3. Assign the bin that best fills unmet demand
//   4. Across 4096 pixels, aggregate matches target
// ════════════════════════════════════════════════════════════════

/// Assign bins for one channel across all output pixels.
/// Each pixel has a per-block histogram. Returns one bin index per pixel.
func assignBinsForChannel(_ blockHists: [ChannelHist]) -> [Int] {
    let n = blockHists.count
    var demand = BinTarget.scaled(to: n)
    var result = [Int]()
    result.reserveCapacity(n)

    for hist in blockHists {
        // Score each bin: available count × remaining demand
        var bestBin = hist.strongestBin
        var bestScore: Float = 0

        for b in 0..<BinTarget.numBins {
            if demand[b] > 0 && hist.counts[b] > 0 {
                let score = Float(hist.counts[b]) * Float(demand[b])
                if score > bestScore {
                    bestScore = score
                    bestBin = b
                }
            }
        }

        result.append(bestBin)
        demand[bestBin] = max(0, demand[bestBin] - 1)
    }

    return result
}

/// Assign all 3 channels independently → ComposedColor per pixel.
func assignAllChannels(_ blockHists: [BlockHist]) -> [ComposedColor] {
    let rBins = assignBinsForChannel(blockHists.map(\.r))
    let gBins = assignBinsForChannel(blockHists.map(\.g))
    let bBins = assignBinsForChannel(blockHists.map(\.b))

    return zip(rBins, zip(gBins, bBins)).map { (r, gb) in
        ComposedColor(r: RBin(value: r), g: GBin(value: gb.0), b: BBin(value: gb.1))
    }
}
