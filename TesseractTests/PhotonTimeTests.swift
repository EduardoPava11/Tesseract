// PhotonTimeTests.swift
// Tesseract
//
// Tests for the pure PhotonTime math (isp-spec Time.hs / Physics.hs /
// Uncertainty.hs port). Camera code is compile-check only; the math is not.

import XCTest
@testable import Tesseract

final class PhotonTimeTests: XCTestCase {

    // ── Poisson interarrival estimator ──

    func testEstimateT_poissonBrightPixel() {
        // T = tExp / nHat = 0.01 / 10_000 = 1e-6
        // sT = (tExp / nHat^2) * sigmaN = (0.01 / 1e8) * 100 = 1e-8
        // floor(Gr, 1e4) = 546e-9 / (4π · c · 100) ≈ 1.449e-18 → sT unchanged
        let u = PhotonTime.estimateT(channel: .gr, tExp: 0.01, nHat: 10_000, sigmaN: 100)
        XCTAssertEqual(u.value, 1e-6, accuracy: 1e-12)
        XCTAssertEqual(u.sigma, 1e-8, accuracy: 1e-14)
    }

    func testEstimateT_zeroPhotons() {
        // nHat = 0 → T = tExp; sigma infinite → floored to floor(N=1),
        // which is finite... max(sT=∞, floor) = ∞. The Haskell clampSigma
        // takes max(s, floor), so infinity stays.
        let u = PhotonTime.estimateT(channel: .r, tExp: 0.02, nHat: 0, sigmaN: 5)
        XCTAssertEqual(u.value, 0.02, accuracy: 1e-12)
        XCTAssertFalse(u.sigma.isFinite)
    }

    func testEstimateT_floorEngagesForTinySigma() {
        // Huge photon count with near-zero sigmaN: raw sT below the floor,
        // so the Heisenberg floor must win.
        let n = 1e6
        let u = PhotonTime.estimateT(channel: .b, tExp: 0.01, nHat: n, sigmaN: 1e-20)
        let floor = PhotonPhysics.heisenbergFloorSec(.b, n: n)
        XCTAssertEqual(u.sigma, floor, accuracy: floor * 1e-9)
    }

    // ── Heisenberg floor ──

    func testHeisenbergFloor_strictlyDecreasingInN() {
        var prev = Double.infinity
        for n in [1.0, 10, 100, 1e4, 1e6] {
            let f = PhotonPhysics.heisenbergFloorSec(.gr, n: n)
            XCTAssertLessThan(f, prev, "floor must strictly decrease in N")
            prev = f
        }
    }

    func testHeisenbergFloor_blueBelowRed() {
        // 427 nm < 640 nm → smaller floor at equal N.
        let n = 1000.0
        XCTAssertLessThan(
            PhotonPhysics.heisenbergFloorSec(.b, n: n),
            PhotonPhysics.heisenbergFloorSec(.r, n: n)
        )
    }

    func testHeisenbergFloor_nonPositiveNIsInfinite() {
        XCTAssertFalse(PhotonPhysics.heisenbergFloorSec(.r, n: 0).isFinite)
        XCTAssertFalse(PhotonPhysics.heisenbergFloorSec(.r, n: -3).isFinite)
    }

    // ── Inverse-variance weighted mean ──

    func testWeightedMean_equalSigmasIsArithmeticMean() {
        let xs = [
            Uncertain(value: 1.0, sigma: 0.5),
            Uncertain(value: 2.0, sigma: 0.5),
            Uncertain(value: 3.0, sigma: 0.5)
        ]
        let m = PhotonTime.weightedMean(xs, fallback: 0)
        XCTAssertEqual(m.value, 2.0, accuracy: 1e-12)
        // sigma = sqrt(1 / (3 / 0.25)) = 0.5 / sqrt(3)
        XCTAssertEqual(m.sigma, 0.5 / sqrt(3.0), accuracy: 1e-12)
    }

    func testWeightedMean_ignoresInfiniteSigmaEntries() {
        let xs = [
            Uncertain(value: 5.0, sigma: 1.0),
            Uncertain(value: 999.0, sigma: .infinity)
        ]
        let m = PhotonTime.weightedMean(xs, fallback: 0)
        XCTAssertEqual(m.value, 5.0, accuracy: 1e-12)
    }

    func testWeightedMean_allInfiniteReturnsFallback() {
        let xs = [
            Uncertain(value: 1.0, sigma: .infinity),
            Uncertain(value: 2.0, sigma: .infinity)
        ]
        let m = PhotonTime.weightedMean(xs, fallback: 0.125)
        XCTAssertEqual(m.value, 0.125, accuracy: 1e-12)
        XCTAssertFalse(m.sigma.isFinite)
    }

    func testWeightedMean_weightsBySigma() {
        // Tight measurement dominates: w1/w2 = (2/1)^2 = 4
        let xs = [
            Uncertain(value: 0.0, sigma: 1.0),
            Uncertain(value: 10.0, sigma: 2.0)
        ]
        let m = PhotonTime.weightedMean(xs, fallback: 0)
        // (0·1 + 10·0.25) / 1.25 = 2.0
        XCTAssertEqual(m.value, 2.0, accuracy: 1e-12)
    }

    // ── N-hat from the noise model ──

    func testNHat_basicRecipe() {
        // x = 0.5, S = 0.001, O = 0, count = 529
        // nHat = 0.5 / 0.001 = 500
        // sigmaN = sqrt(0.001·0.5) / (0.001 · sqrt(529))
        let (n, sN) = PhotonTime.nHat(x: 0.5, s: 0.001, o: 0, count: 529)
        XCTAssertEqual(n, 500, accuracy: 1e-9)
        let expected = sqrt(0.0005) / (0.001 * sqrt(529.0))
        XCTAssertEqual(sN, expected, accuracy: 1e-9)
    }

    func testNHat_countShrinksSigma() {
        let (_, s1) = PhotonTime.nHat(x: 0.5, s: 0.001, o: 0.0001, count: 1)
        let (_, s529) = PhotonTime.nHat(x: 0.5, s: 0.001, o: 0.0001, count: 529)
        XCTAssertEqual(s1 / s529, sqrt(529.0), accuracy: 1e-6)
    }

    func testNHat_degenerateInputs() {
        let (n, sN) = PhotonTime.nHat(x: 0.5, s: 0, o: 0, count: 529)
        XCTAssertEqual(n, 0)
        XCTAssertFalse(sN.isFinite)
    }
}
