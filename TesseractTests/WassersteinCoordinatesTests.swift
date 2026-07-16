// WassersteinCoordinatesTests.swift
// Tesseract
//
// Pure-logic tests for the 1-D EMD + barycentric coordinate machinery
// used by the DNG mode. No camera, no Metal.

import XCTest
@testable import Tesseract

final class WassersteinCoordinatesTests: XCTestCase {

    // Fixed 16-bin histograms (normalized).
    private let low: [Double] = {
        var h = [Double](repeating: 0, count: 16)
        h[0] = 0.5; h[1] = 0.3; h[2] = 0.2
        return h
    }()
    private let mid: [Double] = {
        var h = [Double](repeating: 0, count: 16)
        h[6] = 0.25; h[7] = 0.5; h[8] = 0.25
        return h
    }()
    private let high: [Double] = {
        var h = [Double](repeating: 0, count: 16)
        h[13] = 0.2; h[14] = 0.3; h[15] = 0.5
        return h
    }()

    private func delta(_ bin: Int) -> [Double] {
        var h = [Double](repeating: 0, count: 16)
        h[bin] = 1
        return h
    }

    // MARK: - EMD metric laws

    func testEMD_identityOfIndiscernibles() {
        XCTAssertEqual(WassersteinCoordinates.emd(low, low), 0, accuracy: 1e-12)
        XCTAssertEqual(WassersteinCoordinates.emd(mid, mid), 0, accuracy: 1e-12)
        XCTAssertGreaterThan(WassersteinCoordinates.emd(low, high), 0)
    }

    func testEMD_symmetry() {
        XCTAssertEqual(
            WassersteinCoordinates.emd(low, high),
            WassersteinCoordinates.emd(high, low),
            accuracy: 1e-12
        )
        XCTAssertEqual(
            WassersteinCoordinates.emd(low, mid),
            WassersteinCoordinates.emd(mid, low),
            accuracy: 1e-12
        )
    }

    func testEMD_triangleInequality() {
        let dLH = WassersteinCoordinates.emd(low, high)
        let dLM = WassersteinCoordinates.emd(low, mid)
        let dMH = WassersteinCoordinates.emd(mid, high)
        XCTAssertLessThanOrEqual(dLH, dLM + dMH + 1e-12)
    }

    func testEMD_deltaDistributionsHaveBinDistance() {
        // Ground metric is 1 per bin step: EMD(δ_i, δ_j) = |i - j| exactly.
        XCTAssertEqual(WassersteinCoordinates.emd(delta(0), delta(15)), 15, accuracy: 1e-12)
        XCTAssertEqual(WassersteinCoordinates.emd(delta(3), delta(7)), 4, accuracy: 1e-12)
        XCTAssertEqual(WassersteinCoordinates.emd(delta(9), delta(9)), 0, accuracy: 1e-12)
    }

    // MARK: - Strata projection

    func testProjectToStrata_foldsAndNormalizes() {
        // 256-bin histogram with mass only in bins 0..15 (stratum 0) and
        // 240..255 (stratum 15).
        var counts = [Int](repeating: 0, count: 256)
        for i in 0..<16 { counts[i] = 3 }          // 48 total
        for i in 240..<256 { counts[i] = 1 }        // 16 total
        let strata = WassersteinCoordinates.projectToStrata(counts)
        XCTAssertEqual(strata.count, 16)
        XCTAssertEqual(strata[0], 0.75, accuracy: 1e-12)
        XCTAssertEqual(strata[15], 0.25, accuracy: 1e-12)
        XCTAssertEqual(strata.reduce(0, +), 1.0, accuracy: 1e-12)
    }

    func testProjectToStrata_zeroHistogramIsUniform() {
        let strata = WassersteinCoordinates.projectToStrata([Int](repeating: 0, count: 256))
        for s in strata {
            XCTAssertEqual(s, 1.0 / 16.0, accuracy: 1e-12)
        }
    }

    // MARK: - Barycentric coordinates

    func testCoordinates_identityRecoversSimplexVertices() {
        let dict = (a: low, b: mid, c: high)
        let l0 = WassersteinCoordinates.coordinates(target: low, dictionary: dict)
        XCTAssertEqual(l0.lambda, SIMD3<Double>(1, 0, 0))
        XCTAssertEqual(l0.emd, 0, accuracy: 1e-12)

        let l1 = WassersteinCoordinates.coordinates(target: mid, dictionary: dict)
        XCTAssertEqual(l1.lambda, SIMD3<Double>(0, 1, 0))
        XCTAssertEqual(l1.emd, 0, accuracy: 1e-12)

        let l2 = WassersteinCoordinates.coordinates(target: high, dictionary: dict)
        XCTAssertEqual(l2.lambda, SIMD3<Double>(0, 0, 1))
        XCTAssertEqual(l2.emd, 0, accuracy: 1e-12)
    }

    func testCoordinates_partitionOfUnity() {
        let dict = (a: low, b: mid, c: high)
        // Arbitrary targets, including ones far from the dictionary span.
        let targets = [delta(4), delta(11), mid,
                       (0..<16).map { _ in 1.0 / 16.0 }]
        for t in targets {
            let (lambda, _) = WassersteinCoordinates.coordinates(target: t, dictionary: dict)
            XCTAssertEqual(lambda.x + lambda.y + lambda.z, 1.0, accuracy: 1e-9,
                           "λ must lie on the simplex")
            XCTAssertGreaterThanOrEqual(lambda.min(), 0)
        }
    }

    func testCoordinates_exactMidpointMixture() {
        // Target constructed as the 50/50 bin-wise mixture of two atoms is
        // reproduced exactly at grid resolution 1/16 (8/16 each).
        let dict = (a: low, b: mid, c: high)
        let target = (0..<16).map { 0.5 * low[$0] + 0.5 * high[$0] }
        let (lambda, d) = WassersteinCoordinates.coordinates(target: target, dictionary: dict)
        XCTAssertEqual(d, 0, accuracy: 1e-12)
        XCTAssertEqual(lambda.x, 0.5, accuracy: 1e-12)
        XCTAssertEqual(lambda.z, 0.5, accuracy: 1e-12)
    }

    func testTrajectory_endpointsAreVertices() {
        // 5 "frames": dictionary is {first, middle, last}.
        let frames = [low, delta(2), mid, delta(12), high]
        let traj = WassersteinCoordinates.trajectory(strataHistograms: frames)
        XCTAssertEqual(traj.count, 5)
        XCTAssertEqual(traj[0], SIMD3<Double>(1, 0, 0))
        XCTAssertEqual(traj[2], SIMD3<Double>(0, 1, 0))   // index 5/2 = 2
        XCTAssertEqual(traj[4], SIMD3<Double>(0, 0, 1))
        for l in traj {
            XCTAssertEqual(l.x + l.y + l.z, 1.0, accuracy: 1e-9)
        }
    }
}
