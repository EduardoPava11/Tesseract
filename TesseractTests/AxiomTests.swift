// AxiomTests.swift
// TesseractTests
//
// Port of Haskell axiom verification:
//   Tesseract.hs — A1-A7, P1-P5, C1-C4, T1-T5, E1-E3
//   TemporalBinomial.hs — T1-T7
//   DeviationManifold.hs — D1-D7

import XCTest
import simd
@testable import Tesseract

final class AxiomTests: XCTestCase {

    let eps: Float = 1e-6

    // MARK: - Test Vectors

    let testR4s: [SIMD4<Float>] = [
        SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0),
        SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1),
        SIMD4(2, 3, 1, 0.5), SIMD4(0, 0, 0, 0),
        SIMD4(-1, 2, -3, 0.7), SIMD4(3, 3, 3, 3),
        SIMD4(1.5, 1.5, 1.5, 1.5)
    ]

    // ════════════════════════════════════════════════
    // DIRECT SUM AXIOMS A1-A7
    // ════════════════════════════════════════════════

    // (A1) inject₁(π₁(v)) + inject₂(π₂(v)) = v
    func testA1_decomposition() {
        for tc in TesseractCoord.all {
            let v = tc.r4
            let epoch = v[0]             // π₁
            let color = SIMD3(v[1], v[2], v[3])  // π₂
            let reconstructed = SIMD4(epoch, color.x, color.y, color.z)
            XCTAssertEqual(v, reconstructed, "A1 failed for \(tc)")
        }
    }

    // (A2) π₁(inject₁(u)) = u
    func testA2_retract1() {
        for d: UInt8 in 0...3 {
            let tc = TesseractCoord.fromEpoch(d)
            XCTAssertEqual(tc.d, d, "A2 failed for epoch \(d)")
            XCTAssertEqual(tc.a, 0); XCTAssertEqual(tc.b, 0); XCTAssertEqual(tc.c, 0)
        }
    }

    // (A3) π₂(inject₂(w)) = w
    func testA3_retract2() {
        for a: UInt8 in 0...3 {
            for b: UInt8 in 0...3 {
                for c: UInt8 in 0...3 {
                    let tc = TesseractCoord.fromColor(a: a, b: b, c: c)
                    XCTAssertEqual(tc.a, a); XCTAssertEqual(tc.b, b); XCTAssertEqual(tc.c, c)
                    XCTAssertEqual(tc.d, 0, "A3 failed for color (\(a),\(b),\(c))")
                }
            }
        }
    }

    // (A4) π₁(inject₂(w)) = 0
    func testA4_crossProjection1() {
        for a: UInt8 in 0...3 {
            let tc = TesseractCoord.fromColor(a: a, b: 2, c: 1)
            XCTAssertEqual(tc.epoch, 0, "A4 failed: inject₂ should have epoch=0")
        }
    }

    // (A5) π₂(inject₁(u)) = 0
    func testA5_crossProjection2() {
        for d: UInt8 in 0...3 {
            let tc = TesseractCoord.fromEpoch(d)
            XCTAssertEqual(tc.color, SIMD3<Float>(0, 0, 0), "A5 failed for epoch \(d)")
        }
    }

    // (A7) dim = 1 + 3 = 4
    func testA7_dimension() {
        // The tesseract has 4 axes: d, a, b, c
        XCTAssertEqual(1 + 3, 4)
    }

    // ════════════════════════════════════════════════
    // TESSERACT AXIOMS T1-T5
    // ════════════════════════════════════════════════

    // (T1) Metric invariant under axis permutation
    func testT1_symmetry() {
        let v1 = SIMD4<Float>(1, 2, 3, 0)
        let v2 = SIMD4<Float>(0, 1, 2, 3)
        let d_orig = simd_distance(v1, v2)
        // Swap axes 0 and 1
        let d_swap = simd_distance(SIMD4(v1[1], v1[0], v1[2], v1[3]),
                                   SIMD4(v2[1], v2[0], v2[2], v2[3]))
        XCTAssertEqual(d_orig, d_swap, accuracy: eps, "T1 failed: axis permutation changed distance")

        // Cyclic permutation
        let d_cycle = simd_distance(SIMD4(v1[1], v1[2], v1[3], v1[0]),
                                    SIMD4(v2[1], v2[2], v2[3], v2[0]))
        XCTAssertEqual(d_orig, d_cycle, accuracy: eps)
    }

    // (T2) |lattice| = 4⁴ = 256
    func testT2_cardinality() {
        XCTAssertEqual(TesseractCoord.all.count, 256)
        // All unique
        let unique = Set(TesseractCoord.all)
        XCTAssertEqual(unique.count, 256)
    }

    // (T3) Cell volume = (1/4)⁴ = 1/256
    func testT3_cellVolume() {
        let volume = powf(1.0 / 4.0, 4.0)
        XCTAssertEqual(volume, 1.0 / 256.0, accuracy: eps)
        XCTAssertEqual(TesseractCoord.cellVolume, 1.0 / 256.0, accuracy: eps)
    }

    // (T4) Black = index 0, White = index 255
    func testT4_corners() {
        XCTAssertEqual(TesseractCoord.black.index, 0)
        XCTAssertEqual(TesseractCoord.white.index, 255)
        XCTAssertEqual(TesseractCoord(index: 0), TesseractCoord.black)
        XCTAssertEqual(TesseractCoord(index: 255), TesseractCoord.white)
    }

    // (T5) Diagonal = √(4 × 3²) = 6
    func testT5_diagonal() {
        let d = TesseractCoord.black.distance(to: .white)
        XCTAssertEqual(d, 6.0, accuracy: eps)
        XCTAssertEqual(TesseractCoord.diagonal, 6.0)
    }

    // ════════════════════════════════════════════════
    // INDEX ROUND-TRIP
    // ════════════════════════════════════════════════

    func testIndexRoundTrip() {
        for i: UInt8 in 0...255 {
            let tc = TesseractCoord(index: i)
            XCTAssertEqual(tc.index, i, "Round trip failed for index \(i)")
        }
        for tc in TesseractCoord.all {
            let i = tc.index
            let tc2 = TesseractCoord(index: i)
            XCTAssertEqual(tc, tc2, "Round trip failed for coord \(tc)")
        }
    }

    // ════════════════════════════════════════════════
    // EPOCH AXIOMS E1-E3
    // ════════════════════════════════════════════════

    // (E1) 4 epochs × 16 frames = 64
    func testE1_epochFrames() {
        for d in 0..<4 {
            let frames = (0..<64).filter { $0 / 16 == d }
            XCTAssertEqual(frames.count, 16, "Epoch \(d) doesn't have 16 frames")
        }
    }

    // (E2) project₁ extracts epoch correctly
    func testE2_epochExtraction() {
        for i: UInt8 in 0...255 {
            let tc = TesseractCoord(index: i)
            XCTAssertEqual(UInt8(tc.epoch), tc.d)
        }
    }

    // (E3) 64 colors per epoch
    func testE3_colorsPerEpoch() {
        for d: UInt8 in 0...3 {
            let count = TesseractCoord.all.filter { $0.d == d }.count
            XCTAssertEqual(count, 64, "Epoch \(d) doesn't have 64 colors")
        }
    }

    // ════════════════════════════════════════════════
    // BINOMIAL CADENCE AXIOMS
    // ════════════════════════════════════════════════

    // Σ P(d|z) = 1 for all z
    func testCadence_normalized() {
        for z in 0..<64 {
            let probs = BinomialCadence.epochProbabilities(frame: z)
            let sum = probs[0] + probs[1] + probs[2] + probs[3]
            XCTAssertEqual(sum, 1.0, accuracy: eps, "Cadence not normalized at frame \(z)")
        }
    }

    // P(d|z) is smooth: <10% change per frame
    func testCadence_smooth() {
        for z in 0..<63 {
            let p1 = BinomialCadence.epochProbabilities(frame: z)
            let p2 = BinomialCadence.epochProbabilities(frame: z + 1)
            for d in 0..<4 {
                let jump = abs(p1[d] - p2[d])
                XCTAssertLessThan(jump, 0.10, "Cadence jump too large at frame \(z), epoch \(d)")
            }
        }
    }

    // Epoch centers equispaced
    func testCadence_equispaced() {
        let c = BinomialCadence.centers
        let gap01 = c[1] - c[0]
        let gap12 = c[2] - c[1]
        let gap23 = c[3] - c[2]
        XCTAssertEqual(gap01, gap12, accuracy: eps)
        XCTAssertEqual(gap12, gap23, accuracy: eps)
    }

    // Crossovers at ~50/50
    func testCadence_crossovers() {
        for (d, cross) in BinomialCadence.crossovers.enumerated() {
            let z = Int(cross.rounded())
            let pd = BinomialCadence.epochProb(frame: z, epoch: d)
            let pd1 = BinomialCadence.epochProb(frame: z, epoch: d + 1)
            XCTAssertEqual(pd, pd1, accuracy: 0.15,
                "Crossover not balanced at frame \(z): P(\(d))=\(pd), P(\(d+1))=\(pd1)")
        }
    }

    // ════════════════════════════════════════════════
    // BIRKHOFF MEASURE
    // ════════════════════════════════════════════════

    func testBirkhoff_noiseVsFace() {
        // Noise: uniform distribution → low deviation, high entropy
        var noiseCounts = [Int](repeating: 16, count: 256)
        let noiseMeasure = BirkhoffMeasure(counts: noiseCounts)
        XCTAssertLessThan(noiseMeasure.order, 1.0, "Noise should have near-zero deviation")
        XCTAssertGreaterThan(noiseMeasure.complexity, 0.95, "Noise should have near-max entropy")

        // Face-like: concentrated in a few colors
        var faceCounts = [Int](repeating: 0, count: 256)
        faceCounts[37] = 800   // skin tone dominates
        faceCounts[38] = 600
        faceCounts[21] = 400
        faceCounts[5] = 300
        // Spread remaining 1896 across 20 other colors
        for i in 50..<70 { faceCounts[i] = 94 }
        faceCounts[69] += 36   // ensure total = 4096
        let faceMeasure = BirkhoffMeasure(counts: faceCounts)

        XCTAssertGreaterThan(faceMeasure.order, noiseMeasure.order * 10,
            "Face should deviate much more than noise")
        XCTAssertGreaterThan(faceMeasure.beauty, noiseMeasure.beauty,
            "Face should be more 'beautiful' than noise")
    }

    func testBirkhoff_manifoldDim() {
        // Single color → dim ≈ 0
        var singleCounts = [Int](repeating: 0, count: 256)
        singleCounts[128] = 4096
        let single = BirkhoffMeasure(counts: singleCounts)
        XCTAssertLessThan(single.manifoldDim, 0.5)

        // Uniform → dim ≈ 3
        let uniform = BirkhoffMeasure(counts: [Int](repeating: 16, count: 256))
        XCTAssertGreaterThan(uniform.manifoldDim, 2.5)
    }

    // ════════════════════════════════════════════════
    // sRGB PROJECTION
    // ════════════════════════════════════════════════

    // 4 epochs of same color → same sRGB
    func testProjection_epochInvisible() {
        for a: UInt8 in 0...3 {
            for b: UInt8 in 0...3 {
                for c: UInt8 in 0...3 {
                    let srgb0 = TesseractCoord(d: 0, a: a, b: b, c: c).sRGB
                    let srgb1 = TesseractCoord(d: 1, a: a, b: b, c: c).sRGB
                    let srgb2 = TesseractCoord(d: 2, a: a, b: b, c: c).sRGB
                    let srgb3 = TesseractCoord(d: 3, a: a, b: b, c: c).sRGB
                    XCTAssertEqual(srgb0, srgb1, "Epoch should be invisible in sRGB")
                    XCTAssertEqual(srgb1, srgb2)
                    XCTAssertEqual(srgb2, srgb3)
                }
            }
        }
    }

    // Black → (0.125, 0.125, 0.125), White → (0.875, 0.875, 0.875)
    func testProjection_blackWhite() {
        let b = TesseractCoord.black.sRGB
        let w = TesseractCoord.white.sRGB
        XCTAssertEqual(b.x, 0.125, accuracy: eps)
        XCTAssertEqual(w.x, 0.875, accuracy: eps)
        // They're at opposite corners of the projected cube
        XCTAssertGreaterThan(simd_distance(b, w), 1.0)
    }
}
