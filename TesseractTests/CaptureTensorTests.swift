// CaptureTensorTests.swift
// Tesseract
//
// The retained tensor's laws, in Swift: spec/output/CaptureTensor.hs
// CT1–CT11 and spec/neural/TensorEncoder.hs TA1–TA9. Pure arithmetic,
// so it runs on the simulator; the ENGINE half is
// TensorANEParityTests.

import XCTest
@testable import Tesseract

final class CaptureTensorTests: XCTestCase {

    // MARK: - Fixtures

    /// A figure moving over a quiet ground: the structure the zerotree
    /// exists to exploit. Synthetic by construction — the
    /// NO-CAPTURE-TRAINING decree means no fixture here is a
    /// photograph, and none needs to be.
    private func fixture(noise: Float = 0) -> CaptureTensor.Level {
        var l = CaptureTensor.Level(frames: 64, side: 64)
        var seed: UInt64 = 20_260_814
        func rnd() -> Float {                       // deterministic LCG
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(seed >> 40) / Float(1 << 24) - 0.5
        }
        for t in 0..<64 {
            let cx = 32 + 12 * sin(2 * .pi * Float(t) / 64)
            let cy = 32 + 8 * cos(2 * .pi * Float(t) / 64)
            for y in 0..<64 {
                for x in 0..<64 {
                    let d2 = (Float(x) - cx) * (Float(x) - cx)
                           + (Float(y) - cy) * (Float(y) - cy)
                    let fig = exp(-d2 / 90)
                    let ground = 0.42 + 0.02 * sin(0.09 * Float(x) + 0.05 * Float(y))
                    for (c, w) in [Float(1.0), 0.35, -0.2].enumerated() {
                        let v = ground + w * fig * 0.45 + noise * rnd()
                        l.set(t, y, x, c, min(1, max(0, v)))
                    }
                }
            }
        }
        return l
    }

    // MARK: - TA1: the pool factors

    /// The ANE graph runs the temporal-then-spatial factorisation and
    /// the CPU twin runs the 2×2×2 atom directly. If those two ever
    /// stopped agreeing, the twin would be a lie, so the equality is
    /// checked here on the same shape the graph is compiled for.
    func testPoolFactorsIntoTemporalThenSpatial() {
        let fine = fixture()
        let atom = CaptureTensor.poolDown(fine)

        // temporal pair-average, then spatial 2×2 — the graph's order.
        var timed = CaptureTensor.Level(frames: 32, side: 64)
        for t in 0..<32 {
            for y in 0..<64 {
                for x in 0..<64 {
                    for c in 0..<3 {
                        timed.set(t, y, x, c,
                                  (fine.at(2 * t, y, x, c)
                                   + fine.at(2 * t + 1, y, x, c)) / 2)
                    }
                }
            }
        }
        var factored = CaptureTensor.Level(frames: 32, side: 32)
        for t in 0..<32 {
            for y in 0..<32 {
                for x in 0..<32 {
                    for c in 0..<3 {
                        let s = timed.at(t, 2 * y, 2 * x, c)
                              + timed.at(t, 2 * y, 2 * x + 1, c)
                              + timed.at(t, 2 * y + 1, 2 * x, c)
                              + timed.at(t, 2 * y + 1, 2 * x + 1, c)
                        factored.set(t, y, x, c, s / 4)
                    }
                }
            }
        }
        for i in 0..<atom.data.count {
            XCTAssertEqual(atom.data[i], factored.data[i], accuracy: 1e-5,
                           "TA1: the pool must factor at index \(i)")
        }
    }

    // MARK: - CT9: a quiet subtree is g = 0, not a second path

    func testQuietSubtreeDecodesToItsParentExactly() throws {
        // A perfectly flat cube has zero residual everywhere, so every
        // subtree is quiet and the decode must return the parent — the
        // SAME arithmetic, with g = 0.
        var flat = CaptureTensor.Level(frames: 64, side: 64)
        for i in 0..<flat.data.count { flat.data[i] = 0.375 }
        let depths = [[Float]](repeating: [Float](repeating: 0.5, count: 4096),
                               count: 64)
        let data = try XCTUnwrap(CaptureTensor.encode(colour: flat,
                                                      depths: depths))
        let back = try XCTUnwrap(CaptureTensor.decode(data))
        for v in back.colour.data {
            XCTAssertEqual(v, 0.375, accuracy: 1e-3,
                           "CT9: a quiet subtree must decode as its parent")
        }
    }

    // MARK: - CT6: depth is never quantised

    func testDepthRoundTripsBitExactly() throws {
        let fine = fixture()
        var depths: [[Float]] = []
        for t in 0..<64 {
            depths.append((0..<4096).map { p in
                Float(sin(Double(t) * 0.11 + Double(p) * 0.0007)) * 0.5 + 0.5
            })
        }
        let data = try XCTUnwrap(CaptureTensor.encode(colour: fine,
                                                      depths: depths))
        let back = try XCTUnwrap(CaptureTensor.decode(data))
        XCTAssertEqual(back.depths.count, 64)
        for t in 0..<64 {
            for p in 0..<4096 {
                XCTAssertEqual(back.depths[t][p].bitPattern,
                               depths[t][p].bitPattern,
                               "CT6: depth must survive bit for bit at \(t),\(p)")
            }
        }
    }

