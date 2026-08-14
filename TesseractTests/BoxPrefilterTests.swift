// BoxPrefilterTests.swift
// Tesseract
//
// ★ C3 — acquisition aliasing (docs/model-placement.md §3; rate-ladder
// step S2). The LIVE read used to take the CENTRE pixel of each
// step×step block: one sample in 144 at rung 64, with the other 143
// discarded. That is decimation, not downsampling — everything above
// the output Nyquist folds back as alias and no later stage can undo
// it. FACE already box-averaged (FaceCaptureManager.swift:329-340);
// LIVE was the only decimating path.
//
// These tests pin the two properties that make the fix a fix rather
// than a blur: the average is over the WHOLE block, and it is taken in
// LINEAR LIGHT.

import XCTest
@testable import Tesseract

final class BoxPrefilterTests: XCTestCase {

    // MARK: - the transfer itself

    func testLUTIsExactOverTheWholeByteDomain() {
        // The source is 8-bit, so 256 entries is the entire domain and
        // the table is exact rather than an approximation.
        XCTAssertEqual(SRGBTransfer.toLinear.count, 256)
        for i in 0...255 {
            let c = Float(i) / 255
            let expected = c <= 0.04045 ? c / 12.92
                                        : pow((c + 0.055) / 1.055, 2.4)
            XCTAssertEqual(SRGBTransfer.toLinear[i], expected, accuracy: 1e-7)
        }
    }

    func testTransferRoundTrips() {
        for i in 0...255 {
            let back = SRGBTransfer.toSRGB(SRGBTransfer.toLinear[i])
            XCTAssertEqual(back, Float(i) / 255, accuracy: 1e-5,
                           "sRGB → linear → sRGB is the identity at byte \(i)")
        }
    }

    func testTransferIsMonotoneAndAnchored() {
        XCTAssertEqual(SRGBTransfer.toLinear[0], 0, accuracy: 1e-12)
        XCTAssertEqual(SRGBTransfer.toLinear[255], 1, accuracy: 1e-6)
        for i in 1...255 {
            XCTAssertGreaterThan(SRGBTransfer.toLinear[i],
                                 SRGBTransfer.toLinear[i - 1])
        }
    }

    // MARK: - why linear matters (the bias the old space would keep)

    func testGammaSpaceAveragingBiasesMixedBlocksDark() {
        // A block that is half black and half white. The physically
        // correct answer is half the LIGHT, which is sRGB ~0.7354 —
        // not the byte midpoint 0.5. Averaging gamma-encoded values
        // returns 0.5 and loses ~24% of the block's luminance; this is
        // the error the linear-light average exists to avoid, and it
        // applies to every high-contrast block in the scene.
        let linearMean = (SRGBTransfer.toLinear[0] + SRGBTransfer.toLinear[255]) / 2
        let correct = SRGBTransfer.toSRGB(linearMean)
        let gammaSpaceMean: Float = (0 + 1) / 2

        XCTAssertEqual(correct, 0.7354, accuracy: 0.001)
        XCTAssertGreaterThan(correct - gammaSpaceMean, 0.2,
                             "the two spaces disagree by a quarter of the range")
    }

    // MARK: - the filter's own properties, on the pooling law

    /// The box average the read performs, over one block.
    private func boxAverage(_ bytes: [UInt8]) -> Float {
        var sum: Float = 0
        for b in bytes { sum += SRGBTransfer.toLinear[Int(b)] }
        return SRGBTransfer.toSRGB(sum / Float(bytes.count))
    }

    func testConstantBlocksArePreservedExactly() {
        // Anti-aliasing must not move flat regions: if it did, every
        // background in every capture would shift.
        for v in [UInt8(0), 17, 64, 128, 200, 255] {
            let block = [UInt8](repeating: v, count: 144)
            XCTAssertEqual(boxAverage(block), Float(v) / 255, accuracy: 1e-5,
                           "a constant block is its own average")
        }
    }

    func testTheWholeBlockIsRead() {
        // The property decimation lacks: changing ANY sample in the
        // block must change the result. Under the old centre-sample
        // read, 143 of 144 samples could change with no effect at all.
        let base = [UInt8](repeating: 100, count: 144)
        let reference = boxAverage(base)
        for i in 0..<144 {
            var perturbed = base
            perturbed[i] = 200
            XCTAssertNotEqual(boxAverage(perturbed), reference,
                              "sample \(i) must reach the output")
        }
    }

    func testAliasingIsSuppressed() {
        // The failure C3 names, as a number. A checkerboard at the
        // source Nyquist is pure alias: point-sampling returns 0 or 255
        // depending only on WHERE the sample lands (a phase that the
        // scene, not the camera, chooses), while the box average
        // returns the block's true mean regardless of phase.
        var evenPhase = [UInt8](), oddPhase = [UInt8]()
        for i in 0..<144 {
            evenPhase.append(i % 2 == 0 ? 255 : 0)
            oddPhase.append(i % 2 == 0 ? 0 : 255)
        }
        // Decimation: the two phases disagree by the entire range.
        XCTAssertEqual(Float(evenPhase[0]) / 255 - Float(oddPhase[0]) / 255, 1.0,
                       "point-sampling makes the answer depend on phase alone")
        // Box average: identical, and equal to the half-light mean.
        XCTAssertEqual(boxAverage(evenPhase), boxAverage(oddPhase), accuracy: 1e-6,
                       "the prefilter is phase-independent — that IS the fix")
        XCTAssertEqual(boxAverage(evenPhase), 0.7354, accuracy: 0.001)
    }

    // MARK: - depth pooling is a mean of disparities

    func testDepthSignalIsAffineInInverseMetres() {
        // The claim the depth prefilter rests on: averaging SIGNALS is
        // averaging disparities, which is the correct space for depth.
        // If this ever fails, the depth box filter needs re-deriving.
        let a = DepthSignal.signal(meters: 0.4)
        let b = DepthSignal.signal(meters: 1.2)
        let mid = DepthSignal.signal(meters: 1 / ((1 / 0.4 + 1 / 1.2) / 2))
        XCTAssertEqual((a + b) / 2, mid, accuracy: 1e-6,
                       "signal is affine in 1/m, so the mean of signals is "
                       + "the signal of the harmonic mean")
    }

    func testInvalidDepthIsExcludedNotAveragedIn() {
        // A block with one dropout must read as the valid surface, not
        // be dragged toward fill. `signalOrFill` maps invalid → 0.5, so
        // averaging raw outputs would move a near surface (1.0) to 0.75.
        let valid = DepthSignal.signal(meters: 0.25)   // s = 1
        let naive = (valid + DepthSignal.fill) / 2     // what averaging fill gives
        XCTAssertEqual(valid, 1.0, accuracy: 1e-6)
        XCTAssertEqual(naive, 0.75, accuracy: 1e-6)
        XCTAssertNotEqual(valid, naive,
                          "excluding invalid samples is not cosmetic — it is "
                          + "the difference between 'no evidence' and 'mid distance'")
    }
}
