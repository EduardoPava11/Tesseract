// DepthMixture.swift
// Tesseract
//
// THE CONSTANT-FREE ROLE LAW — Swift twin of spec/temporal/DepthMixture.hs
// (DM1–DM10, suite-enrolled 2026-08-10). Subject and background are the
// two phases of the capture's own depth field: a tied-variance
// two-component Gaussian mixture fit by EM over the pooled 64×4096
// samples. Everything DyadPipeline used to hard-code is derived:
//
//   pull       t(s) = P(B|s) = 1 / (1 + exp((s − s*)/τ))
//   crossover  s*   = (μ_F+μ_B)/2 + τ·ln(π_B/π_F)
//   temper.    τ    = σ² / (μ_F − μ_B)
//
// Tied σ is load-bearing: it keeps the log-odds linear in s, hence the
// posterior monotone and the crossover unique (DM2). BIC decides
// whether a background phase exists at all (DM9); a single-phase
// capture is ALL-FACE by ruling R3. The EMA gain for the per-frame
// palette statistics is the steady-state Kalman gain of a local-level
// model, estimated from the stats sequence itself (DM10, ruling R2).

import Foundation

enum DepthMixture {

    struct Fit: Sendable {
        var muF: Double     // subject mean (μ_F ≥ μ_B by relabeling)
        var muB: Double     // background mean
        var piB: Double     // background weight
        var sigma: Double   // tied std-dev (floored)

        var temperature: Double { sigma * sigma / (muF - muB) }
        var crossover: Double {
            (muF + muB) / 2 + temperature * log(piB / (1 - piB))
        }

        /// THE PULL. IEEE-total: exp overflow saturates t to 0/1.
        func pull(_ s: Double) -> Double {
            1 / (1 + exp((s - crossover) / temperature))
        }
    }

    // MARK: - EM (mirrors the spec: median-split init, 64 steps, tied σ)

    /// Background responsibility, log-space (total for any σ ≥ floor).
    private static func responsibility(_ f: Fit, _ x: Double) -> Double {
        let dF = x - f.muF, dB = x - f.muB
        let logOdds = log(f.piB / (1 - f.piB))
                    + (dF * dF - dB * dB) / (2 * f.sigma * f.sigma)
        return 1 / (1 + exp(-logOdds))
    }

    private static func emStep(_ xs: [Double], _ f: Fit) -> Fit {
        let n = Double(xs.count)
        var sB = 0.0, sumBx = 0.0, sumFx = 0.0
        var rs = [Double](); rs.reserveCapacity(xs.count)
        for x in xs {
            let r = responsibility(f, x)
            rs.append(r)
            sB += r; sumBx += r * x; sumFx += (1 - r) * x
        }
        let sF = n - sB
        let mb = sumBx / sB
        let mf = sumFx / sF
        var varSum = 0.0
        for (x, r) in zip(xs, rs) {
            varSum += r * (x - mb) * (x - mb) + (1 - r) * (x - mf) * (x - mf)
        }
        return Fit(muF: mf, muB: mb, piB: sB / n,
                   sigma: max(1e-9, (varSum / n).squareRoot()))
    }

    static func fit(_ depths: [Double]) -> Fit {
        let ys = depths.sorted()
        let half = ys.count / 2
        let lo = ys[..<half], hi = ys[half...]
        let mean = { (zs: ArraySlice<Double>) in zs.reduce(0, +) / Double(zs.count) }
        let m = ys.reduce(0, +) / Double(ys.count)
        let sd = max(1e-9, (ys.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(ys.count)).squareRoot())
        var f = Fit(muF: mean(hi), muB: mean(lo), piB: 0.5, sigma: sd)
        for _ in 0..<64 { f = emStep(depths, f) }
        if f.muF < f.muB {
            f = Fit(muF: f.muB, muB: f.muF, piB: 1 - f.piB, sigma: f.sigma)
        }
        return f
    }

    // MARK: - BIC model selection (DM9): does a background phase exist?

    private static func logNormal(_ x: Double, _ mu: Double, _ sd: Double) -> Double {
        let d = (x - mu) / sd
        return -d * d / 2 - log(sd) - log(2 * Double.pi) / 2
    }

