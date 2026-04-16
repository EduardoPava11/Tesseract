// GeneModule.swift
// Tesseract
//
// The Gene NN as an MLX Module — the Para(C) → MLX mapping.
//
// Para morphism      = MLXNN.Module (has parameters, callable)
// compose (f >>> g)  = Sequential or manual chaining
// CORE (frozen)      = core.freeze()
// ATTENTION (train)  = attention.unfreeze()
// Learner            = valueAndGrad(model:)
//
// Architecture: attention(137→32) >>> relu >>> core(32→5) >>> tanh
// Output: 5 direction values ∈ [-1, 1] for the residual δ
//
// The MONOID structure:
//   Identity: weights = 0 → tanh(0) = 0 → δ = 0 → teacher unchanged
//   Composition: two GeneModules compose by weight addition
//   The gene capsule IS the monoid element.

#if canImport(MLX)
import MLX
import MLXNN
import MLXOptimizers
#endif

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. THE MLX MODULE
// ════════════════════════════════════════════════════════════════

#if canImport(MLX)

/// The Gene NN as a proper MLX Module.
/// Para composition: attention >>> relu >>> core >>> tanh
///
/// ATTENTION (4416 params): Linear(137→32) + bias(32)
///   The user's trained perception. Trainable on iPhone via gestures.
///
/// CORE (165 params): Linear(32→5) + bias(5)
///   The species identity. Frozen on iPhone. Shared via gene capsule.
///
/// Output: 5 values in [-1, 1] (direction for residual δ)
///   [0]: epoch direction
///   [1]: R level direction
///   [2]: G level direction
///   [3]: B level direction
///   [4]: global weight direction
class GeneModule: Module, @unchecked Sendable {

    // Para morphism 1: the perception (ATTENTION)
    let attention: Linear    // R^137 → R^32

    // Para morphism 2: the species (CORE)
    let core: Linear         // R^32 → R^5

    override init() {
        attention = Linear(GeneWeights.inputDim, GeneWeights.hiddenDim)
        core = Linear(GeneWeights.hiddenDim, GeneWeights.outputDim)
        super.init()
    }

    /// Para composition: attention >>> relu >>> core >>> tanh
    /// Output: direction ∈ [-1, 1]^5 for the residual correction
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = attention(x)     // R^137 → R^32
        h = MLX.maximum(h, 0)   // ReLU
        let o = core(h)          // R^32 → R^5
        return tanh(o)           // direction ∈ [-1, 1]^5
    }

    // ── CORE/ATTENTION split ──

    /// Freeze CORE: species identity locked during user training
    func freezeCore() {
        core.freeze()
    }

    /// Unfreeze ATTENTION: perception trainable via gestures
    func unfreezeAttention() {
        attention.unfreeze()
    }

    /// Prepare for training: freeze core, unfreeze attention
    func prepareForTraining() {
        freezeCore()
        unfreezeAttention()
    }

    // ── Weight transfer to/from GeneWeights (for capsule encoding) ──

    /// Export flat weights for gene capsule
    func exportWeights() -> GeneWeights {
        var weights = [Float](repeating: 0, count: GeneWeights.totalCount)

        // Attention W1: [32, 137] → flatten row-major
        let w1 = attention.weight.asArray(Float.self)
        for (i, v) in w1.enumerated() where i < GeneWeights.hiddenDim * GeneWeights.inputDim {
            weights[i] = v
        }

        // Attention b1: [32]
        if let b1 = attention.bias?.asArray(Float.self) {
            let b1Start = GeneWeights.hiddenDim * GeneWeights.inputDim
            for (i, v) in b1.enumerated() {
                weights[b1Start + i] = v
            }
        }

        // Core W2: [5, 32]
        let w2 = core.weight.asArray(Float.self)
        let w2Start = GeneWeights.attentionCount
        for (i, v) in w2.enumerated() where i < GeneWeights.outputDim * GeneWeights.hiddenDim {
            weights[w2Start + i] = v
        }

        // Core b2: [5]
        if let b2 = core.bias?.asArray(Float.self) {
            let b2Start = w2Start + GeneWeights.outputDim * GeneWeights.hiddenDim
            for (i, v) in b2.enumerated() {
                weights[b2Start + i] = v
            }
        }

        return GeneWeights(weights: weights)
    }

    /// Import weights from gene capsule
    func importWeights(_ gw: GeneWeights) {
        // W1: [32, 137]
        let w1Data = Array(gw.weights[0..<(GeneWeights.hiddenDim * GeneWeights.inputDim)])
        attention.weight = MLXArray(w1Data).reshaped([GeneWeights.hiddenDim, GeneWeights.inputDim])

        // b1: [32]
        let b1Start = GeneWeights.hiddenDim * GeneWeights.inputDim
        let b1Data = Array(gw.weights[b1Start..<(b1Start + GeneWeights.hiddenDim)])
        attention.bias = MLXArray(b1Data)

        // W2: [5, 32]
        let w2Start = GeneWeights.attentionCount
        let w2Data = Array(gw.weights[w2Start..<(w2Start + GeneWeights.outputDim * GeneWeights.hiddenDim)])
        core.weight = MLXArray(w2Data).reshaped([GeneWeights.outputDim, GeneWeights.hiddenDim])

        // b2: [5]
        let b2Start = w2Start + GeneWeights.outputDim * GeneWeights.hiddenDim
        let b2Data = Array(gw.weights[b2Start..<(b2Start + GeneWeights.outputDim)])
        core.bias = MLXArray(b2Data)
    }
}

#endif
