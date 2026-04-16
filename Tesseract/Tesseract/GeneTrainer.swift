// GeneTrainer.swift
// Tesseract
//
// MLX training loop for the Gene residual NN.
// Uses the ROTAS PyramidTrainer pattern:
//   valueAndGrad(model:) → loss + gradients → optimizer.update
//
// The teacher provides targets. The NN learns δ corrections.
// CORE is frozen (species identity). ATTENTION is trainable (user perception).
//
// Training signal: user interactions (rotate/swipe/interpolate).
// Each interaction generates a preferred output → loss = distance from preferred.
//
// CRITICAL: Must run in Release build. Debug builds stack overflow
// during MLX valueAndGrad backward pass (~200 ops × debug frames).
// (Lesson from ROTAS CLAUDE.md)

#if canImport(MLX)
import MLX
import MLXNN
import MLXOptimizers
#endif

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. TRAINING CONFIGURATION
// ════════════════════════════════════════════════════════════════

struct GeneTrainConfig {
    let learningRate: Float
    let stepsPerInteraction: Int  // gradient steps per user gesture
    let batchSize: Int            // blocks per training batch

    static let `default` = GeneTrainConfig(
        learningRate: 1e-3,
        stepsPerInteraction: 3,   // 3 steps per swipe/rotate = responsive
        batchSize: 256            // 256 blocks per step (subsampled from 4096)
    )
}

// ════════════════════════════════════════════════════════════════
// § 2. THE TRAINER
// ════════════════════════════════════════════════════════════════

#if canImport(MLX)

/// Trains the GeneModule using user preference signals.
/// Each interaction → a few gradient steps on ATTENTION.
class GeneTrainer {

    let model: GeneModule
    let optimizer: Adam
    let config: GeneTrainConfig

    private(set) var totalSteps: Int = 0
    private(set) var lastLoss: Float = 0

    init(model: GeneModule, config: GeneTrainConfig = .default) {
        self.model = model
        self.config = config
        self.optimizer = Adam(learningRate: config.learningRate)
        model.prepareForTraining()  // freeze CORE, unfreeze ATTENTION
    }

    /// Train on a batch: input pyramids → preferred output (from user interaction).
    ///
    /// - Parameters:
    ///   - input: [batchSize, 137] flattened BlockPyramids
    ///   - teacherOutput: [batchSize, 5] teacher's (d,a,b,c,g) as continuous values
    ///   - confidenceGate: [batchSize, 5] per-axis (1-confidence) × max_delta
    ///   - preferredOutput: [batchSize, 5] the output the user chose (via interaction)
    ///
    /// Returns the average loss over the batch.
    func trainStep(
        input: MLXArray,
        teacherOutput: MLXArray,
        confidenceGate: MLXArray,
        preferredOutput: MLXArray
    ) -> Float {
        // The loss function: how far is the residual output from the user's preference?
        let lossFn = valueAndGrad(model: model) {
            [confidenceGate, preferredOutput]
            (m: GeneModule, inp: MLXArray, teacher: MLXArray) -> MLXArray in

            // NN direction: tanh ∈ [-1, 1]^5
            let direction = m(inp)

            // Gated δ: direction × confidenceGate (magnitude from statistics)
            let delta = direction * confidenceGate

            // Residual: teacher + δ
            let final = teacher + delta

            // Loss: MSE to preferred output
            // The preferred output IS what the user chose via rotation/swipe/interpolation
            let loss = (final - preferredOutput).square().mean()

            return loss
        }

        let (loss, grads) = lossFn(model, input, teacherOutput)
        optimizer.update(model: model, gradients: grads)
        eval(model.parameters())

        let lossVal = loss.item(Float.self)
        totalSteps += 1
        lastLoss = lossVal
        return lossVal
    }

    /// Run multiple training steps from a user interaction.
    /// Subsamples blocks for each step (different batch each time).
    func trainFromInteraction(
        allInputs: MLXArray,        // [totalBlocks, 137]
        allTeacher: MLXArray,       // [totalBlocks, 5]
        allConfidence: MLXArray,    // [totalBlocks, 5]
        allPreferred: MLXArray      // [totalBlocks, 5]
    ) -> Float {
        let n = allInputs.dim(0)
        var totalLoss: Float = 0

        for _ in 0..<config.stepsPerInteraction {
            // Random subsample for this step
            let indices = MLXArray.random.randInt(0..<n, [config.batchSize])
            let batchInput = allInputs[indices]
            let batchTeacher = allTeacher[indices]
            let batchConf = allConfidence[indices]
            let batchPref = allPreferred[indices]

            let loss = trainStep(
                input: batchInput,
                teacherOutput: batchTeacher,
                confidenceGate: batchConf,
                preferredOutput: batchPref
            )
            totalLoss += loss
        }

        return totalLoss / Float(config.stepsPerInteraction)
    }

    /// Export current gene weights (for capsule encoding)
    func exportGene() -> GeneWeights {
        model.exportWeights()
    }

    /// Import gene weights (from capsule or shared gene)
    func importGene(_ gw: GeneWeights) {
        model.importWeights(gw)
        model.prepareForTraining()  // re-freeze CORE after import
    }
}

#endif
