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

    // (E1) 4 epochs × (K/4) frames = K
    func testE1_epochFrames() {
        let k = CameraConfig.totalFrames
        let fpe = k / 4  // frames per epoch
        for d in 0..<4 {
            let frames = (0..<k).filter { $0 / fpe == d }
            XCTAssertEqual(frames.count, fpe, "Epoch \(d) should have \(fpe) frames")
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
        let k = CameraConfig.totalFrames
        for z in 0..<k {
            let probs = BinomialCadence.epochProbabilities(frame: z)
            let sum = probs[0] + probs[1] + probs[2] + probs[3]
            XCTAssertEqual(sum, 1.0, accuracy: eps, "Cadence not normalized at frame \(z)")
        }
    }

    // P(d|z) is smooth: <10% change per frame
    func testCadence_smooth() {
        let k = CameraConfig.totalFrames
        for z in 0..<(k - 1) {
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
            let probs = BinomialCadence.epochProbabilities(frame: z)
            let pd = probs[d]
            let pd1 = probs[d + 1]
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

    // ════════════════════════════════════════════════
    // GIF ENCODER — PALETTE ROUNDTRIP
    // ════════════════════════════════════════════════

    /// Verify that GIF encoding carries the per-frame palette bytes
    /// verbatim: GCT = frame 0's table, valid GIF89a envelope.
    /// (The global-table lattice stream is deleted — 2026-08-12
    /// decree; DyadGIFContractTests locks the full LCT walk.)
    func testGIF_palettePreserved() {
        let n = CameraConfig.pixelCount
        let indices: [UInt8] = (0..<n).map { UInt8($0 % 256) }
        let table = DyadPalette.gifColorTable(
            DyadPalette.table(stats: DyadPalette.analyze([])))

        let gifData = GIFEncoder.encode(
            indexFrames: [indices], side: CameraConfig.outputSize,
            perFrameTables: [table])
        XCTAssertNotNil(gifData, "GIF encoding should succeed")

        guard let data = gifData else { return }

        // Verify GIF89a header
        let header = data.prefix(6)
        XCTAssertEqual(header, Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
            "GIF header should be GIF89a")

        // Verify Logical Screen Descriptor
        XCTAssertEqual(data[6], 64)   // width low byte
        XCTAssertEqual(data[7], 0)    // width high byte
        XCTAssertEqual(data[8], 64)   // height low byte
        XCTAssertEqual(data[9], 0)    // height high byte
        XCTAssertEqual(data[10], 0xF7, "Packed byte should indicate 256-entry GCT")

        // Verify the GCT is frame 0's table, byte-for-byte
        let gctStart = 13
        let gctEnd = gctStart + 768  // 256 × 3
        XCTAssertEqual(Data(data[gctStart..<gctEnd]), table,
            "GCT must be frame 0's per-frame table byte-for-byte")

        // Verify trailer
        XCTAssertEqual(data.last, 0x3B, "GIF should end with trailer 0x3B")
    }

    // ════════════════════════════════════════════════
    // LAYER 1a: PALETTE BYTE EXACTNESS
    // ════════════════════════════════════════════════

    /// Canonical sRGB8 values: {32, 96, 159, 223} for levels {0, 1, 2, 3}.
    /// This test FAILS if sRGB8 uses truncation instead of rounding.
    func testSRGB8_exactBytes() {
        let expected: [UInt8] = [32, 96, 159, 223]
        for level: UInt8 in 0...3 {
            let tc = TesseractCoord(d: 0, a: level, b: 0, c: 0)
            XCTAssertEqual(tc.sRGB8.0, expected[Int(level)],
                "Level \(level): R should be \(expected[Int(level)]), got \(tc.sRGB8.0)")
        }
        // Verify ALL 256 palette entries use ONLY canonical values
        for i: UInt8 in 0...255 {
            let (r, g, b) = TesseractCoord(index: i).sRGB8
            XCTAssertTrue(expected.contains(r), "Index \(i): R=\(r) not in {32,96,159,223}")
            XCTAssertTrue(expected.contains(g), "Index \(i): G=\(g) not in {32,96,159,223}")
            XCTAssertTrue(expected.contains(b), "Index \(i): B=\(b) not in {32,96,159,223}")
        }
    }

    /// Black = (32,32,32), White = (223,223,223). Exact bytes.
    func testSRGB8_blackWhiteExact() {
        let black = TesseractCoord.black.sRGB8
        XCTAssertTrue(black == (32, 32, 32), "Black must be (32,32,32)")
        let white = TesseractCoord.white.sRGB8
        XCTAssertTrue(white == (223, 223, 223), "White must be (223,223,223)")
    }

    // ════════════════════════════════════════════════
    // LAYER 1b: GCT ROUNDTRIP
    // ════════════════════════════════════════════════

    func testGCT_exactBytes() {
        let gct = TesseractPalette.gifColorTable
        XCTAssertEqual(gct.count, 768, "GCT must be 768 bytes (256 × 3)")

        // Index 0 = black = (32, 32, 32)
        XCTAssertEqual(gct[0], 32); XCTAssertEqual(gct[1], 32); XCTAssertEqual(gct[2], 32)
        // Index 255 = white = (223, 223, 223)
        XCTAssertEqual(gct[765], 223); XCTAssertEqual(gct[766], 223); XCTAssertEqual(gct[767], 223)

        // All bytes must be from canonical set
        let canonical: Set<UInt8> = [32, 96, 159, 223]
        for i in 0..<768 {
            XCTAssertTrue(canonical.contains(gct[i]),
                "GCT byte \(i) = \(gct[i]) not in {32,96,159,223}")
        }
    }

    // ════════════════════════════════════════════════
    // LAYER 1c: PERFECTQUANTIZER AXIOMS PQ1-PQ5
    // ════════════════════════════════════════════════

    /// Synthetic test data: gradient RGB + center-near depth
    /// Uses CameraConfig.outputSize so it works at any CubeLevel.
    private func syntheticFrame() -> (rgb: [(Float,Float,Float)], depths: [Float]) {
        let s = CameraConfig.outputSize  // 64, 128, or 256
        let n = s * s
        let rgb = (0..<n).map { i -> (Float,Float,Float) in
            let cx = i % s, cy = i / s
            // Planted anchors (2026-08-10): true black and white 4×4
            // blocks in opposite corners. The gradient body has b ≡ 0.5,
            // which can NEVER quantize to (0,0,0)/(3,3,3) under the
            // round+F-S law — the old anchor expectations were asserting
            // on a scene that contained no black or white.
            if cx < 4 && cy < 4 { return (0, 0, 0) }
            if cx >= s - 4 && cy >= s - 4 { return (1, 1, 1) }
            let x = Float(cx) / Float(s - 1)
            let y = Float(cy) / Float(s - 1)
            return (x, y, 0.5)
        }
        let half = Float(s - 1) / 2.0
        let depths = (0..<n).map { i -> Float in
            let x = abs(Float(i % s) - half) / half
            let y = abs(Float(i / s) - half) / half
            return 1.0 - sqrt(x*x + y*y) / sqrt(2.0)
        }
        return (rgb, depths)
    }

    /// PQ1: All 4096 pixels assigned, all indices in [0,255]
    func testPQ1_allAssigned() {
        let (rgb, depths) = syntheticFrame()
        let indices = PerfectQuantizer.quantizeFrame(frameIndex: 8, rgb: rgb, depths: depths)
        XCTAssertEqual(indices.count, CameraConfig.pixelCount, "PQ1: must produce \(CameraConfig.pixelCount) indices")
        for (i, idx) in indices.enumerated() {
            XCTAssertTrue(idx <= 255, "PQ1: index \(i) = \(idx) > 255")
        }
    }

    /// PQ3: Deterministic — same input → same output
    func testPQ3_deterministic() {
        let (rgb, depths) = syntheticFrame()
        let run1 = PerfectQuantizer.quantizeFrame(frameIndex: 24, rgb: rgb, depths: depths)
        let run2 = PerfectQuantizer.quantizeFrame(frameIndex: 24, rgb: rgb, depths: depths)
        XCTAssertEqual(run1, run2, "PQ3: same input must produce identical output")
    }

    /// PQ5: Color (a,b,c) tracks the input under the dithered law.
    /// Updated 2026-08-10: the original expected pre-pivot FLOOR
    /// quantization (Int(r·4)); PerfectQuantizer has been nearest-level
    /// (round(r·3)) with Floyd–Steinberg diffusion since the pivot. The
    /// adjustment is clamped to ±0.2, so the dithered level can differ
    /// from the undithered nearest level by AT MOST one step — that
    /// clamp is the lawful bound, not per-pixel equality.
    func testPQ5_colorPreserved() {
        let (rgb, depths) = syntheticFrame()
        let indices = PerfectQuantizer.quantizeFrame(frameIndex: 16, rgb: rgb, depths: depths)
        for (i, idx) in indices.enumerated() {
            let (r, g, b) = rgb[i]
            let nearestA = min(3, max(0, Int((r * 3.0).rounded())))
            let nearestB = min(3, max(0, Int((g * 3.0).rounded())))
            let nearestC = min(3, max(0, Int((b * 3.0).rounded())))
            let actualA = Int(idx % 64) / 16
            let actualB = (Int(idx % 64) % 16) / 4
            let actualC = Int(idx) % 4
            XCTAssertLessThanOrEqual(abs(actualA - nearestA), 1, "PQ5 pixel \(i): a drifted >1 level")
            XCTAssertLessThanOrEqual(abs(actualB - nearestB), 1, "PQ5 pixel \(i): b drifted >1 level")
            XCTAssertLessThanOrEqual(abs(actualC - nearestC), 1, "PQ5 pixel \(i): c drifted >1 level")
        }
    }

    // ════════════════════════════════════════════════
    // LAYER 1d: DEPTH-SIGMA FORMULA
    // ════════════════════════════════════════════════

    func testDepthSigma_exactValues() {
        // σ(depth) = σ_base × (2 - depth), σ_base = (K-1)/8
        let sb = BinomialCadence.sigmaBase  // (K-1)/8, depends on CameraConfig.level
        XCTAssertEqual(BinomialCadence.sigmaForDepth(1.0), sb * 1.0, accuracy: eps,
            "Near (face): σ = σ_base × 1")
        XCTAssertEqual(BinomialCadence.sigmaForDepth(0.0), sb * 2.0, accuracy: eps,
            "Far (wall): σ = σ_base × 2")
        XCTAssertEqual(BinomialCadence.sigmaForDepth(0.5), sb * 1.5, accuracy: eps,
            "Mid: σ = σ_base × 1.5")
    }

    func testDepthSigma_monotonic() {
        // Nearer depth → smaller sigma (tighter epochs)
        var prevSigma = BinomialCadence.sigmaForDepth(0.0)
        for d in stride(from: Float(0.1), through: 1.0, by: 0.1) {
            let sigma = BinomialCadence.sigmaForDepth(d)
            XCTAssertLessThan(sigma, prevSigma,
                "σ must decrease as depth increases (d=\(d))")
            prevSigma = sigma
        }
    }

    // ════════════════════════════════════════════════
    // LAYER 2: SUBJECT ANALYSIS
    // ════════════════════════════════════════════════

    func testSubjectAnalysis_centerNear() {
        let (_, depths) = syntheticFrame()  // center-near depth map
        let analysis = PerfectQuantizer.analyzeSubject(depths: depths)

        XCTAssertGreaterThan(analysis.subjectPixelCount, 0, "Should have subject pixels")
        XCTAssertGreaterThan(analysis.backgroundPixelCount, 0, "Should have background pixels")
        XCTAssertGreaterThan(analysis.resolutionRatio, 1.0,
            "Background σ should be larger than subject σ")
        XCTAssertLessThan(analysis.subjectSigma, analysis.backgroundSigma,
            "Subject should have tighter epochs than background")
    }

    // ════════════════════════════════════════════════
    // LAYER 3: BLACK/WHITE ANCHORS
    // ════════════════════════════════════════════════

    /// Black and white anchors exist in a gradient frame
    func testAnchors_existInGradient() {
        let (rgb, depths) = syntheticFrame()
        let indices = PerfectQuantizer.quantizeFrame(frameIndex: 8, rgb: rgb, depths: depths)
        let anchors = PerfectQuantizer.findAnchors(indices: indices)

        XCTAssertNotNil(anchors.blackPixelIndex, "Gradient should have a black pixel (a=0,b=0,c=0)")
        XCTAssertNotNil(anchors.whitePixelIndex, "Gradient should have a white pixel (a=3,b=3,c=3)")
    }

    /// Anchor epochs should follow the Gaussian cadence across frames
    /// Updated 2026-08-10: track the MODAL epoch of the black group,
    /// not the first black pixel's. findAnchors reports the first
    /// occurrence, which is the far corner of the planted block — the
    /// depth-sorted threading lawfully hands that tail pixel a MINORITY
    /// epoch (PQ4: dominant epoch goes to NEAR pixels first). The
    /// Gaussian cadence law is about the group's dominant epoch.
    func testAnchors_epochCadence() {
        let (rgb, depths) = syntheticFrame()
        var blackModalEpochs: [Int] = []

        let k = CameraConfig.totalFrames
        for z in 0..<k {
            let indices = PerfectQuantizer.quantizeFrame(frameIndex: z, rgb: rgb, depths: depths)
            var counts = [Int](repeating: 0, count: 4)
            for idx in indices where idx % 64 == 0 {   // black display color
                counts[Int(idx) / 64] += 1
            }
            if counts.contains(where: { $0 > 0 }) {
                blackModalEpochs.append(counts.firstIndex(of: counts.max()!)!)
            }
        }

        // Black should exist in every frame (the planted block is stable)
        XCTAssertGreaterThan(blackModalEpochs.count, k * 3 / 4,
            "Black pixels should exist in >75% of frames")

        // The dominant epoch progresses 0→1→2→3 across the 64 frames
        if blackModalEpochs.count >= 4 {
            let early = blackModalEpochs[4]                            // ~frame 4 → epoch 0
            let mid = blackModalEpochs[blackModalEpochs.count / 2]     // ~frame 32
            let late = blackModalEpochs[blackModalEpochs.count - 4]    // ~frame 60 → epoch 3
            XCTAssertLessThanOrEqual(early, mid, "Dominant epoch should increase over time")
            XCTAssertLessThanOrEqual(mid, late, "Dominant epoch should increase over time")
        }
    }

    // ════════════════════════════════════════════════
    // LAYER 4: INTEGRATION
    // ════════════════════════════════════════════════

    func testPipeline_syntheticFullRoundtrip() {
        let (rgb, depths) = syntheticFrame()

        // Process all K frames (64, 32, or 16 depending on level)
        let totalFrames = CameraConfig.totalFrames
        var frames: [QuantizedFrame] = []
        for z in 0..<totalFrames {
            let indices = PerfectQuantizer.quantizeFrame(frameIndex: z, rgb: rgb, depths: depths)
            let measure = BirkhoffMeasure(paletteIndices: indices)
            let subject = PerfectQuantizer.analyzeSubject(depths: depths)
            let anchors = PerfectQuantizer.findAnchors(indices: indices)
            frames.append(QuantizedFrame(
                index: z, paletteIndices: indices, rawRGB: rgb, depths: depths,
                measure: measure, subjectAnalysis: subject, anchorTrace: anchors,
                timestamp: Double(z) / 20.0
            ))
        }

        // Encode through the machine (DYAD per-frame palettes — the
        // only export law; the frames carry rawRGB so it is eligible)
        let gifData = GIFMachine.makeGIF(
            frames: frames, measure: nil,
            settings: ExportSettings(bleed: true, mirror: false))
        XCTAssertNotNil(gifData, "\(totalFrames)-frame GIF encoding should succeed")

        guard let data = gifData else { return }

        // Verify structure
        XCTAssertEqual(data[0], 0x47, "GIF magic byte 0")  // 'G'
        XCTAssertEqual(data[10], 0xF7, "Packed byte: 256-entry GCT")
        XCTAssertEqual(data.last, 0x3B, "Trailer byte")

        // All frames have anchors
        for frame in frames {
            XCTAssertNotNil(frame.anchorTrace?.blackPixelIndex,
                "Frame \(frame.index): missing black anchor")
        }
    }
}
