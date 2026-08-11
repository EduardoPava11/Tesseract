// DyadPreview.swift
// Tesseract
//
// PREVIEW/EXPORT UNIFICATION under THE AERIAL MIRROR LAW (spec §6c v5
// + §4b; ported 2026-08-10): the live preview runs the SAME law as the
// DYAD export, approximated to fit the frame budget on the TL8/TL9
// ladder:
//
//   rung 64 @ 20 Hz — per-pixel γ-staged assignment (ŷ = c_F +
//                     γ(s)·(y − c_F), one search, σ-routing at
//                     coverage t) — on the GPU when the aerialPreview
//                     kernel is available, CPU otherwise;
//   rung 16 @ 5 Hz  — the slow state: judgment-pooled mixture fit
//                     with the DM11 τ-LIFT (law of total variance,
//                     an identity — the naive pooled τ collapses),
//                     stats-on-ŷ, derived-α EMA, table solve.
//
// Approximations vs the export (documented, not hidden):
//   · judgments here are the frame's 4×4 spatial blocks (256 of 16
//     samples); the export's rung-16 judgment also pools 4 frames —
//     the τ-lift identity covers both poolings;
//   · the EMA gain derives from a 16-frame ring of staged stats;
//   · GPU assignment is fp32 — near-tie flips vs the CPU reference
//     are the only permitted difference (the ANE parity posture).
//
// Called ONLY on the owning manager's serial queue — no locking.

import Foundation
import simd

final class DyadPreview {

    /// Slow-state stride: 20 Hz frames / 4 = the 5 Hz rung-16 cadence.
    static let refreshStride = 4

    /// Everything the Metal kernel needs for one 20 Hz assignment.
    struct MetalState {
        var primaries: [SIMD4<Float>]   // 128 OKLab primaries (xyz)
        var centroid: SIMD3<Float>      // the γ-staging centroid c_F
        var sStar: Float                // mixture crossover
        var tau: Float                  // mixture temperature
        var twoPhase: Bool
    }

    private var counter = 0
    private var mixture: DepthMixture.Fit?
    private var twoPhase = false
    private var cFStage = OKLabColor(l: 0.5, a: 0, b: 0)
    private var history: [[Double]] = []          // staged stat 9-vectors, ≤ 16
    private var smoothed: DyadPalette.Stats?
    // Ground-law state (step 3, R2): the background moment triple,
    // EMA'd like the stats; nil until background evidence exists.
    private var smoothedBg: (meanL: Double, meanLnC: Double, sdLnC: Double)?
    private(set) var table: [(UInt8, UInt8, UInt8)] = []
    private var prims: [OKLabColor] = []

    // MARK: - The 5 Hz slow state

    /// Run the slow state if this frame is on the rung-16 cadence.
    /// Always advances the frame counter — call exactly once per frame.
    func refreshIfDue(rgb: [(Float, Float, Float)], depths: [Float]) {
        if counter % Self.refreshStride == 0 {
            refresh(rgb: rgb, depths: depths)
        }
        counter += 1
    }

