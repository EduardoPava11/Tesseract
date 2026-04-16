// ResidualPipeline.swift
// Tesseract
//
// Port of spec/neural/Residual.hs:
// teacher + δ, confidence-gated, phase-identified.
//
// direction = tanh(NN_raw)          ∈ [-1, 1]
// magnitude = (1 - confidence) × δ_max
// δ = direction × magnitude
// final = round(teacher + δ)
//
// The statistics gate the corrections. The NN proposes direction.
// Face (high confidence) → δ ≈ 0. Background (low) → δ large.

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. RESIDUAL CORRECTION
// ════════════════════════════════════════════════════════════════

/// Per-pixel correction: direction × magnitude
struct Delta {
    let d: Float     // epoch correction
    let a: Float     // R level correction
    let b: Float     // G level correction
    let c: Float     // B level correction
    let g: Float     // global weight correction

    static let zero = Delta(d: 0, a: 0, b: 0, c: 0, g: 0)
}

/// Maximum correction per axis (from Residual.hs defaultMaxDelta)
struct MaxDelta {
    let epoch: Float    // 0.5
    let color: Float    // 0.5
    let global: Float   // 0.3

    static let `default` = MaxDelta(epoch: 0.5, color: 0.5, global: 0.3)
}

// ════════════════════════════════════════════════════════════════
// § 2. CONFIDENCE GATE
// ════════════════════════════════════════════════════════════════

/// Per-axis confidence: gates how far the NN can push.
/// High confidence → small magnitude → teacher wins.
/// Low confidence → large magnitude → NN explores.
struct ConfidenceGate {
    let r: Float       // R channel level confidence ∈ [0.25, 1.0]
    let g: Float       // G channel
    let b: Float       // B channel
    let epoch: Float   // epoch probability concentration
    let global: Float  // teacher global weight confidence

    /// Build from histogram decisions (per-channel confidence)
    static func from(
        rConf: Float, gConf: Float, bConf: Float,
        epochConf: Float, depth: Float
    ) -> ConfidenceGate {
        ConfidenceGate(
            r: rConf, g: gConf, b: bConf,
            epoch: epochConf,
            global: TeacherDecision.globalWeight(histConfidence: (rConf + gConf + bConf) / 3, depth: depth)
        )
    }
}

/// Compute gated δ from NN raw direction and confidence
func gateDelta(rawDirection: [Float], gate: ConfidenceGate, maxDelta: MaxDelta = .default) -> Delta {
    // Direction: tanh ∈ [-1, 1]
    let dir = rawDirection.map { tanh($0) }
    guard dir.count >= 5 else { return .zero }

    // Magnitude per axis: (1 - confidence) × max_delta
    return Delta(
        d: dir[0] * (1 - gate.epoch)  * maxDelta.epoch,
        a: dir[1] * (1 - gate.r)      * maxDelta.color,
        b: dir[2] * (1 - gate.g)      * maxDelta.color,
        c: dir[3] * (1 - gate.b)      * maxDelta.color,
        g: dir[4] * (1 - gate.global) * maxDelta.global
    )
}

// ════════════════════════════════════════════════════════════════
// § 3. APPLY RESIDUAL: teacher + δ → final
// ════════════════════════════════════════════════════════════════

/// Teacher's baseline output (from PerfectQuantizer)
struct TeacherOutput {
    let d: Int, a: Int, b: Int, c: Int  // {0,1,2,3}
    let g: Float                         // [0,1]

    var paletteIndex: UInt8 {
        UInt8(d * 64 + a * 16 + b * 4 + c)
    }
}

/// Final output after residual correction
struct FinalOutput {
    let d: Int, a: Int, b: Int, c: Int
    let g: Float

    var paletteIndex: UInt8 {
        UInt8(d * 64 + a * 16 + b * 4 + c)
    }
}

/// Apply δ to teacher → final (Residual.hs applyResidual)
func applyResidual(teacher: TeacherOutput, delta: Delta) -> FinalOutput {
    func clamp03(_ x: Int) -> Int { max(0, min(3, x)) }
    func clamp01(_ x: Float) -> Float { max(0, min(1, x)) }

    return FinalOutput(
        d: clamp03(Int(round(Float(teacher.d) + delta.d))),
        a: clamp03(Int(round(Float(teacher.a) + delta.a))),
        b: clamp03(Int(round(Float(teacher.b) + delta.b))),
        c: clamp03(Int(round(Float(teacher.c) + delta.c))),
        g: clamp01(teacher.g + delta.g)
    )
}

