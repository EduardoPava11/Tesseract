// DissonanceTests.swift
// TesseractTests
//
// Swift-side gates for the Dissonance port — mirrors the axioms of
// spec/statistics/Dissonance.hs (the authority, DS1–DS16 green).

import XCTest
@testable import Tesseract

final class DissonanceTests: XCTestCase {

    // DS1–DS3: kernel shape — zero at unison, closed-form peak, the
    // x = x* landing at 0.9963 of the peak (audit-tightened pin).
    func testKernelShape() {
        XCTAssertEqual(DissonanceKernel.g(0), 0)
        XCTAssertEqual(DissonanceKernel.xHat, 0.220350, accuracy: 1e-6)
        let ratio = DissonanceKernel.g(DissonanceKernel.xStar)
                  / DissonanceKernel.g(DissonanceKernel.xHat)
        XCTAssertEqual(ratio, 0.9963, accuracy: 1e-4)
        // Monotone tail: strictly decreasing past the peak.
        XCTAssertGreaterThan(DissonanceKernel.g(0.5), DissonanceKernel.g(1.0))
        XCTAssertGreaterThan(DissonanceKernel.g(1.0), DissonanceKernel.g(3.0))
    }

    // The chart: 12 pinned integer frequencies, symmetric zero-diag G.
    func testChart() {
        XCTAssertEqual(DissonanceKernel.freqs12,
                       [500, 1000, 2000, 4000,
                        625, 1250, 2500, 5000,
                        750, 1500, 3000, 6000])
        for i in 0..<12 {
            XCTAssertEqual(DissonanceKernel.gMat[i][i], 0)
            for j in 0..<12 {
                XCTAssertEqual(DissonanceKernel.gMat[i][j],
                               DissonanceKernel.gMat[j][i])
                XCTAssertGreaterThanOrEqual(DissonanceKernel.gMat[i][j], 0)
            }
        }
    }

    // DS9 polarization: D(a+b) == D(a) + D(b) + X(a,b).
    func testPolarization() {
        var s = 7
        func u() -> Double {
            s = (1103515245 &* s &+ 12345) % 2147483648
            return Double(s) / 2147483648.0
        }
        let a = (0..<12).map { _ in u() }
        let b = (0..<12).map { _ in u() }
        let joint = zip(a, b).map(+)
        XCTAssertEqual(DissonanceKernel.quadD(joint),
                       DissonanceKernel.quadD(a) + DissonanceKernel.quadD(b)
                           + DissonanceKernel.bilinX(a, b),
                       accuracy: 1e-9)
    }

    // The spec's pinned uniform-occupancy tuning witness: (269, 836).
    func testUniformTuningWitness() {
        let uniform = [Double](repeating: 0.25, count: 12)
        let t = DissonanceKernel.designTuning(amps12: uniform)
        XCTAssertEqual(t.kG, 269)
        XCTAssertEqual(t.kB, 836)
    }

    // DS12: near/far spans one exact octave — full depth contrast
    // lands at x = x* exactly; equal depths are exactly silent.
    func testUrgencyTheorems() {
        XCTAssertEqual(DissonanceKernel.xBond(0, 1), DissonanceKernel.xStar)
        XCTAssertEqual(DissonanceKernel.xBond(0.5, 0.5), 0)
        XCTAssertEqual(DissonanceKernel.urgencyBond(w1: 1, w2: 1, dA: 0.7, dB: 0.7), 0)
        // Monotone in contrast (lattice never passes the peak: x ≤ x* < x̂).
        let low = DissonanceKernel.urgencyBond(w1: 1, w2: 1, dA: 0.8, dB: 1)
        let high = DissonanceKernel.urgencyBond(w1: 1, w2: 1, dA: 0, dB: 1)
        XCTAssertGreaterThan(high, low)
        XCTAssertGreaterThan(low, 0)
        // Bilinear in mass.
        XCTAssertEqual(DissonanceKernel.urgencyBond(w1: 2, w2: 3, dA: 0, dB: 1),
                       6 * DissonanceKernel.urgencyBond(w1: 1, w2: 1, dA: 0, dB: 1),
                       accuracy: 1e-12)
    }

    // Field on synthetic bursts: constant depth ⇒ zero urgency;
    // a near/far split ⇒ positive; tunings present at both cadences.
    func testFieldOnSyntheticBursts() throws {
        func makeFrames(depth: (Int, Int) -> Float) -> [QuantizedFrame] {
            (0..<64).map { f in
                let indices = [UInt8](repeating: 0, count: 4096)
                let depths = (0..<4096).map { p in depth(f, p) }
                return QuantizedFrame(
                    index: f, paletteIndices: indices, rawRGB: nil,
                    depths: depths,
                    measure: BirkhoffMeasure(paletteIndices: indices),
                    subjectAnalysis: nil, anchorTrace: nil, timestamp: 0)
            }
        }
        let flat = try XCTUnwrap(DissonanceField.telemetry(
            frames: makeFrames(depth: { _, _ in 0.5 })))
        XCTAssertEqual(flat.urgencyTotal, 0)
        XCTAssertEqual(flat.urgencyEnvelope.count, 16)
        XCTAssertEqual(flat.sliceTunings.count, 16)
        XCTAssertEqual(flat.voxelUrgency.count, 4096)

        // Left half near (d=1), right half far (d=0): the seam beats.
        let split = try XCTUnwrap(DissonanceField.telemetry(
            frames: makeFrames(depth: { _, p in (p % 64) < 32 ? 1 : 0 })))
        XCTAssertGreaterThan(split.urgencyTotal, 0)

        // Partial bursts are refused.
        XCTAssertNil(DissonanceField.telemetry(
            frames: Array(makeFrames(depth: { _, _ in 0.5 }).prefix(63))))
    }
}