    private static func logLik(_ xs: [Double], _ f: Fit) -> Double {
        xs.reduce(0) { acc, x in
            let lB = log(f.piB) + logNormal(x, f.muB, f.sigma)
            let lF = log(1 - f.piB) + logNormal(x, f.muF, f.sigma)
            let hi = max(lB, lF)
            return acc + hi + log(exp(lB - hi) + exp(lF - hi))   // log-sum-exp
        }
    }

    /// True iff BIC prefers two phases (k=4, tied) over one (k=2).
    static func isTwoPhase(_ depths: [Double], fit f: Fit) -> Bool {
        guard f.muF > f.muB else { return false }
        let n = Double(depths.count)
        let m = depths.reduce(0, +) / n
        let sd = max(1e-9, (depths.reduce(0) { $0 + ($1 - m) * ($1 - m) } / n).squareRoot())
        let single = Fit(muF: m, muB: m, piB: 0.5, sigma: sd)
        let bic1 = 2 * log(n) - 2 * logLik(depths, single)
        let bic2 = 4 * log(n) - 2 * logLik(depths, f)
        return bic2 < bic1
    }

    // MARK: - Rung-16 preview fit (DM11/DM12): the τ-lift

    /// Fit on pooled judgment means, then LIFT the tied variance by the
    /// law of total variance — σ²_total = σ²_between + E[σ²_within], an
    /// identity, not a tunable (spec §4b). The naive pooled τ collapses
    /// (means alone lose the within-judgment spread and harden the
    /// band); the lifted fit recovers the full-resolution (s*, τ).
    /// EXPORT keeps the full-res pooled fit — measurement-only decree.
    static func fitLifted(means: [Double], meanWithinVariance: Double) -> Fit {
        let pooled = fit(means)
        let sigma2 = pooled.sigma * pooled.sigma + max(0, meanWithinVariance)
        return Fit(muF: pooled.muF, muB: pooled.muB, piB: pooled.piB,
                   sigma: max(1e-9, sigma2.squareRoot()))
    }

    // MARK: - Crossover report (DM6): meters are an OUTPUT, never an input

    static func metersOf(signal s: Double) -> Double {
        let invNear = 1 / Double(DepthSignal.dNear)
        let invFar = 1 / Double(DepthSignal.dFar)
        return 1 / (invFar + s * (invNear - invFar))
    }

    // MARK: - Derived EMA gain (DM10, ruling R2)

    /// Lag-1 autocorrelation of a series; nil if constant or too short.
    private static func rho1(_ ds: [Double]) -> Double? {
        guard ds.count >= 2 else { return nil }
        let n = Double(ds.count)
        let dbar = ds.reduce(0, +) / n
        let es = ds.map { $0 - dbar }
        let v = es.reduce(0) { $0 + $1 * $1 } / n
        guard v > 0 else { return nil }
        let c1 = zip(es, es.dropFirst()).reduce(0) { $0 + $1.0 * $1.1 } / (n - 1)
        return c1 / v
    }

    /// Steady-state Kalman gain of the pooled local-level model over
    /// per-frame stat vectors (Muth 1960). Var(Δx) = q + 2r,
    /// Cov₁(Δx) = −r; standardized, r̂ = max(0,−ρ), q̂ = 1 − 2r̂.
    static func localLevelAlpha(_ series: [[Double]]) -> Double {
        guard series.count >= 3, let k = series.first?.count else { return 1 }
        var bigR = 0.0, bigQ = 0.0
        var informative = false
        for c in 0..<k {
            let comp = series.map { $0[c] }
            let diffs = zip(comp.dropFirst(), comp).map { $0 - $1 }
            guard let rho = rho1(diffs) else { continue }
            informative = true
            bigR += max(0, -rho)
            bigQ += max(0, 1 + 2 * min(0, rho))
        }
        guard informative, bigR > 0 else { return 1 }
        guard bigQ > 0 else { return 0 }
        let lam = bigQ / bigR
        let x = (lam + (lam * lam + 4 * lam).squareRoot()) / 2
        return x / (x + 1)
    }
}