// ════════════════════════════════════════════════════════════════
// § 4. PHASE IDENTIFICATION
// ════════════════════════════════════════════════════════════════

/// Phase in the confidence × depth energy landscape
enum Phase: String {
    case stable    // high conf + high depth → δ ≈ 0 (face)
    case boundary  // medium → dithering territory (edges)
    case explore   // low conf + low depth → δ large (background)
}

func identifyPhase(gate: ConfidenceGate, depth: Float) -> Phase {
    let meanConf = (gate.r + gate.g + gate.b) / 3
    if meanConf > 0.7 && depth > 0.6 { return .stable }
    if meanConf < 0.4 && depth < 0.4 { return .explore }
    return .boundary
}

// ════════════════════════════════════════════════════════════════
// § 5. RESIDUAL QUANTIZE — the full pipeline
//
// teacher(pyramid) → baseline (d,a,b,c,g)
// gene(flatten(pyramid)) → direction ∈ [-1,1]^5
// Decision(histogram) → confidence gate
// δ = direction × (1-confidence) × max_delta
// final = teacher + δ → palette index
// ════════════════════════════════════════════════════════════════

/// Full residual quantization: teacher + gene correction + confidence gate.
/// This is the CORRECT path that replaces direct gene.forward().
func residualQuantize(
    gene: GeneWeights,
    pyramid: BlockPyramid,
    frameIndex: Int,
    mode: CubeMode
) -> (paletteIndex: UInt8, globalWeight: Float) {
    // 1. Teacher baseline (from Decision.swift)
    let nativeHist: (ChannelPyramid) -> CountedHist = { ch in
        switch mode {
        case .training: return ch.coarse
        case .inference: return ch.medium
        }
    }

    let rDecision = ChannelDecision(from: nativeHist(pyramid.r))
    let gDecision = ChannelDecision(from: nativeHist(pyramid.g))
    let bDecision = ChannelDecision(from: nativeHist(pyramid.b))

    // Teacher epoch from BinomialCadence
    let epochProbs = BinomialCadence.epochProbabilities(frame: frameIndex, depth: pyramid.depth)
    let teacherEpoch = (0..<4).max(by: { epochProbs[$0] < epochProbs[$1] }) ?? 0

    // Teacher global weight
    let histConf = (rDecision.confidence + gDecision.confidence + bDecision.confidence) / 3.0
    let teacherG = TeacherDecision.globalWeight(histConfidence: histConf, depth: pyramid.depth)

    let teacher = TeacherOutput(
        d: teacherEpoch,
        a: rDecision.level,
        b: gDecision.level,
        c: bDecision.level,
        g: teacherG
    )

    // 2. Gene direction (NN forward pass)
    let input = pyramid.flatten()
    let (_, _) = gene.forward(input)  // we don't use the direct output

    // Extract raw direction (pre-sigmoid) — approximate via re-running layers
    // For now: use the gene output difference from teacher as a proxy
    // In production: gene outputs raw direction, not final index
    let rawDir: [Float] = {
        // Run the gene and interpret its output as direction
        // The gene's tanh output IS the direction in [-1,1]^5
        var hidden = [Float](repeating: 0, count: GeneWeights.hiddenDim)
        let w1Base = 0
        let b1Base = GeneWeights.hiddenDim * GeneWeights.inputDim
        for h in 0..<GeneWeights.hiddenDim {
            var sum = gene.weights[b1Base + h]
            let wRow = w1Base + h * GeneWeights.inputDim
            for i in 0..<GeneWeights.inputDim {
                sum += gene.weights[wRow + i] * input[i]
            }
            hidden[h] = max(0, sum)
        }
        let w2Base = GeneWeights.attentionCount
        let b2Base = w2Base + GeneWeights.outputDim * GeneWeights.hiddenDim
        var raw = [Float](repeating: 0, count: GeneWeights.outputDim)
        for o in 0..<GeneWeights.outputDim {
            var sum = gene.weights[b2Base + o]
            let wRow = w2Base + o * GeneWeights.hiddenDim
            for h in 0..<GeneWeights.hiddenDim {
                sum += gene.weights[wRow + h] * hidden[h]
            }
            raw[o] = sum
        }
        return raw  // pre-tanh: gateDelta applies tanh internally
    }()

    // 3. Confidence gate
    let gate = ConfidenceGate(
        r: rDecision.confidence,
        g: gDecision.confidence,
        b: bDecision.confidence,
        epoch: epochProbs.max() ?? 0.25,
        global: teacherG
    )

    // 4. Gated δ
    let delta = gateDelta(rawDirection: rawDir, gate: gate)

    // 5. Apply residual
    let final = applyResidual(teacher: teacher, delta: delta)

    return (final.paletteIndex, final.g)
}

