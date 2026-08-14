// DegenerateFitTests.swift
// Tesseract
//
// ★ C5 — the NaN cascade (docs/model-placement.md §3).
//
// A frame of constant depth fits two COINCIDENT components. Then
// μ_F − μ_B = 0, temperature = +inf, crossover = inf·0 = NaN, and
// pull returns NaN for every pixel. NaN never trips a comparison, so
// the frame collapses onto a handful of σ entries and poisons its own
// table without any guard firing. FACE reaches this on any tracking
// drop and unavoidably on frame 0.
//
// The fix is not a threshold: two coincident components ARE one
// component, so a degenerate fit is the single-phase case the role law
// already rules on (DM R3 — single-phase ⇒ all-face, coverage 0).
// These tests pin both the cascade's absence and the routing.

import XCTest
@testable import Tesseract

final class DegenerateFitTests: XCTestCase {

    /// The exact shape a constant-depth frame produces.
    private var coincident: DepthMixture.Fit {
        DepthMixture.Fit(muF: 0.5, muB: 0.5, piB: 0.75, sigma: 0.01)
    }

    /// A healthy two-phase fit, for contrast.
    private var separated: DepthMixture.Fit {
        DepthMixture.Fit(muF: 0.8, muB: 0.2, piB: 0.75, sigma: 0.05)
    }

    // MARK: - the cascade, and that it is gone

    func testCoincidentComponentsAreDetectedAsDegenerate() {
        XCTAssertTrue(coincident.isDegenerate,
                      "μ_F ≯ μ_B is the single-phase case, not a fit")
        XCTAssertFalse(separated.isDegenerate)
    }

    func testTheCascadeExistsInTheUnguardedArithmetic() {
        // Documents WHY the guard is needed: the raw quantities really
        // do leave the reals, and the unguarded pull is NaN either way.
        // Two routes, depending on π_B — both end in the same place:
        //   π_B ≠ ½ : crossover = ±inf, and (s − ±inf)/inf = NaN
        //   π_B = ½ : log(1) = 0, so inf·0 = NaN at the crossover
        // If this ever fails, the fit's algebra changed and the guard
        // must be re-derived rather than kept out of habit.
        func rawPull(_ f: DepthMixture.Fit, _ s: Double) -> Double {
            1 / (1 + exp((s - f.crossover) / f.temperature))
        }
        let skewed = coincident                                  // π_B = 0.75
        XCTAssertFalse(skewed.temperature.isFinite,
                       "μ_F − μ_B = 0 ⇒ σ²/0 = +inf")
        XCTAssertFalse(skewed.crossover.isFinite,
                       "inf · log(3) ⇒ ±inf")
        XCTAssertTrue(rawPull(skewed, 0.5).isNaN,
                      "(s − inf)/inf = NaN ⇒ the pull is NaN")

        let even = DepthMixture.Fit(muF: 0.5, muB: 0.5, piB: 0.5, sigma: 0.01)
        XCTAssertTrue(even.crossover.isNaN, "inf · log(1) = inf · 0 = NaN")
        XCTAssertTrue(rawPull(even, 0.5).isNaN)

        // …and both are caught by the same predicate.
        XCTAssertTrue(skewed.isDegenerate)
        XCTAssertTrue(even.isDegenerate)
    }

    func testPullIsTotalUnderDegeneracy() {
        let f = coincident
        for s in stride(from: 0.0, through: 1.0, by: 0.05) {
            let t = f.pull(s)
            XCTAssertFalse(t.isNaN, "pull must never be NaN at s=\(s)")
            XCTAssertEqual(t, 0, "degenerate ⇒ the single-phase reading")
        }
    }

    func testPullIsUnchangedWhenTheFitIsHealthy() {
        // The guard must not perturb the shipped path: a separated fit
        // keeps the exact logistic it always had.
        let f = separated
        for s in stride(from: 0.0, through: 1.0, by: 0.1) {
            let expected = 1 / (1 + exp((s - f.crossover) / f.temperature))
            XCTAssertEqual(f.pull(s), expected, accuracy: 1e-15)
        }
    }

    // MARK: - the routing (the only reading of the role law)

    func testCoverageRoutesDegeneracyToAllFace() {
        for bleed in [true, false] {
            for d in stride(from: Float(0), through: 1, by: 0.1) {
                let c = DyadPipeline.coverage(d, fit: coincident,
                                              twoPhase: true, bleed: bleed)
                XCTAssertEqual(c, 0, accuracy: 0,
                               "degenerate ⇒ coverage 0 ⇒ all-face (DM R3)")
                XCTAssertFalse(c.isNaN)
            }
        }
    }

    func testDegenerateMatchesSinglePhaseExactly() {
        // The claim the guard rests on: a degenerate two-phase fit and
        // an explicit single-phase capture are the SAME decision.
        for d in stride(from: Float(0), through: 1, by: 0.1) {
            let degenerate = DyadPipeline.coverage(d, fit: coincident,
                                                   twoPhase: true, bleed: true)
            let singlePhase = DyadPipeline.coverage(d, fit: separated,
                                                    twoPhase: false, bleed: true)
            XCTAssertEqual(degenerate, singlePhase,
                           "two coincident components ARE one component")
        }
    }

    func testHealthyTwoPhaseCoverageStillSpansTheRange() {
        // Guard against over-guarding: a real fit must still produce a
        // real band, or the fix would have flattened every capture.
        let lo = DyadPipeline.coverage(0, fit: separated,
                                       twoPhase: true, bleed: true)
        let hi = DyadPipeline.coverage(1, fit: separated,
                                       twoPhase: true, bleed: true)
        XCTAssertGreaterThan(abs(hi - lo), 0.5,
                             "a separated fit still pulls across the range")
    }
}
