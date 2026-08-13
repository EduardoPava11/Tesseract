// DepthMixtureTests.swift
// Tesseract
//
// Golden pins for the constant-free role law, mirroring
// spec/temporal/DepthMixture.hs (DM1–DM10). The planted fields are
// the spec's, and the recovery targets are the spec's printed
// goldens — Swift and Haskell must agree on the same capture.
// Pure logic: runs on simulator.

import XCTest
@testable import Tesseract

final class DepthMixtureTests: XCTestCase {

    // Binomial(8) atoms around a mean (spec §4): near-Gaussian,
    // exact weights, deterministic. var = δ²/2.
    private func cluster(_ mu: Double, _ delta: Double, _ count: Int) -> [Double] {
        let c8 = [1, 8, 28, 56, 70, 56, 28, 8, 1]
        var out = [Double]()
        for k in 0...8 {
            out.append(contentsOf: [Double](
                repeating: mu + delta * Double(k - 4) / 2,
                count: count * c8[k] / 256))
        }
        return out
    }

    // The planted portrait: wall at s=0.05 (3072 px), face at 0.75 (1024).
    private var bimodal: [Double] {
        cluster(0.05, 0.06, 3072) + cluster(0.75, 0.06, 1024)
    }
    private var unimodal: [Double] { cluster(0.5, 0.06, 4096) }

    // MARK: - DM3: planted recovery, pinned to the spec goldens

    func testPlantedRecoveryMatchesSpec() {
        let f = DepthMixture.fit(bimodal)
        XCTAssertEqual(f.muF, 0.75, accuracy: 0.01)
        XCTAssertEqual(f.muB, 0.05, accuracy: 0.01)
        XCTAssertEqual(f.piB, 0.75, accuracy: 0.01)
        XCTAssertEqual(f.sigma, 0.06 / 2.0.squareRoot(), accuracy: 0.01)
        // spec-printed goldens for the same field
        XCTAssertEqual(f.crossover, 0.402825, accuracy: 5e-4)
        XCTAssertEqual(DepthMixture.metersOf(signal: f.crossover),
                       0.497657, accuracy: 5e-4)
    }

    // MARK: - DM1/DM2: total, monotone, unique crossover

    func testPullRangeMonotoneCrossover() {
        let f = DepthMixture.fit(bimodal)
        var prev = Double.infinity
        for k in 0...100 {
            let t = f.pull(Double(k) / 100)
            XCTAssertTrue(t >= 0 && t <= 1)
            XCTAssertLessThanOrEqual(t, prev + 1e-12, "t must be nonincreasing in s")
            prev = t
        }
        XCTAssertEqual(f.pull(f.crossover), 0.5, accuracy: 1e-9)
        // IEEE-total far outside the data range
        XCTAssertEqual(f.pull(1e6), 0, accuracy: 1e-12)
        XCTAssertEqual(f.pull(-1e6), 1, accuracy: 1e-12)
    }

    // MARK: - DM8: trichotomy from the Bayer extrema only

    func testTrichotomyBoundariesAreTheBayerExtrema() {
        XCTAssertEqual(DyadPipeline.coverageFloor, 1.0 / 32)
        XCTAssertEqual(DyadPipeline.coverageCeil, 31.0 / 32)
        let f = DepthMixture.fit(bimodal)
        XCTAssertLessThan(f.pull(f.muF), DyadPipeline.coverageFloor,
                          "deep in the face phase: solid face")
        XCTAssertGreaterThan(f.pull(f.muB), DyadPipeline.coverageCeil,
                             "deep in the background phase: solid mirror")
        let tCross = f.pull(f.crossover)
        XCTAssertTrue(tCross > DyadPipeline.coverageFloor
                   && tCross < DyadPipeline.coverageCeil,
                      "the crossover dithers")
    }

    // MARK: - DM9: BIC phase count

    func testBICPhaseSelection() {
        let f2 = DepthMixture.fit(bimodal)
        XCTAssertTrue(DepthMixture.isTwoPhase(bimodal, fit: f2))
        let f1 = DepthMixture.fit(unimodal)
        XCTAssertFalse(DepthMixture.isTwoPhase(unimodal, fit: f1),
                       "a face-filling capture has one phase (ruling R3: all-face)")
    }

    // MARK: - DM10: the derived EMA gain (ruling R2)

    // Spec §5 planted sequences: 16-frame flicker, 17-frame walk
    // (scanl includes the origin), constant, and their blends.
    private var flickerSeq: [[Double]] {
        (0..<16).map { k in
            let s = k % 2 == 0 ? 1.0 : -1.0
            return [s * 0.1, s * 3]
        }
    }
    private var walkSeq: [[Double]] {
        var w = [0.0]
        for d in (0..<16).map({ [1.0, 1, -1, -1][$0 % 4] }) {
            w.append(w.last! + d)
        }
        return w.map { [$0, 2 * $0] }
    }
    private var constSeq: [[Double]] { Array(repeating: [0.7, 0.2], count: 16) }

