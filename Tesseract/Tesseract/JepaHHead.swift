// ★JEPA-H v7 — THE ONE MODEL, deployed (JH4; nn/jepa charter,
// Daniel's decree 2026-08-12: MLX JEPA-H → iPhone, beauty is the
// objective). This is the ENTIRE deployed smoother: 149 weights
// (JepaHWeights.swift) driving a regime-conditioned symmetric
// 5-tap ring filter + jump gate on the capture's 16-slot latent
// ring. The hypernet reads only the ring's own autocorrelations
// (r1, r2, r3 — the sufficient statistics for the smoothing gain);
// NO slot-content parameters exist, so the model structurally
// cannot memorize content — it can only map regime → kernel.
//
// Pure Swift on CPU by design: a 16×6 ring is orders of magnitude
// below the measured ANE dispatch floor, so the mlpackage
// (nn/jepa/JepaH.mlpackage) stays the Mac-side reference and THIS
// port is the phone's law. Parity vs the float64 training forward
// is gated by nn/jepa/parity_swift.sh and JepaHParityTests.
//
// Beauty gates passed on 128 held-out rings (nn/jepa/RESULTS.md):
// palette churn 7.92 vs oracle-gain EMA 8.97 (truth 8.45),
// LZW(LCT stream) down, state RMSE better than the oracle EMA.

import Foundation

enum JepaHHead {

    /// The ring: 16 = frames/epochs (spec JepaH.hs JH1, derived).
    static let slots = 16
    /// The latent: centroid l,a,b + log-diagonal variances (the
    /// corpus law, spec/output/JepaCorpusEmit.hs).
    static let dims = 6

    /// v7 forward, mirroring nn/jepa/train.py StateHead exactly:
    /// per-dim ring whitening → autocorrelation regime → hypernet
    /// (3→16 gelu →5) → softmax 3-logit symmetric 5-tap kernel +
    /// softplus/sigmoid jump gate → de-whiten. Ring-rotation
    /// equivariant end to end (JH4's whitening law + the filter
    /// being a ring convolution): the model has no phase origin.
    ///
    /// DIM-AGNOSTIC BY CONSTRUCTION: every operation is per-dim and
    /// the whitening + autocorrelation regime make the hypernet's
    /// input scale-free, so the learned regime→kernel map applies
    /// lawfully to ANY local-level dimension — the corpus's 6 stats
    /// dims and the bg-moments triple alike (the "one smoothing law
    /// for all generating state" ruling, R2).
    static func smoothRing(_ y: [[Double]]) -> [[Double]] {
        let m = y.first?.count ?? 0
        precondition(y.count == slots && y.allSatisfy { $0.count == m })
        let n = Double(slots)
        var out = y

        for d in 0..<m {
            // ── whiten this dim over the ring ──
            var mu = 0.0
            for t in 0..<slots { mu += y[t][d] }
            mu /= n
            var varAcc = 0.0
            for t in 0..<slots { let c = y[t][d] - mu; varAcc += c * c }
            let sd = (varAcc / n).squareRoot() + 1e-12
            var w = [Double](repeating: 0, count: slots)
            for t in 0..<slots { w[t] = (y[t][d] - mu) / sd }

            // ── regime: circular autocorrelations, lags 1..3 ──
            var regime = [0.0, 0.0, 0.0]
            for (li, lag) in [1, 2, 3].enumerated() {
                var acc = 0.0
                for t in 0..<slots { acc += w[t] * w[(t + lag) % slots] }
                regime[li] = acc / n
            }

            // ── hypernet: regime → kernel logits + gate params ──
            var h = [Double](repeating: 0, count: 16)
            for i in 0..<16 {
                var acc = JepaHWeights.r1b[i]
                for j in 0..<3 { acc += JepaHWeights.r1w[i * 3 + j] * regime[j] }
                h[i] = gelu(acc)
            }
            var p = [Double](repeating: 0, count: 5)
            for i in 0..<5 {
                var acc = JepaHWeights.r2b[i]
                for j in 0..<16 { acc += JepaHWeights.r2w[i * 16 + j] * h[j] }
                p[i] = acc
            }
            let mx = max(p[0], max(p[1], p[2]))
            let e0 = exp(p[0] - mx), e1 = exp(p[1] - mx), e2 = exp(p[2] - mx)
            let z = e0 + e1 + e2
            let a0 = e0 / z, a1 = e1 / z, a2 = e2 / z
            let gs = log1p(exp(p[3]))
            let gb = p[4]

            // ── symmetric 5-tap ring filter + jump gate ──
            for t in 0..<slots {
                let c = w[t]
                let p1 = w[(t + 1) % slots], m1 = w[(t + slots - 1) % slots]
                let p2 = w[(t + 2) % slots], m2 = w[(t + slots - 2) % slots]
                let smooth = a0 * c + 0.5 * a1 * (p1 + m1) + 0.5 * a2 * (p2 + m2)
                let dev = abs(c - 0.5 * (p1 + m1))
                let g = 1 / (1 + exp(-(gs * dev + gb)))
                out[t][d] = ((1 - g) * smooth + g * c) * sd + mu
            }
        }
        return out
    }

    static func gelu(_ x: Double) -> Double {
        0.5 * x * (1 + erf(x / 2.0.squareRoot()))
    }
}
