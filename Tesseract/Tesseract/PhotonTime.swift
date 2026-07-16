// PhotonTime.swift
// Tesseract
//
// Pure Swift port of isp-spec/src/ISP/Time.hs (PoissonInterarrival arm),
// isp-spec/src/ISP/Sensor/Physics.hs and Sensor/Uncertainty.hs.
//
// T is a physical per-pixel quantity in SECONDS (mean photon interarrival
// time), NOT a frame index. Every sigma is floored by the Heisenberg
// energy-time bound at the channel's wavelength anchor.
//
// No dependencies; fully unit-testable on Mac/simulator.

import Foundation

/// Bayer channel with wavelength anchor (Physics.hs `Channel`).
/// Raw values match the reducer's channel order: R=0, Gr=1, Gb=2, B=3.
enum BayerChannel: Int, CaseIterable, Sendable {
    case r = 0, gr = 1, gb = 2, b = 3
}

enum PhotonPhysics {

    // CODATA 2019 (Physics.hs:22-26)
    static let planckH = 6.62607015e-34
    static let lightC  = 299792458.0

    /// Peak-transmission centers for a generic Bayer CFA (Physics.hs:34-38).
    static func wavelengthM(_ c: BayerChannel) -> Double {
        switch c {
        case .r:       return 640e-9
        case .gr, .gb: return 546e-9
        case .b:       return 427e-9
        }
    }

    /// Heisenberg energy-time bound:
    ///   sigma_T >= lambda_c / (4 pi c sqrt(N));  n <= 0 -> +infinity
    /// (Physics.hs:63-66)
    static func heisenbergFloorSec(_ c: BayerChannel, n: Double) -> Double {
        guard n > 0 else { return .infinity }
        return wavelengthM(c) / (4 * .pi * lightC * n.squareRoot())
    }
}

/// Value-with-standard-deviation carrier (Uncertainty.hs `Uncertain`).
struct Uncertain: Sendable {
    var value: Double
    var sigma: Double
}

enum PhotonTime {

    /// Poisson interarrival estimator (Time.hs:44-58, PoissonInterarrival arm):
    ///   T  = tExp / nHat                 (T = tExp when nHat <= 0)
    ///   sT = (tExp / nHat^2) * sigmaN    (infinity when nHat <= 0)
    /// then sigma clamped UP to the Heisenberg floor computed at max(1, nHat).
    static func estimateT(channel: BayerChannel, tExp: Double,
                          nHat: Double, sigmaN: Double) -> Uncertain {
        let floorSec = PhotonPhysics.heisenbergFloorSec(channel, n: max(1, nHat))
        let t: Double  = nHat > 0 ? tExp / nHat : tExp
        let sT: Double = nHat > 0 ? (tExp / (nHat * nHat)) * sigmaN : .infinity
        return Uncertain(value: t, sigma: max(sT, floorSec))
    }

    /// Per-cell photon-count estimate from the DNG noise model.
    /// NoiseProfile semantics (DNG tag 51041): Var(x) = S*x + O on the
    /// normalized [0,1] signal, S = inverse effective gain, so N ~ x / S.
    ///
    ///   x       = clamp((meanDN - black_ch)/(white - black_ch), 0, 1)  (caller)
    ///   nHat    = max(0, x) / S_ch
    ///   sigmaN  = sqrt(max(S*x + O, 0)) / (S * sqrt(count))
    ///
    /// `count` is the number of photosites averaged into x (529 per cell
    /// at block=46) — the cell mean shrinks sigma by sqrt(count).
    static func nHat(x: Double, s: Double, o: Double, count: Int) -> (nHat: Double, sigmaN: Double) {
        guard s > 0, count > 0 else { return (0, .infinity) }
        let n = max(0, x) / s
        let variance = max(s * x + o, 0)
        let sigmaN = variance.squareRoot() / (s * Double(count).squareRoot())
        return (n, sigmaN)
    }

    /// Inverse-variance weighted mean (Uncertainty.hs `weightedMeanU`):
    ///   w_i = 1/sigma_i^2; T = sum(x_i w_i)/sum(w_i); sigma = sqrt(1/sum(w_i))
    /// Entries with non-finite or non-positive sigma are skipped.
    /// If ALL entries are skipped, returns Uncertain(fallback, .infinity).
    static func weightedMean(_ xs: [Uncertain], fallback: Double) -> Uncertain {
        var wSum = 0.0
        var num  = 0.0
        for u in xs {
            guard u.sigma.isFinite, u.sigma > 0, u.value.isFinite else { continue }
            let w = 1.0 / (u.sigma * u.sigma)
            wSum += w
            num  += u.value * w
        }
        guard wSum > 0 else { return Uncertain(value: fallback, sigma: .infinity) }
        return Uncertain(value: num / wSum, sigma: (1.0 / wSum).squareRoot())
    }
}
