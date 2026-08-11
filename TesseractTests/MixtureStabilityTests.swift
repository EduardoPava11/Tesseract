// MixtureStabilityTests — the MS law's exact witnesses, in Swift.
// Spec authority: spec/temporal/MixtureStability.hs (MS1–MS7 green).

import XCTest
@testable import Tesseract

final class MixtureStabilityTests: XCTestCase {

    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
    private func fitClose(_ x: DepthMixture.Fit, _ y: DepthMixture.Fit) -> Bool {
        close(x.muF, y.muF) && close(x.muB, y.muB)
            && close(x.piB, y.piB) && close(x.sigma, y.sigma)
    }

    /// MS1: constant sequence ⇒ α = 1, filtered ≡ raw.
    func testConstantIsIdentity() {
        let f = DepthMixture.Fit(muF: 0.9, muB: 0.25, piB: 0.25, sigma: 0.0625)
        let seq = Array(repeating: f, count: 64)
        let (out, gain) = DepthMixture.filtered(seq)
        XCTAssertEqual(gain, 1)
        XCTAssertTrue(out.allSatisfy { fitClose($0, f) })
    }

    /// MS2: alternating fits ⇒ α = 0, frozen at θ₀.
    func testFlickerIsFrozen() {
        let hi = DepthMixture.Fit(muF: 0.9, muB: 0.25, piB: 0.30, sigma: 0.05)
        let lo = DepthMixture.Fit(muF: 0.35, muB: 0.05, piB: 0.02, sigma: 0.03)
        let seq = (0..<64).map { $0 % 2 == 0 ? hi : lo }
        let (out, gain) = DepthMixture.filtered(seq)
        XCTAssertEqual(gain, 0)
        XCTAssertTrue(out.allSatisfy { fitClose($0, hi) })
    }

    /// MS3: exact linear drift ⇒ α = 1, tracked exactly.
    func testDriftIsTracked() {
        var seq: [DepthMixture.Fit] = []
        for k in 0..<64 {
            let mf: Double = Double(461 - k) / 512.0
            let mb: Double = Double(128 + 2 * k) / 1024.0
            seq.append(DepthMixture.Fit(muF: mf, muB: mb,
                                        piB: 0.25, sigma: 0.0625))
        }
        let (out, gain) = DepthMixture.filtered(seq)
        XCTAssertEqual(gain, 1)
        XCTAssertTrue(zip(out, seq).allSatisfy { fitClose($0, $1) })
    }

    /// MS6: order μF > μB survives filtering on every witness.
    func testOrderPreserved() {
        let hi = DepthMixture.Fit(muF: 0.9, muB: 0.25, piB: 0.30, sigma: 0.05)
        let lo = DepthMixture.Fit(muF: 0.35, muB: 0.05, piB: 0.02, sigma: 0.03)
        let seq = (0..<64).map { $0 % 3 == 0 ? lo : hi }
        let (out, _) = DepthMixture.filtered(seq)
        XCTAssertTrue(out.allSatisfy { $0.muF > $0.muB })
    }
}