    private func blend(_ amp: Double) -> [[Double]] {
        zip(walkSeq, flickerSeq).map { w, f in
            zip(w, f).map { amp * $0 + $1 }
        }
    }

    func testDerivedAlphaEndpointsMatchSpec() {
        XCTAssertEqual(DepthMixture.localLevelAlpha(flickerSeq), 0,
                       "pure flicker: full smoothing")
        XCTAssertEqual(DepthMixture.localLevelAlpha(walkSeq), 1,
                       "zero-lag-1 walk: follow the measurement")
        XCTAssertEqual(DepthMixture.localLevelAlpha(constSeq), 1,
                       "constant stats: identity EMA, byte-neutral")
        let a1 = DepthMixture.localLevelAlpha(blend(1))
        let a4 = DepthMixture.localLevelAlpha(blend(4))
        XCTAssertTrue(a1 > 0 && a1 < a4 && a4 < 1,
                      "blends interior and monotone in signal/noise")
        XCTAssertEqual(DepthMixture.localLevelAlpha([[1], [2]]), 1,
                       "too short to estimate: identity EMA")
    }

    // MARK: - DM11: the rung-16 τ-lift (Swift twin)

    /// Judgment pooling collapses τ naively; the total-variance lift
    /// recovers the full-resolution (s*, τ) — mirrors spec §4b with
    /// the same planted capture (binomial(6) = exactly 64 samples).
    func testLiftedFitRecoversFullResolution() {
        func judgment64(_ mu: Double, _ delta: Double) -> [Double] {
            let w = [1, 6, 15, 20, 15, 6, 1]
            return (0...6).flatMap { k in
                [Double](repeating: mu + delta * Double(k - 3) / 2, count: w[k])
            }
        }
        let blocks = [[Double]](repeating: judgment64(0.05, 0.06), count: 48)
                   + [[Double]](repeating: judgment64(0.75, 0.06), count: 16)
        let full = DepthMixture.fit(blocks.flatMap { $0 })
        let means = blocks.map { $0.reduce(0, +) / 64 }
        let withins = blocks.map { b -> Double in
            let m = b.reduce(0, +) / 64
            return b.reduce(0) { $0 + ($1 - m) * ($1 - m) } / 64
        }
        let naive = DepthMixture.fit(means)
        let lifted = DepthMixture.fitLifted(
            means: means, meanWithinVariance: withins.reduce(0, +) / Double(withins.count))
        XCTAssertLessThan(naive.temperature, full.temperature / 10,
                          "naive pooled τ must collapse")
        XCTAssertEqual(lifted.temperature, full.temperature,
                       accuracy: full.temperature * 0.05,
                       "the total-variance lift recovers τ")
        XCTAssertEqual(lifted.crossover, full.crossover, accuracy: 0.005,
                       "the lifted crossover matches full-res")
    }

    /// The lift is a map on the FITTED state, and `fitLifted` is only
    /// its composition with `fit` — the live read (EM13) fits once and
    /// lifts, so the two spellings must never fork. w = 0 is the
    /// identity on σ², which is why a fine read passes no lift at all.
    func testLiftIsAMapOnTheFittedState() {
        let xs = (0..<256).map { Double($0 % 7) / 6 }
        let f = DepthMixture.fit(xs)
        let w = 0.01
        let a = DepthMixture.fitLifted(means: xs, meanWithinVariance: w)
        let b = DepthMixture.lift(f, byWithinVariance: w)
        XCTAssertEqual(a.sigma, b.sigma)
        XCTAssertEqual(a.crossover, b.crossover)
        XCTAssertEqual(DepthMixture.lift(f, byWithinVariance: 0).sigma, f.sigma,
                       accuracy: f.sigma * 1e-15,
                       "w = 0 is the identity on σ (round-trip through √ aside)")
        XCTAssertGreaterThan(b.temperature, f.temperature,
                             "a coarse read's band is SOFTER than the pooled field's")
    }

    // MARK: - The original bug, as a regression law

    /// A binary portrait field (face 1, wall 0) must come out
    /// two-phase with a hard split — the flat-blue collapse is now a
    /// consequence of the fitted law, not of a hard-coded 46 cm.
    func testBinaryFieldSplitsHard() {
        let field = [Double](repeating: 1, count: 1810)
                  + [Double](repeating: 0, count: 2286)
        let f = DepthMixture.fit(field)
        XCTAssertTrue(DepthMixture.isTwoPhase(field, fit: f))
        XCTAssertEqual(f.pull(1), 0)
        XCTAssertEqual(f.pull(0), 1)
        XCTAssertEqual(f.muF, 1, accuracy: 1e-9)
        XCTAssertEqual(f.muB, 0, accuracy: 1e-9)
    }
}
