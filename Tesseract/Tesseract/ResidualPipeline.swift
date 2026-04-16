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
// § 5. ENERGY
// ════════════════════════════════════════════════════════════════

/// Energy of a residual assignment: lower = better
struct Energy {
    let reconstruction: Float  // Hamming distance from teacher
    let beauty: Float          // 1/M (inverse Birkhoff)
    let smoothness: Float      // spatial coherence
    let total: Float           // weighted sum

    static func compute(
        teacher: TeacherOutput, final: FinalOutput,
        alpha: Float = 0.4, beta: Float = 0.4, gamma: Float = 0.2
    ) -> Energy {
        let recon = Float(
            (teacher.d != final.d ? 1 : 0) +
            (teacher.a != final.a ? 1 : 0) +
            (teacher.b != final.b ? 1 : 0) +
            (teacher.c != final.c ? 1 : 0)
        )
        // beauty and smoothness computed from full frame (placeholder)
        let beauty: Float = 0
        let smooth: Float = 0
        return Energy(
            reconstruction: recon,
            beauty: beauty,
            smoothness: smooth,
            total: alpha * recon + beta * beauty + gamma * smooth
        )
    }
}
