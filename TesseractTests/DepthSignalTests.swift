// DepthSignalTests.swift
// Tesseract
//
// Swift↔Haskell golden parity for the meters → [0,1] depth signal
// contract (spec/temporal/DepthSignal.hs, DS1–DS4). The golden values
// below are the exact rationals from DS3, evaluated as Float.

import XCTest
@testable import Tesseract

final class DepthSignalTests: XCTestCase {

    private let eps: Float = 1e-6

    // ── DS3: golden points ──

    func testGoldenPoints() {
        XCTAssertEqual(DepthSignal.signal(meters: 0.25), 1.0, accuracy: eps)
        XCTAssertEqual(DepthSignal.signal(meters: 0.5), 0.4, accuracy: eps)   // 2/5
        XCTAssertEqual(DepthSignal.signal(meters: 1.0), 0.1, accuracy: eps)   // 1/10
        XCTAssertEqual(DepthSignal.signal(meters: 1.5), 0.0, accuracy: eps)
    }

    func testClamps() {
        // Beyond dFar: clamped to 0, never negative (the raw-meters bug
        // produced σ ≤ 0 here).
        XCTAssertEqual(DepthSignal.signal(meters: 2.0), 0.0)
        XCTAssertEqual(DepthSignal.signal(meters: 10.0), 0.0)
        // Closer than dNear: clamped to 1.
        XCTAssertEqual(DepthSignal.signal(meters: 0.2), 1.0)
        XCTAssertEqual(DepthSignal.signal(meters: 0.05), 1.0)
    }

    func testInvalidFill() {
        XCTAssertEqual(DepthSignal.signalOrFill(meters: 0), 0.5)
        XCTAssertEqual(DepthSignal.signalOrFill(meters: -1), 0.5)
        XCTAssertEqual(DepthSignal.signalOrFill(meters: .nan), 0.5)
        XCTAssertEqual(DepthSignal.signalOrFill(meters: .infinity), 0.5)
        // Valid values pass through to the law.
        XCTAssertEqual(DepthSignal.signalOrFill(meters: 0.5), 0.4, accuracy: eps)
    }

    // ── DS1 + DS2: range and monotonicity on a dense grid ──

    func testRangeAndMonotone() {
        var previous: Float = .infinity
        for step in 1...300 {
            let m = Float(step) * 0.01   // 1 cm … 3 m
            let s = DepthSignal.signal(meters: m)
            XCTAssertTrue(s >= 0 && s <= 1, "s(\(m)) = \(s) out of range")
            XCTAssertLessThanOrEqual(s, previous + eps, "not monotone at \(m)")
            previous = s
        }
    }

    // ── DS4: σ containment through BinomialCadence ──

    func testSigmaContainment() {
        let base = BinomialCadence.sigmaBase
        for step in 0...300 {
            let s = DepthSignal.signalOrFill(meters: Float(step) * 0.01)
            let sigma = BinomialCadence.sigmaForDepth(s)
            XCTAssertTrue(sigma.isFinite)
            XCTAssertGreaterThanOrEqual(sigma, base - eps)
            XCTAssertLessThanOrEqual(sigma, 2 * base + eps)
        }
    }
}
