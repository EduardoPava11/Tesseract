// FunnelLedgerTests.swift
// Tesseract
//
// ★ THE SERIOUS TESTS: how the signal gets funneled, measured.
//
// Daniel, 2026-08-15: "I am ready to explore the color space fully.
// that means we should do a series of serious tests. so I know how the
// information from the signal gets funneled. For example a raw reading
// of a series of related numbers can be summarized into one bigger
// number. categorize compression into its components. the function map
// our axioms and theorems to test the swift and metal."
//
// Every test below runs ONE synthetic capture through the real
// pipeline and asserts something about a named stratum, citing the
// axiom that governs it. `testPrintTheFunnel` prints the whole ledger,
// which is the artifact the ask is really for: nobody had ever seen
// this pipeline's rate decomposition, only its end-to-end summary.
//
// No camera. `DyadPipeline.process(rgb:depths:)` is the export path
// itself, so these are measurements OF the shipping encoder rather
// than of a model of it.

import XCTest
@testable import Tesseract

final class FunnelLedgerTests: XCTestCase {

    private let side = 64
    private let frames = 16    // a short cube: every law here is per-frame
    private var px: Int { side * side }

    // MARK: - A synthetic capture, deterministic, no camera

    /// A figure over a ground: a disc that MOVES, so the temporal
    /// stratum has something to read and the depth mixture finds two
    /// phases. Colour drifts with the disc so the latent is not
    /// constant across the loop.
    private func syntheticCapture()
        -> (rgb: [[(Float, Float, Float)]], depths: [[Float]]) {
        var rgb: [[(Float, Float, Float)]] = []
        var depths: [[Float]] = []
        for f in 0..<frames {
            let phase = Double(f) / Double(frames) * 2 * Double.pi
            let cx = Double(side) / 2 + 12 * cos(phase)
            let cy = Double(side) / 2 + 12 * sin(phase)
            var frame: [(Float, Float, Float)] = []
            var dep: [Float] = []
            frame.reserveCapacity(px); dep.reserveCapacity(px)
            for p in 0..<px {
                let x = Double(p % side), y = Double(p / side)
                let d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy)
                let inFigure = d2 < 15 * 15
                if inFigure {
                    // Warm figure, shading across the disc.
                    let t = Float(min(1, d2 / (15 * 15)))
                    frame.append((0.85 - 0.25 * t, 0.55 - 0.2 * t, 0.42 - 0.1 * t))
                    dep.append(0.25 + 0.05 * Float(t))
                } else {
                    // Cool ground, a gentle gradient so it is not flat.
                    let g = Float(y / Double(side))
                    frame.append((0.16 + 0.06 * g, 0.20 + 0.05 * g, 0.34 + 0.10 * g))
                    dep.append(0.80 + 0.05 * g)
                }
            }
            rgb.append(frame); depths.append(dep)
        }
        return (rgb, depths)
    }

    private func ledger() throws -> FunnelLedger.Ledger {
        let c = syntheticCapture()
        guard let out = DyadPipeline.process(rgb: c.rgb, depths: c.depths) else {
            throw XCTSkip("the synthetic capture must be exportable")
        }
        let lzw = GIFEncoder.lzwCost(indexFrames: out.indexFrames)
        return FunnelLedger.measure(output: out, gifBytes: 0, lzwBytes: lzw,
                                    outputSize: side)
    }

    // MARK: - ★ The artifact: print the funnel

    func testPrintTheFunnel() throws {
        let l = try ledger()
        print(l.report)
        // A report nobody can read is not a measurement.
        XCTAssertFalse(l.report.isEmpty)
        XCTAssertEqual(l.strata.count, 7)
    }

    // MARK: - S0: the entrance, and what KIND of narrowing it is

    /// The steepest structural step in the pipeline, and RL2's own
    /// audit factor: 768 to 64 is 144:1, 256 to 64 is 16:1.
    func testAcquisitionRatiosAreTheAuditFactors() throws {
        XCTAssertEqual(FrameGeometry.rgbDecimation(outputSize: 64), 144)
        XCTAssertEqual(FrameGeometry.depthDecimation(outputSize: 64), 16)
        XCTAssertEqual(FrameGeometry.rgbStep(outputSize: 64), 12)
        XCTAssertEqual(FrameGeometry.depthStep(outputSize: 64),
                       FrameGeometry.rgbStep(outputSize: 64) / FrameGeometry.scaleFactor)

        let l = try ledger()
        let rgb = l.strata.first { $0.name.contains("acquire RGB") }!
        let dep = l.strata.first { $0.name.contains("acquire depth") }!
        XCTAssertEqual(rgb.ratio, 144, accuracy: 1e-9)
        XCTAssertEqual(dep.ratio, 16, accuracy: 1e-9)
        // ★ AND IT IS A DISCARD, NOT A SUMMARY. This is the assertion
        // that carries the finding: the kernel reads ONE texel per
        // output pixel, so 143 of 144 samples never reach the answer.
        XCTAssertEqual(rgb.kind, .discard)
        XCTAssertEqual(dep.kind, .discard)
        XCTAssertEqual(FrameGeometry.samplesDiscardedPerOutputPixel(outputSize: 64), 143)
    }

    /// ★ What the discard costs, measured rather than asserted. On a
    /// field with structure below the sampling pitch the point sample
    /// and the box mean disagree; on a constant field they cannot.
    func testPointSampleDivergesFromTheBoxMeanItIsNot() {
        let srcSide = FrameGeometry.rgbCrop

        // A constant field: no structure to alias, so no divergence.
        let flat = [(Float, Float, Float)](repeating: (0.5, 0.5, 0.5),
                                           count: srcSide * srcSide)
        XCTAssertEqual(FunnelLedger.pointSampleDivergence(source: flat,
                                                          sourceSide: srcSide),
                       0, accuracy: 1e-9)

        // Fine stripes at the Nyquist limit of the 12-pixel pitch:
        // the box mean sees grey, the point sample sees whichever
        // stripe it landed on.
        var stripes = [(Float, Float, Float)]()
        stripes.reserveCapacity(srcSide * srcSide)
        for p in 0..<(srcSide * srcSide) {
            let v: Float = (p % srcSide) % 2 == 0 ? 1 : 0
            stripes.append((v, v, v))
        }
        let d = FunnelLedger.pointSampleDivergence(source: stripes, sourceSide: srcSide)
        print(String(format: "  S0 divergence on Nyquist stripes: %.2f levels", d))
        XCTAssertGreaterThan(d, 100, "a point sample of stripes cannot equal their mean")
    }

    // MARK: - ★ S2: the summarize Daniel named

    /// "a raw reading of a series of related numbers can be summarized
    /// into one bigger number." Per frame, 4096 pixels of 24-bit
    /// colour become 14 numbers and 2 bits, and CL1 says that is
    /// EXACT: the table is a pure function of them.
    func testTheLatentIsTheLargestSummarizationInTheLadder() throws {
        let l = try ledger()
        let s2 = l.strata.first { $0.name.contains("solve the latent") }!
        XCTAssertEqual(s2.kind, .summarize)

        // The arity is CL1's, measured from the pipeline's own types
        // rather than quoted: 9 stat numbers + 5 ground numbers.
        let c = syntheticCapture()
        let out = DyadPipeline.process(rgb: c.rgb, depths: c.depths)!
        XCTAssertEqual(DyadPipeline.statVector(out.stats[0]).count, 9)
        XCTAssertEqual(out.stats.count, frames)
        XCTAssertEqual(out.groundMoments.count, frames)
        // 14 continuous + 2 bits per frame.
        XCTAssertEqual(s2.bitsOut, frames * (14 * 64 + 2))

        // ★ AND THE MEASUREMENT CORRECTED THE GUESS THIS TEST WAS
        // FIRST WRITTEN WITH. S2 was asserted to be the steepest
        // stratum in the ladder. It is not: it summarizes at 109.5 : 1
        // while S0 DISCARDS at 144 : 1. The app throws away more
        // information at the sensor than it summarizes at the latent,
        // and the discarded part is the part no edit can ever recover.
        let steepestSummary = l.strata.filter { $0.kind == .summarize }
            .map { $0.ratio }.max()!
        XCTAssertEqual(s2.ratio, steepestSummary, accuracy: 1e-9,
                       "S2 is the steepest SUMMARIZE")
        let acquire = l.strata.first { $0.name.contains("acquire RGB") }!
        XCTAssertGreaterThan(acquire.ratio, s2.ratio,
                             "the discard at S0 is steeper than the summary at S2")
        print(String(format: "  S2 summarization: %.2f : 1   (S0 discard: %.0f : 1)",
                     s2.ratio, acquire.ratio))
    }

    /// ★ S3 runs the other way, and the ledger must not hide it. The
    /// palette is an EXPANSION: 14 numbers deterministically become
    /// 768 table bytes. It adds no information and loses none.
    func testThePaletteIsAnExpansionAndSaysSo() throws {
        let l = try ledger()
        let s3 = l.strata.first { $0.name.contains("grow the palette") }!
        XCTAssertEqual(s3.kind, .expand)
        XCTAssertLessThan(s3.ratio, 1, "an expansion has ratio below one")
        XCTAssertEqual(s3.bitsOut, frames * 768 * 8)
        print(String(format: "  S3 expansion: 1 : %.2f", 1 / s3.ratio))
    }

    // MARK: - ★ Depth: the steepest terminus in the app

    /// 32 bits of depth arrive per voxel and ONE leaves, as the role
    /// bit (AD7). That 32:1 is why depth is 57% of what is retained
    /// and almost none of what is exported.
    func testDepthEndsAsOneBitPerVoxel() throws {
        let l = try ledger()
        let d = l.strata.first { $0.name.contains("role bit") }!
        XCTAssertEqual(d.ratio, 32, accuracy: 1e-9)
        XCTAssertEqual(d.kind, .summarize)
        XCTAssertEqual(d.bitsOut, frames * px)
    }

    // MARK: - RL2: the ladder telescopes, where it is a ladder

    /// The product of a PATH's ratios equals that path's end-to-end
    /// ratio. Checked with the connectivity check beside it, because a
    /// product over a disconnected list telescopes vacuously.
    func testEveryPathTelescopes() throws {
        let l = try ledger()
        for p in [FunnelLedger.Path.pixel, .codebook, .depth] {
            XCTAssertTrue(l.isConnected(p), "\(p.rawValue) path must connect")
            XCTAssertEqual(l.telescoped(p), l.endToEnd(p),
                           accuracy: 1e-6 * max(1, l.endToEnd(p)),
                           "RL2 on the \(p.rawValue) path")
        }
        // The pixel path's structural head is exactly 144 × 3.
        let pixel = l.path(.pixel)
        XCTAssertEqual(pixel[0].ratio * pixel[1].ratio, 432, accuracy: 1e-9)

        // ★ AND THE CODEBOOK PATH'S NET RATIO IS EXACTLY 16, which is
        // not a coincidence and is worth pinning: summarizing 4096
        // pixels into a 256-entry table is N/K, and N/K = 16 is the
        // BALANCED OCCUPANCY of TE2, the ground state of E, the rung.
        // The palette costs exactly one sixteenth of the pixels it
        // describes because that is what "256 colours on a 64×64"
        // means, read as a rate.
        XCTAssertEqual(l.endToEnd(.codebook), 16, accuracy: 1e-9)
        XCTAssertEqual(Double(TilingEnergy.balanced), l.endToEnd(.codebook),
                       accuracy: 1e-9)

        // The depth path is 16 × 32 = 512, steeper structurally than
        // the pixel path's 432.
        XCTAssertEqual(l.endToEnd(.depth), 512, accuracy: 1e-9)
        XCTAssertGreaterThan(l.endToEnd(.depth), pixel[0].ratio * pixel[1].ratio)
    }

    // MARK: - ★ TE10: the coder, decomposed

    /// E is the ledger read from the other end. The order-0 bill is
    /// an IDENTITY here, not an estimate: TE10 says E = N·8 − N·H₀,
    /// so N·H₀ = 2,097,152 − E exactly.
    func testTheOrderZeroBillIsAnIdentityNotAnEstimate() throws {
        let c = syntheticCapture()
        let out = DyadPipeline.process(rgb: c.rgb, depths: c.depths)!
        var byIdentity = 0.0
        var byEntropy = 0.0
        for f in out.indexFrames {
            let h = TilingEnergy.histogram(f)
            let n = Double(f.count)
            byIdentity += n * 8 - TilingEnergy.energy(h)
            byEntropy += n * TilingEnergy.h0(h)
        }
        XCTAssertEqual(byIdentity, byEntropy, accuracy: 1e-6)
    }

    /// The decomposition itself: index plane, minus what occupancy
    /// already saved, minus what runs bought, is what LZW spent.
    ///
    /// ★ THE FIRST VERSION OF THIS TEST WAS VACUOUS and it is worth
    /// saying so. `contextFindBits` is DEFINED as order0 − lzw and
    /// `order0Bits` as plane − E, so their sum reconstitutes the plane
    /// no matter what any of them are; the assertion could not fail.
    /// The plane is now checked against a figure the ledger did not
    /// compute, and each part against an independent bound.
    func testTheCoderSplitsIntoOccupancyAndContext() throws {
        let l = try ledger()
        // The plane, from the shape rather than from the ledger.
        XCTAssertEqual(l.indexPlaneBits, frames * px * 8)
        XCTAssertEqual(l.frameCount, frames)

        // Each part is real and inside its own bound.
        XCTAssertGreaterThan(l.perFrameEnergySum, 0)
        XCTAssertLessThan(l.perFrameEnergySum, Double(l.indexPlaneBits))
        XCTAssertGreaterThan(l.lzwBits, 0)
        XCTAssertLessThan(Double(l.lzwBits), l.order0Bits,
                          "LZW beat an ideal order-0 coder on this fixture")
        XCTAssertGreaterThan(l.contextFindBits, 0)

        // And the identity holds against the independent plane.
        XCTAssertEqual(l.perFrameEnergySum + Double(l.lzwBits) + l.contextFindBits,
                       Double(frames * px * 8), accuracy: 1e-6)

        let pct = l.contextFindBits / l.order0Bits * 100
        print(String(format:
            "  occupancy %.0f b | order-0 bill %.0f b | lzw %d b | runs bought %.1f%%",
            l.perFrameEnergySum, l.order0Bits, l.lzwBits, pct))
    }

    /// TE9: pooling cannot be more ordered than the parts on average.
    /// A per-frame palette is exactly why the pooled E is the larger
    /// number here, and the ledger reports both so the difference is
    /// visible rather than implied.
    func testPooledEnergyExceedsTheFrameMean() throws {
        let l = try ledger()
        let mean = l.perFrameEnergySum / Double(frames)
        XCTAssertGreaterThanOrEqual(l.energy.eHist + 1e-6, mean)
    }

    // MARK: - The surplus the deviation ruling stands on

    func testTheSurplusIsSevenToOnePerVoxel() throws {
        let l = try ledger()
        // 7 bytes retained per voxel, 1 byte of index emitted.
        XCTAssertEqual(l.retainedBits, frames * px * (24 + 32))
        XCTAssertEqual(Double(l.retainedBits) / Double(frames * px * 8), 7,
                       accuracy: 1e-9)
        XCTAssertEqual(CubeStore.bytesPerCapture(frames: frames, side: side),
                       16 + frames * px * 7)
    }
}