// ════════════════════════════════════════════════════════════════
// § 6. ENERGY
// ════════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════════
// § 7. TEACHER TARGETS — convert PerfectQuantizer output to training data
// ════════════════════════════════════════════════════════════════

/// Decompose palette indices + depths into (d, a, b, c, g) teacher targets.
/// The `g` value blends histogram confidence with depth.
func teacherTargets(
    indices: [UInt8],
    depths: [Float],
    pyramids: [BlockPyramid]
) -> [[Float]] {
    return indices.enumerated().map { (i, idx) in
        let d = Float(Int(idx) / 64)
        let a = Float((Int(idx) % 64) / 16)
        let b = Float((Int(idx) % 16) / 4)
        let c = Float(Int(idx) % 4)

        // Global weight from confidence + depth
        let g: Float
        if i < pyramids.count {
            let pyr = pyramids[i]
            let depth = i < depths.count ? depths[i] : 0.5
            let histConf = (pyr.r.coarse.levelConfidence
                          + pyr.g.coarse.levelConfidence
                          + pyr.b.coarse.levelConfidence) / 3.0
            g = TeacherDecision.globalWeight(histConfidence: histConf, depth: depth)
        } else {
            g = i < depths.count ? depths[i] : 0.5
        }

        return [d, a, b, c, g]
    }
}

/// Energy of a residual assignment: lower = better
struct Energy {
    let reconstruction: Float  // Hamming distance from teacher
    let beauty: Float          // 1/M (inverse Birkhoff, lower = more beautiful)
    let smoothness: Float      // spatial incoherence (lower = smoother)
    let total: Float           // weighted sum

    /// Compute energy for a single pixel (teacher vs final)
    static func computePixel(
        teacher: TeacherOutput, final: FinalOutput,
        alpha: Float = 0.4, beta: Float = 0.4, gamma: Float = 0.2
    ) -> Energy {
        let recon = Float(
            (teacher.d != final.d ? 1 : 0) +
            (teacher.a != final.a ? 1 : 0) +
            (teacher.b != final.b ? 1 : 0) +
            (teacher.c != final.c ? 1 : 0)
        )
        return Energy(reconstruction: recon, beauty: 0, smoothness: 0,
                       total: alpha * recon)
    }

    /// Compute energy for a full frame of palette indices.
    /// beauty = inverse Birkhoff. smoothness = neighbor coherence.
    static func computeFrame(
        indices: [UInt8], width: Int,
        alpha: Float = 0.4, beta: Float = 0.4, gamma: Float = 0.2
    ) -> Energy {
        // Beauty: inverse Birkhoff measure
        let measure = BirkhoffMeasure(paletteIndices: indices)
        let beauty = 1.0 / max(measure.beauty, 0.001)

        // Smoothness: mean absolute difference between horizontal neighbors
        var totalDiff: Float = 0
        var count: Float = 0
        for i in 0..<indices.count {
            let x = i % width
            if x + 1 < width {
                totalDiff += abs(Float(Int(indices[i]) - Int(indices[i + 1])))
                count += 1
            }
            if i + width < indices.count {
                totalDiff += abs(Float(Int(indices[i]) - Int(indices[i + width])))
                count += 1
            }
        }
        let smooth = count > 0 ? totalDiff / (count * 255.0) : 0  // normalized to [0,1]

        let total = alpha * 0 + beta * beauty + gamma * smooth  // recon=0 for full frame
        return Energy(reconstruction: 0, beauty: beauty, smoothness: smooth, total: total)
    }
}
