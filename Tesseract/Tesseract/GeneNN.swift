// GeneNN.swift
// Tesseract
//
// Port of spec/neural/Gene.hs: gene weights + perturbation.
//
// ATTENTION (4416 params): InputEncoder — user-trained via swipes.
// CORE (165 params): OutputHead — species identity, frozen on iPhone.
// TOTAL: 4581 floats → 4.5 KB gene capsule (Int8).
//
// Output 5: (d,a,b,c) tesseract + g global/local weight.
//   g=1 → global palette entry (stable across epochs, face)
//   g=0 → local palette entry (epoch-specific, background)

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. GENE WEIGHTS
// ════════════════════════════════════════════════════════════════

/// Gene NN weights: ATTENTION (W1, b1) + CORE (W2, b2).
/// Flat array of 4548 floats matching Gene.metal layout:
///   [0..4383]    W1: 32 × 137
///   [4384..4415] b1: 32
///   [4416..4543] W2: 4 × 32
///   [4544..4547] b2: 4
struct GeneWeights: Equatable {
    static let inputDim = 137
    static let hiddenDim = 32
    static let outputDim = 5  // (d, a, b, c, g)

    static let attentionCount = hiddenDim * inputDim + hiddenDim  // 4416
    static let coreCount = outputDim * hiddenDim + outputDim       // 165
    static let totalCount = attentionCount + coreCount              // 4581

    /// Flat weight array (matches Gene.metal buffer layout)
    var weights: [Float]

    init(weights: [Float]) {
        assert(weights.count == GeneWeights.totalCount,
               "GeneWeights requires \(GeneWeights.totalCount) floats, got \(weights.count)")
        self.weights = weights
    }

    /// ATTENTION slice (first 4416 floats): W1 + b1
    var attention: ArraySlice<Float> {
        weights[0..<GeneWeights.attentionCount]
    }

    /// CORE slice (last 132 floats): W2 + b2
    var core: ArraySlice<Float> {
        weights[GeneWeights.attentionCount..<GeneWeights.totalCount]
    }
}

// ════════════════════════════════════════════════════════════════
// § 2. DEFAULT WEIGHTS — approximates the teacher
// ════════════════════════════════════════════════════════════════

extension GeneWeights {

    /// Default (untrained) weights: small random values.
    /// In practice, should be initialized to approximate the
    /// algebraic teacher (PerfectQuantizer).
    static func defaultWeights() -> GeneWeights {
        var w = [Float](repeating: 0, count: totalCount)
        // Xavier initialization: scale = sqrt(2 / fan_in)
        let scale1 = sqrt(2.0 / Float(inputDim))
        let scale2 = sqrt(2.0 / Float(hiddenDim))
        // Deterministic pseudo-random (matches Gene.hs syntheticGene)
        for i in 0..<(hiddenDim * inputDim) {
            w[i] = scale1 * sin(Float(i) * 0.01)
        }
        // b1 = zero
        let w2Start = attentionCount
        for i in 0..<(outputDim * hiddenDim) {
            w[w2Start + i] = scale2 * cos(Float(i) * 0.01)
        }
        // b2 = zero
        return GeneWeights(weights: w)
    }
}

// ════════════════════════════════════════════════════════════════
// § 3. PERTURBATION — swipe LEFT adds noise to ATTENTION only
// ════════════════════════════════════════════════════════════════

extension GeneWeights {

    /// Perturb ATTENTION weights with SGLD-style noise.
    /// CORE weights are untouched (species identity preserved).
    ///
    /// Matches Gene.hs: `applySignal SwipeLeft`
    func perturbed(scale: Float = 0.01, seed: UInt32 = 0) -> GeneWeights {
        var newWeights = weights
        // Only perturb ATTENTION (first 4416 floats)
        var hash = seed
        for i in 0..<GeneWeights.attentionCount {
            // Simple hash-based noise (deterministic given seed)
            hash = hash &* 2246822519 &+ 374761393
            let noise = Float(Int32(bitPattern: hash)) / Float(Int32.max)
            newWeights[i] += scale * noise
        }
        return GeneWeights(weights: newWeights)
    }