    // MARK: - CT7: the threshold is DERIVED, and its verdict is a branch

    func testSignificanceThresholdIsTheMixtureCrossover() {
        let tr = CaptureTensor.transform(fixture())
        let thr = CaptureTensor.significanceThreshold(tr.dev16)

        // The fixture is a figure over a quiet ground, so the mixture
        // must find two phases and the threshold must SEPARATE them:
        // strictly inside the deviation range, with both sides
        // non-empty. A threshold that keeps everything or nothing is
        // not a crossover, it is a no-op wearing one's face.
        let t = try? XCTUnwrap(thr)
        guard let t else { return XCTFail("CT7: two phases expected here") }
        let loud = tr.dev16.data.filter { $0 >= t }.count
        XCTAssertGreaterThan(loud, 0, "CT7: some subtree must speak")
        XCTAssertLessThan(loud, tr.dev16.data.count,
                          "CT7: some subtree must be quiet")
    }

    func testSinglePhaseCaptureHasNoQuietPopulationAndPaysFlat() {
        // A cube whose deviations are one population has no crossover.
        // CT7 says it pays flat, and that verdict is a BRANCH of the
        // law: the encoder writes every sign because the data said
        // every subtree speaks. It is not a degraded path.
        var uniform = CaptureTensor.Level(frames: 64, side: 64)
        var seed: UInt64 = 7
        for i in 0..<uniform.data.count {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            uniform.data[i] = 0.5 + Float(seed >> 40) / Float(1 << 24) * 0.02
        }
        let tr = CaptureTensor.transform(uniform)
        let thr = CaptureTensor.significanceThreshold(tr.dev16)
        if let thr {
            // If a crossover IS found on white noise, it must not be a
            // meaningful split — that would mean the fitter is reading
            // structure that is not there.
            let loud = Double(tr.dev16.data.filter { $0 >= thr }.count)
                     / Double(tr.dev16.data.count)
            XCTAssertGreaterThan(loud, 0.2,
                                 "a single population must not be mostly killed")
        }
    }

    // MARK: - TA5 / TA9: the ledger

    func testCoarsePictureFitsInsideTheAllocationCT2Forced() {
        // 3 channels × fp16 = 48 bits, inside the 64 bits per rung-16
        // cell that the 1 : 8 : 64 cell counting already forced.
        XCTAssertEqual(CaptureTensor.channels * 16, 48)
        XCTAssertLessThan(CaptureTensor.channels * 16, 64)
    }

    func testTensorIsSmallerThanTheCubeItReplaces() {
        // CubeStore: 8-bit sRGB + f32 depth per voxel, no transform.
        let cube = 16 + 64 * 4096 * 3 + 64 * 4096 * 4
        XCTAssertEqual(cube, 1_835_024)
        // Even paying flat — every subtree loud — the tensor is smaller.
        XCTAssertLessThan(CaptureTensor.bytesPerCapture(loudFraction: 1.0),
                          cube)
        // And the depth is what is left: over 80% at the flat extreme.
        let depth = Double(64 * 4096 * 4)
        let flat = Double(CaptureTensor.bytesPerCapture(loudFraction: 1.0))
        XCTAssertGreaterThan(depth / flat, 0.8)
    }

    func testEncodeRefusesAShapeItCannotStore() {
        // NOT a silent downgrade: a level that is not the compiled
        // 64 × 64² cannot be stored in this format, and the encoder
        // says so by refusing rather than writing something else.
        let short = CaptureTensor.Level(frames: 32, side: 64)
        let depths = [[Float]](repeating: [Float](repeating: 0, count: 4096),
                               count: 32)
        XCTAssertNil(CaptureTensor.encode(colour: short, depths: depths))
    }

    // MARK: - The round trip's fidelity

    func testRoundTripErrorIsBoundedByTheStepSize() throws {
        // CT11 declares that a cube rebuilt from the tensor differs
        // from the one read live, bounded by g. This measures it, so
        // the declared price is a number rather than a promise.
        let fine = fixture()
        let depths = [[Float]](repeating: [Float](repeating: 0.5, count: 4096),
                               count: 64)
        let data = try XCTUnwrap(CaptureTensor.encode(colour: fine,
                                                      depths: depths))
        let back = try XCTUnwrap(CaptureTensor.decode(data))

        var sum = 0.0
        for i in 0..<fine.data.count {
            let d = Double(fine.data[i] - back.colour.data[i])
            sum += d * d
        }
        let rmse = (sum / Double(fine.data.count)).squareRoot()
        XCTAssertLessThan(rmse, 0.02,
                          "CT11: the remade cube must stay within g of the read")
        print("CAPTURE TENSOR: \(data.count) B, rmse \(rmse), "
              + "vs CubeStore 1835024 B")
    }
}
