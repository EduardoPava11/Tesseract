// Decision.swift
// Tesseract
//
// Port of spec/algebra/Decision.hs:
// How a histogram becomes a pixel decision.
//
// P(Level k | h) = sum of mass in level k's bin range.
// Decision = argmax. Confidence = max P. Dither = 1 - confidence.
// R, G, B are independent — each channel dithered by its own confidence.
// Global weight g = mean(conf_R, conf_G, conf_B).
// Depth CONFIRMS what the histogram SHOWS.

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. LEVEL ← BIN MAPPING
// ════════════════════════════════════════════════════════════════

/// Which histogram bins belong to which tesseract level.
/// Level 0: bins 0-3   (4 bins, dark)
/// Level 1: bins 4-6   (3 bins)
/// Level 2: bins 7-10  (4 bins)
/// Level 3: bins 11-13 (3 bins, bright)
enum LevelBins {
    static let ranges: [[Int]] = [
        [0, 1, 2, 3],       // Level 0
        [4, 5, 6],           // Level 1
        [7, 8, 9, 10],       // Level 2
        [11, 12, 13]          // Level 3
    ]
}

// ════════════════════════════════════════════════════════════════
// § 2. HISTOGRAM → LEVEL PROBABILITIES
// ════════════════════════════════════════════════════════════════

extension CountedHist {

    /// P(Level k | histogram) for k ∈ {0,1,2,3}
    /// Sum of frequency mass in each level's bin range.
    /// This is a projection from 14D histogram → 4D level space.
    func levelProbabilities() -> (Float, Float, Float, Float) {
        var p = [Float](repeating: 0, count: 4)
        for (lv, range) in LevelBins.ranges.enumerated() {
            for bin in range {
                if bin < bins.count {
                    p[lv] += bins[bin]
                }
            }
        }
        return (p[0], p[1], p[2], p[3])
    }

    /// The decided level: argmax P(Level k)
    var decidedLevel: Int {
        let (p0, p1, p2, p3) = levelProbabilities()
        let probs = [p0, p1, p2, p3]
        return probs.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
    }

    /// Confidence: P(decided level) ∈ [0.25, 1.0]
    /// 1.0 = all mass in one level (sharp peak).
    /// 0.25 = uniform (maximum uncertainty for 4 levels).
    var levelConfidence: Float {
        let (p0, p1, p2, p3) = levelProbabilities()
        return max(p0, p1, p2, p3)
    }

    /// Dithering budget: 1 - confidence ∈ [0, 0.75]
    /// How much of this channel's quantization error to diffuse.
    var ditherBudget: Float {
        1.0 - levelConfidence
    }

    /// Is the confidence statistically significant?
    /// True if confidence > 1/4 + 2×SE (2σ above uniform chance).
    var isSignificant: Bool {
        let p = levelConfidence
        guard n > 1 else { return false }
        let se = sqrt(p * (1 - p) / Float(n))
        return p > 0.25 + 2 * se
    }
}

// ════════════════════════════════════════════════════════════════
// § 3. PER-CHANNEL DECISION
// ════════════════════════════════════════════════════════════════

/// Decision for one color channel: level + confidence + dither budget.
struct ChannelDecision {
    let level: Int           // {0,1,2,3}
    let confidence: Float    // P(decided level) ∈ [0.25, 1.0]
    let ditherBudget: Float  // 1 - confidence ∈ [0, 0.75]
    let isSignificant: Bool  // statistically meaningful?

    init(from hist: CountedHist) {
        self.level = hist.decidedLevel
        self.confidence = hist.levelConfidence
        self.ditherBudget = hist.ditherBudget
        self.isSignificant = hist.isSignificant
    }
}

// ════════════════════════════════════════════════════════════════
// § 4. THREE-CHANNEL BLOCK DECISION
// ════════════════════════════════════════════════════════════════

/// Complete decision for one block: R + G + B channels + epoch + global weight.
/// Each channel decided independently. Global weight = mean confidence.
struct BlockDecision {
    let r: ChannelDecision
    let g: ChannelDecision
    let b: ChannelDecision
    let epoch: Int           // d ∈ {0,1,2,3}
    let globalWeight: Float  // mean(conf_R, conf_G, conf_B)

    /// Palette index: d×64 + a×16 + b×4 + c
    var paletteIndex: UInt8 {
        UInt8(epoch * 64 + r.level * 16 + g.level * 4 + b.level)
    }

    /// Per-channel dither budgets (for Floyd-Steinberg)
    var ditherR: Float { r.ditherBudget }
    var ditherG: Float { g.ditherBudget }
    var ditherB: Float { b.ditherBudget }

    init(histR: CountedHist, histG: CountedHist, histB: CountedHist, epoch: Int) {
        self.r = ChannelDecision(from: histR)
        self.g = ChannelDecision(from: histG)
        self.b = ChannelDecision(from: histB)
        self.epoch = epoch
        self.globalWeight = (self.r.confidence + self.g.confidence + self.b.confidence) / 3.0
    }
}

// ════════════════════════════════════════════════════════════════
// § 5. TEACHER GLOBAL WEIGHT: blends confidence + depth
// ════════════════════════════════════════════════════════════════

/// Teacher's global weight: α × histogram_confidence + (1-α) × depth.
/// The NN learns to approximate (and potentially improve) this.
enum TeacherDecision {
    static let alpha: Float = 0.5

    static func globalWeight(histConfidence: Float, depth: Float) -> Float {
        alpha * histConfidence + (1 - alpha) * depth
    }
}

// ════════════════════════════════════════════════════════════════
// § 6. BUILD HISTOGRAM FROM CAMERA PIXELS
//
// This is the missing link: raw camera pixels → CountedHist.
// For each output block at position (x,y), sample the step×step
// patch from the 768×768 crop and bin each channel into 14 bins.
// ════════════════════════════════════════════════════════════════

extension CountedHist {

    /// Build a 14-bin histogram from a slice of channel values.
    /// Values in [0,1]. Bin i covers [i/14, (i+1)/14).
    static func fromValues(_ values: [Float]) -> CountedHist {
        var counts = [Int](repeating: 0, count: numBins)
        for v in values {
            let bin = min(numBins - 1, max(0, Int(v * Float(numBins))))
            counts[bin] += 1
        }
        return fromCounts(counts)
    }
}

/// Build the full 3-channel block decision from a pyramid + depth + frame.
/// Uses the histogram at the native scale for the given mode:
///   Training → Coarse (12×12), Inference → Medium (6×6)
extension BlockPyramid {

    /// Select the histogram at the native scale for this mode
    private func nativeHist(_ ch: ChannelPyramid, mode: CubeMode) -> CountedHist {
        switch mode {
        case .training:  return ch.coarse
        case .inference: return ch.medium
        }
    }

    /// Make a BlockDecision using the native-scale histograms.
    func decide(mode: CubeMode, epoch: Int) -> BlockDecision {
        BlockDecision(
            histR: nativeHist(r, mode: mode),
            histG: nativeHist(g, mode: mode),
            histB: nativeHist(b, mode: mode),
            epoch: epoch
        )
    }

    /// Teacher's global weight for this block.
    func teacherGlobal(mode: CubeMode) -> Float {
        let histConf = (nativeHist(r, mode: mode).levelConfidence
                      + nativeHist(g, mode: mode).levelConfidence
                      + nativeHist(b, mode: mode).levelConfidence) / 3.0
        return TeacherDecision.globalWeight(histConfidence: histConf, depth: depth)
    }
}
