// TensorANEParityTests.swift
// Tesseract
//
// ANE ↔ CPU parity for the capture tensor's ENCODE, per the placement
// laws spec/neural/TensorEncoder.hs TA1–TA9. This is what makes
// TensorANE a TWIN rather than a second path: one law, two engines,
// and a live gate proving they agree.
//
// ★ WHAT "AGREE" MEANS HERE, AND WHY IT IS NOT BIT-EXACTNESS. The
// engine is fp16. TA3 says a flipped sign costs exactly 2·min(|r|, g)
// of extra reconstruction error, and a flip can only happen where |r|
// is under fp16's resolution — so the law to gate is not "no
// disagreement" but "every disagreement is a residual the engine
// could not see". That is the same shape as XP2, which gates the
// assignment stage's near-ties. A test demanding bit-exactness across
// precisions would fail for a lawful reason, and a test demanding
// nothing would pass for an unlawful one.
//
// Skips when TensorEncode.mlmodelc is not bundled. On simulator
// CoreML runs on CPU compute units — correctness is verified here;
// ANE residency and latency belong to the device pass.

import XCTest
@testable import Tesseract

final class TensorANEParityTests: XCTestCase {

    /// fp16's absolute resolution near the mid-range where the cube
    /// lives. Not a tuning knob: 2^-11 is one ulp at 1.0.
    private static let ulp: Float = 0.000_488_281_25

    private func fixture() -> CaptureTensor.Level {
        var l = CaptureTensor.Level(frames: 64, side: 64)
        for t in 0..<64 {
            let cx = 32 + 12 * sin(2 * .pi * Float(t) / 64)
            let cy = 32 + 8 * cos(2 * .pi * Float(t) / 64)
            for y in 0..<64 {
                for x in 0..<64 {
                    let d2 = (Float(x) - cx) * (Float(x) - cx)
                           + (Float(y) - cy) * (Float(y) - cy)
                    let fig = exp(-d2 / 90)
                    let ground = 0.42 + 0.02 * sin(0.09 * Float(x)
                                                   + 0.05 * Float(y))
                    for (c, w) in [Float(1.0), 0.35, -0.2].enumerated() {
                        l.set(t, y, x, c,
                              min(1, max(0, ground + w * fig * 0.45)))
                    }
                }
            }
        }
        return l
    }

    func testEngineAgreesWithTheLawUpToItsOwnResolution() throws {
        try XCTSkipUnless(TensorANE.isAvailable,
                          "TensorEncode.mlmodelc not bundled")

        let fine = fixture()
        let law = CaptureTensor.transform(fine)
        let engine = try XCTUnwrap(TensorANE.transform(fine))

        // The coarse picture: two poolings of fp16 accumulate a few
        // ulp, and TA5 says the whole rung has 16 bits of headroom
        // inside CT2's allocation, so a few ulp is inside the budget
        // by construction rather than by tolerance.
        var worstL16: Float = 0
        for i in 0..<law.l16.data.count {
            worstL16 = max(worstL16,
                           abs(law.l16.data[i] - engine.l16.data[i]))
        }
        XCTAssertLessThan(worstL16, 8 * Self.ulp,
                          "l16 drifted beyond the engine's own resolution")

        // ★ TA3/TA4: every sign disagreement must be a residual the
        // engine could not see. Recompute the residual for each
        // disagreement and check it against fp16's resolution.
        let l32 = CaptureTensor.poolDown(fine)
        let r64 = CaptureTensor.residual(fine, CaptureTensor.parentUp(l32))
        var disagreements = 0
        var worstResidual: Float = 0
        for i in 0..<law.sign64.count where law.sign64[i] != engine.sign64[i] {
            disagreements += 1
            worstResidual = max(worstResidual, abs(r64.data[i]))
        }
        let rate = Double(disagreements) / Double(law.sign64.count)
        print("TENSOR ANE PARITY: sign64 \(100 * (1 - rate))% agree, "
              + "worst disagreeing |r| \(worstResidual) vs ulp \(Self.ulp)")
        XCTAssertLessThanOrEqual(worstResidual, 4 * Self.ulp,
                                 "TA4: a disagreement outside fp16's reach "
                                 + "is a defect, not a near-tie")

        // The step sizes are pooled magnitudes, so they inherit the
        // same resolution and no more.
        for i in 0..<law.g32.data.count {
            XCTAssertEqual(law.g32.data[i], engine.g32.data[i],
                           accuracy: 8 * Self.ulp)
            XCTAssertEqual(law.g64.data[i], engine.g64.data[i],
                           accuracy: 8 * Self.ulp)
        }
    }

    func testEngineRefusesAShapeItWasNotCompiledFor() throws {
        try XCTSkipUnless(TensorANE.isAvailable,
                          "TensorEncode.mlmodelc not bundled")
        // SHAPE, not failure: the live solve reads at rung 16, which
        // this graph is not compiled for. The twin runs; nothing is
        // wrong; and nothing is silently substituted.
        let coarse = CaptureTensor.Level(frames: 16, side: 16)
        XCTAssertNil(TensorANE.transform(coarse))
    }
}
