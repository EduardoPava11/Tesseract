// CubeInteraction.swift
// Tesseract
//
// Port of Residual.hs §5: three interaction mechanisms.
// Form follows function — the GIF is a 64³ cube.
//
//   1. ROTATE: drag on GIF rotates δ in aesthetic subspace
//   2. SWIPE:  L/R/U/D = discretized rotation + Sobol exploration
//   3. INTERPOLATE: slider between two genes → lerp weights
//
// Each interaction produces a new GeneWeights (or modifies the current one).
// The residual pipeline then applies teacher + confidence-gated δ.

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. INTERACTION TYPE
// ════════════════════════════════════════════════════════════════

/// The three mechanisms for navigating aesthetic space
enum CubeInteraction {
    /// Rotate the cube: (rx, ry, rz) angles in radians
    /// X-axis: spatial structure (R ↔ G)
    /// Y-axis: temporal ↔ spatial trade (epoch ↔ color)
    /// Z-axis: chromatic balance (warm ↔ cool)
    case rotate(rx: Float, ry: Float, rz: Float)

    /// Swipe in 4 directions (discretized rotation)
    case swipe(SwipeDirection)

    /// Interpolate between two genes: α ∈ [0, 1]
    case interpolate(alpha: Float, geneA: GeneWeights, geneB: GeneWeights)
}

enum SwipeDirection {
    case left   // explore (Sobol next direction)
    case right  // retreat (revert to previous)
    case up     // more temporal (increase H(d))
    case down   // more stable (decrease H(d))
}

// ════════════════════════════════════════════════════════════════
// § 2. APPLY INTERACTION → NEW GENE
// ════════════════════════════════════════════════════════════════

/// Apply an interaction to the current gene → new gene
func applyInteraction(
    _ interaction: CubeInteraction,
    currentGene: GeneWeights,
    previousGene: GeneWeights,
    sobolExplorer: inout SobolExplorer
) -> GeneWeights {
    switch interaction {
    case .rotate(let rx, let ry, let rz):
        return applyRotation(rx: rx, ry: ry, rz: rz, gene: currentGene)

    case .swipe(let direction):
        switch direction {
        case .left:
            // Sobol next direction: guaranteed novel
            return sobolExplorer.perturb(currentGene, scale: 0.05)
        case .right:
            return previousGene
        case .up:
            // Increase temporal diversity: perturb epoch-related weights
            return perturbEpochAxis(currentGene, scale: 0.03, increase: true)
        case .down:
            // Decrease temporal diversity: perturb epoch-related weights
            return perturbEpochAxis(currentGene, scale: 0.03, increase: false)
        }

    case .interpolate(let alpha, let geneA, let geneB):
        return interpolateGenes(alpha: alpha, geneA: geneA, geneB: geneB)
    }
}

// ════════════════════════════════════════════════════════════════
// § 3. ROTATION — rotate δ in aesthetic subspace
//
// The ATTENTION weights define the NN's direction vector.
// Rotating the gene = rotating which subspace the NN emphasizes.
// X: rotate R↔G perception. Y: rotate epoch↔color. Z: rotate warm↔cool.
// ════════════════════════════════════════════════════════════════

private func applyRotation(rx: Float, ry: Float, rz: Float, gene: GeneWeights) -> GeneWeights {
    // Apply rotation to the ATTENTION weights (first 4416 floats)
    // The rotation is applied to the OUTPUT side of W1 (32 hidden dims)
    // This rotates WHICH features the hidden layer responds to
    var newWeights = gene.weights

    let hiddenDim = GeneWeights.hiddenDim  // 32
    let inputDim = GeneWeights.inputDim    // 137

    // Rotation in the hidden representation space
    // Apply 2D rotation matrices to pairs of hidden dimensions
    // X-rotation: dims 0,1 (maps to spatial R↔G subspace)
    let cosX = cos(rx); let sinX = sin(rx)
    // Y-rotation: dims 2,3 (maps to temporal↔spatial subspace)
    let cosY = cos(ry); let sinY = sin(ry)
    // Z-rotation: dims 4,5 (maps to chromatic balance subspace)
    let cosZ = cos(rz); let sinZ = sin(rz)

    // Rotate pairs of rows in W1 (each row = one hidden neuron's input weights)
    for j in 0..<inputDim {
        // X: rotate hidden dims 0,1
        let i0 = 0 * inputDim + j
        let i1 = 1 * inputDim + j
        let v0 = newWeights[i0]; let v1 = newWeights[i1]
        newWeights[i0] = cosX * v0 - sinX * v1
        newWeights[i1] = sinX * v0 + cosX * v1

        // Y: rotate hidden dims 2,3
        let i2 = 2 * inputDim + j
        let i3 = 3 * inputDim + j
        let v2 = newWeights[i2]; let v3 = newWeights[i3]
        newWeights[i2] = cosY * v2 - sinY * v3
        newWeights[i3] = sinY * v2 + cosY * v3

        // Z: rotate hidden dims 4,5
        let i4 = 4 * inputDim + j
        let i5 = 5 * inputDim + j
        let v4 = newWeights[i4]; let v5 = newWeights[i5]
        newWeights[i4] = cosZ * v4 - sinZ * v5
        newWeights[i5] = sinZ * v4 + cosZ * v5
    }

    return GeneWeights(weights: newWeights)
}

// ════════════════════════════════════════════════════════════════
// § 4. INTERPOLATION — lerp between two genes
// ════════════════════════════════════════════════════════════════

/// Interpolate ATTENTION weights. CORE stays from geneA (species identity).
/// α=1 → geneA. α=0 → geneB.
func interpolateGenes(alpha: Float, geneA: GeneWeights, geneB: GeneWeights) -> GeneWeights {
    var weights = [Float](repeating: 0, count: GeneWeights.totalCount)

    // ATTENTION: lerp
    for i in 0..<GeneWeights.attentionCount {
        weights[i] = alpha * geneA.weights[i] + (1 - alpha) * geneB.weights[i]
    }

    // CORE: keep from geneA (species identity preserved)
    for i in GeneWeights.attentionCount..<GeneWeights.totalCount {
        weights[i] = geneA.weights[i]
    }

    return GeneWeights(weights: weights)
}

// ════════════════════════════════════════════════════════════════
// § 5. EPOCH AXIS PERTURBATION — UP/DOWN swipe
//
// The first hidden dimension responds to frameNorm (input slot 127).
// Perturbing the weights connected to this input shifts temporal behavior.
// UP: increase the weights → NN pays more attention to frame position
// DOWN: decrease → NN pays less attention (more static)
// ════════════════════════════════════════════════════════════════

private func perturbEpochAxis(_ gene: GeneWeights, scale: Float, increase: Bool) -> GeneWeights {
    var newWeights = gene.weights
    let inputDim = GeneWeights.inputDim
    let frameNormSlot = 127  // input slot for z/(K-1)
    let sign: Float = increase ? 1 : -1

    // Perturb the weight from frameNorm input to each hidden neuron
    for h in 0..<GeneWeights.hiddenDim {
        let idx = h * inputDim + frameNormSlot
        newWeights[idx] += sign * scale
    }

    return GeneWeights(weights: newWeights)
}