    /// Check if CORE weights match another gene (same species)
    func coreMatches(_ other: GeneWeights) -> Bool {
        for i in GeneWeights.attentionCount..<GeneWeights.totalCount {
            if weights[i] != other.weights[i] { return false }
        }
        return true
    }
}

// ════════════════════════════════════════════════════════════════
// § 4. CPU FORWARD PASS (for testing, matches Gene.metal exactly)
// ════════════════════════════════════════════════════════════════

extension GeneWeights {

    /// CPU forward pass: input → (palette index, global weight).
    /// Must produce identical output to Gene.metal geneForward kernel.
    func forward(_ input: [Float]) -> (index: UInt8, globalWeight: Float) {
        assert(input.count == GeneWeights.inputDim,
               "forward expects \(GeneWeights.inputDim) floats, got \(input.count)")

        // Layer 1: W1 × input + b1 → ReLU
        var hidden = [Float](repeating: 0, count: GeneWeights.hiddenDim)
        let w1Base = 0
        let b1Base = GeneWeights.hiddenDim * GeneWeights.inputDim
        for h in 0..<GeneWeights.hiddenDim {
            var sum = weights[b1Base + h]  // bias
            let wRow = w1Base + h * GeneWeights.inputDim
            for i in 0..<GeneWeights.inputDim {
                sum += weights[wRow + i] * input[i]
            }
            hidden[h] = max(0, sum)  // ReLU
        }

        // Layer 2: W2 × hidden + b2
        let w2Base = GeneWeights.attentionCount
        let b2Base = w2Base + GeneWeights.outputDim * GeneWeights.hiddenDim
        var raw = [Float](repeating: 0, count: GeneWeights.outputDim)
        for o in 0..<GeneWeights.outputDim {
            var sum = weights[b2Base + o]  // bias
            let wRow = w2Base + o * GeneWeights.hiddenDim
            for h in 0..<GeneWeights.hiddenDim {
                sum += weights[wRow + h] * hidden[h]
            }
            raw[o] = sum
        }

        func sigmoid(_ x: Float) -> Float { 1.0 / (1.0 + exp(-x)) }

        // First 4: Sigmoid × 3.999 → floor → {0,1,2,3}
        let d = min(3, UInt8(sigmoid(raw[0]) * 3.999))
        let a = min(3, UInt8(sigmoid(raw[1]) * 3.999))
        let b = min(3, UInt8(sigmoid(raw[2]) * 3.999))
        let c = min(3, UInt8(sigmoid(raw[3]) * 3.999))

        // 5th: Sigmoid → [0,1] global/local weight
        let g = sigmoid(raw[4])

        return (d * 64 + a * 16 + b * 4 + c, g)
    }
}

// ════════════════════════════════════════════════════════════════
// § 5. GENE META PARAMS (matches Gene.metal GeneMetaParams)
// ════════════════════════════════════════════════════════════════

/// Per-frame metadata for the Gene kernel.
/// Must match Gene.metal `struct GeneMetaParams` layout exactly.
struct GeneMetaParams {
    var width: UInt32
    var height: UInt32
    var frameNorm: Float
    var nRGB64: Float
    var nRGB128: Float
    var nRGB256: Float
    var nDepth: Float
    var entropyEpoch: Float
    var entropyR: Float
    var entropyG: Float
    var entropyB: Float
    var entropyJoint: Float
    // 48 bytes total (12 × 4)

    static func from(mode: CubeMode, frameIndex: Int, entropy: EntropyFeedback) -> GeneMetaParams {
        let s = UInt32(mode.spatialSide)
        let k = mode.frameCount
        return GeneMetaParams(
            width: s, height: s,
            frameNorm: k > 1 ? Float(frameIndex) / Float(k - 1) : 0,
            nRGB64: 144, nRGB128: 36, nRGB256: 9,
            nDepth: Float(CameraConfig.depthStep * CameraConfig.depthStep),
            entropyEpoch: entropy.epoch,
            entropyR: entropy.r,
            entropyG: entropy.g,
            entropyB: entropy.b,
            entropyJoint: entropy.joint
        )
    }
}