    private func refresh(rgb: [(Float, Float, Float)], depths: [Float]) {
        // Rung-16 judgments: 4×4 spatial blocks — exact means + the
        // within-judgment variance the τ-lift restores (DM11).
        let side = Int(Double(depths.count).squareRoot())
        let block = 4
        let bSide = side / block
        var means = [Double]()
        var withinSum = 0.0
        means.reserveCapacity(bSide * bSide)
        for by in 0..<bSide {
            for bx in 0..<bSide {
                var sum = 0.0, sumSq = 0.0
                for dy in 0..<block {
                    for dx in 0..<block {
                        let v = Double(depths[(by * block + dy) * side + bx * block + dx])
                        let q = v.isNaN ? 0.5 : min(max(v, 0), 1)
                        sum += q; sumSq += q * q
                    }
                }
                let n = Double(block * block)
                let m = sum / n
                means.append(m)
                withinSum += max(0, sumSq / n - m * m)
            }
        }
        let pooled = DepthMixture.fit(means)
        twoPhase = DepthMixture.isTwoPhase(means, fit: pooled)
        let fit = DepthMixture.fitLifted(
            means: means, meanWithinVariance: withinSum / Double(means.count))
        mixture = fit

        // Stats-on-ŷ (DY12): raw weighted centroid → γ-stage → analyze.
        let samples = rgb.map { DyadPipeline.srgb8(from: $0) }
        let weights = twoPhase ? depths.map { 1 - fit.pull(Double($0)) }
                               : [Double](repeating: 1, count: depths.count)
        let cF = DyadPalette.analyze(samples, weights: weights).centroid
        cFStage = cF
        let staged = zip(samples, depths).map { rgb8, d in
            DyadPalette.srgb8(from: DyadPipeline.stageAerial(
                DyadPalette.oklab(fromSRGB8: rgb8), s: Double(d), about: cF))
        }
        let raw = DyadPalette.analyze(staged, weights: weights)
        history.append(DyadPipeline.statVector(raw))
        if history.count > 16 { history.removeFirst() }
        let alpha = DepthMixture.localLevelAlpha(history)
        let warm = smoothed.map { DyadPalette.ema(alpha: alpha, raw, $0) } ?? raw
        smoothed = warm

        // Ground law (step 3, ruling R2) — preview through the export
        // fit: background moments on the staged labs with σ weights,
        // EMA'd with the same gain; prior until evidence exists.
        let prims8 = DyadPalette.primaries(stats: warm)
        let cL = DyadPalette.centroidL(prims8)
        let primsLab = prims8.map { DyadPalette.oklab(fromSRGB8: $0) }
        if twoPhase {
            let ts = depths.map { fit.pull(Double($0)) }
            let stagedLabs = staged.map { DyadPalette.oklab(fromSRGB8: $0) }
            if let rb = DyadPalette.backgroundMoments(labs: stagedLabs, weights: ts) {
                smoothedBg = smoothedBg.map { prev in
                    ( alpha * rb.meanL + (1 - alpha) * prev.meanL
                    , alpha * rb.meanLnC + (1 - alpha) * prev.meanLnC
                    , alpha * rb.sdLnC + (1 - alpha) * prev.sdLnC )
                } ?? rb
            }
        }
        let gm = smoothedBg.map {
            DyadPalette.groundMoments(centroidL: cL, primsLab: primsLab,
                                      background: $0)
        } ?? DyadPalette.priorMoments(centroidL: cL)
        table = DyadPalette.table(stats: warm, moments: gm)
        prims = primsLab
    }

    // MARK: - The 20 Hz assignment (CPU reference; GPU twin in Metal)

    /// One frame under the unified law, or nil until the first table.
    func assignCPU(rgb: [(Float, Float, Float)], depths: [Float]) -> [UInt8]? {
        guard let mixture, !prims.isEmpty else { return nil }
        let side = Int(Double(rgb.count).squareRoot())
        var out = [UInt8](repeating: 0, count: rgb.count)
        for p in 0..<rgb.count {
            let s = Double(depths[p])
            let t = twoPhase ? mixture.pull(s) : 0
            let yhat = DyadPipeline.stageAerial(
                DyadPalette.oklab(fromSRGB8: DyadPipeline.srgb8(from: rgb[p])),
                s: s, about: cFStage)
            var best = 0
            var bestD = Double.infinity
            for j in 0..<prims.count {
                let d = DyadPalette.dLab2(prims[j], yhat)
                if d < bestD { bestD = d; best = j }
            }
            let sigmaSide = DyadPipeline.bayer4[(p / side) % 4][(p % side) % 4] < Float(t)
            if sigmaSide {
                // ★R4 faithful-hue (2026-08-11): σ side routes through
                // comp — displayed ≈ ŷ (matches DyadPipeline.pairDither)
                let target = DyadPalette.comp(yhat)
                var bestC = 0
                var bestDC = Double.infinity
                for j in 0..<prims.count {
                    let d = DyadPalette.dLab2(prims[j], target)
                    if d < bestDC { bestDC = d; bestC = j }
                }
                out[p] = UInt8(255 - bestC)
            } else {
                out[p] = UInt8(best)
            }
        }
        return out
    }

    /// Full CPU path: slow state + assignment (FACE mode, GPU fallback).
    func process(rgb: [(Float, Float, Float)], depths: [Float]) -> [UInt8]? {
        refreshIfDue(rgb: rgb, depths: depths)
        return assignCPU(rgb: rgb, depths: depths)
    }

    /// The current state packaged for the aerialPreview Metal kernel,
    /// or nil until the first slow-state pass.
    var metalState: MetalState? {
        guard let mixture, prims.count == DyadPalette.primaryCount else { return nil }
        return MetalState(
            primaries: prims.map {
                SIMD4<Float>(Float($0.l), Float($0.a), Float($0.b), 0)
            },
            centroid: SIMD3<Float>(Float(cFStage.l), Float(cFStage.a), Float(cFStage.b)),
            sStar: Float(mixture.crossover),
            tau: Float(mixture.temperature),
            twoPhase: twoPhase)
    }

}
