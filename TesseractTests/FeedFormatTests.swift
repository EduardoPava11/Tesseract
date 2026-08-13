// FeedFormatTests.swift
// TesseractTests
//
// Swift-side gates for the FeedFormat port — each test mirrors an
// axiom of spec/output/FeedCompression.hs (the authority, FC1–FC10).
// Pure logic: no camera, no Metal, no simulator dependency beyond
// XCTest itself (house pattern: TriScaleLadderTests).
//
// SEVERAL AXIOMS ARE ENFORCED BY THE TYPE SYSTEM AND HAVE NO TEST —
// by design, not omission. They are listed here so no reader mistakes
// the absence for a gap; each is also documented at its declaration:
//
//   FC1  (part) `Rung` is a CLOSED enum over {64,32,16}. Rung 128 —
//        the one with no integer centisecond delay — is
//        UNREPRESENTABLE, so TL4's cap is structural. `delayCs` is a
//        total computed property off the single RungTelemetry.loopCs;
//        there is no second table to drift.
//   FC2  (part) `Rung.frames == rawValue == side` by construction, and
//        `pooled` returns `Rung?` so "one κ step below coarse" is nil
//        rather than an invalid rung.
//   FC3  (part) `FeedChannel` is a 4-case enum and `FeedCube` has
//        exactly four stored planes; a three- or five-channel payload
//        cannot be built. `colourChannelCount` derives from allCases.
//   FC8  (part) `tileSide`/`tileCount` are computed from Rung.fine and
//        Rung.coarse, so the 4³/4096 partition cannot be respecified
//        independently of the ladder.
//   FC9  ★ `energy`/`tileEnergy` are generic with a REQUIRED `weight:`
//        parameter — no default, no overload without it, no stored
//        weight anywhere. Baking a weight in is a compile error at the
//        call site, not a review catch.
//   FC10 (part) `FeedSource.sample` returns `FeedSample`:
//        non-optional, non-throwing. Totality is a property of the
//        signature, and both the synthetic and the real feed conform,
//        so "same type" is checked by the compiler
//        (testFC10SyntheticAndRealSameType only has to COMPILE).
//
// Where the Haskell computes in exact `Rational` and Swift computes in
// Double, the tolerance is DERIVED from the operation (Wilkinson's
// n·ε bound for an n-term sum), never guessed — and where the spec's
// values are dyadic (k/256) the assertion is exact `==`.

import XCTest
@testable import Tesseract

final class FeedFormatTests: XCTestCase {

    // MARK: - Fixtures

    /// The spec's index cube generalized to any side:
    /// `lcg (i*7+3) mod 6` (FeedCompression § 4). The LCG itself is
    /// NOT redefined here — SyntheticFeed.lcg IS the spec's
    /// (1103515245·s + 12345) mod 2³¹, the same one
    /// TriScaleLadderTests.indexStream mirrors.
    private func specIndexCube(side: Int) -> [Int] {
        (0..<(side * side * side)).map { SyntheticFeed.lcg($0 * 7 + 3) % 6 }
    }

    /// A full 64³ burst whose colour and depth are supplied per cell.
    private func makeFrames(
        colour: (Int, Int, Int) -> (Float, Float, Float),
        depth: (Int, Int, Int) -> Float
    ) -> [CapturedFrame] {
        let side = Rung.fine.side
        var frames = [CapturedFrame]()
        frames.reserveCapacity(Rung.fine.frames)
        for t in 0..<Rung.fine.frames {
            var rgb = [(Float, Float, Float)]()
            var depths = [Float]()
            rgb.reserveCapacity(side * side)
            depths.reserveCapacity(side * side)
            for y in 0..<side {
                for x in 0..<side {
                    rgb.append(colour(t, y, x))
                    depths.append(depth(t, y, x))
                }
            }
            frames.append(CapturedFrame(index: t, rgb: rgb, depths: depths,
                                        timestamp: Double(t) / Rung.fine.rateHz))
        }
        return frames
    }

    /// A synthesized cube of the given rung, planes filled by index.
    private func makeCube(_ rung: Rung, plane: (Int) -> Double) -> FeedCube {
        let v = (0..<rung.cells).map(plane)
        return FeedCube(rung: rung, l: v, a: v, b: v, d: v)
    }

    /// The two-phase depth field of the FC6 fixture: a centered
    /// subject disc at 0.78 on a background at 0.22, jittered ±0.1 by
    /// the spec's own LCG. Deterministic; DepthSignal space.
    private func twoPhaseDepth(_ t: Int, _ y: Int, _ x: Int) -> Float {
        let side = Rung.fine.side
        let i = t * side * side + y * side + x
        let c = Double(side - 1) / 2
        let dx = Double(x) - c, dy = Double(y) - c
        let base = (dx * dx + dy * dy) < 18 * 18 ? 0.78 : 0.22
        let jitter = (Double(SyntheticFeed.lcg(i &* 29 &+ 7) % 64) / 64 - 0.5) * 0.2
        return Float(min(1, max(0, base + jitter)))
    }

    private func mean(_ xs: [Double]) -> Double {
        xs.reduce(0, +) / Double(xs.count)
    }

    /// The FC6 scalar fixture, transcribed from the spec's own `where`
    /// clause (FeedCompression § FC6): a 64-value field
    /// `lcg (i*13+1) mod 1000 % 1000`, and its κ pooling
    /// `[ sum blk / 8 | blk <- chunk 8 field ]`. The spec computes in
    /// exact `Rational`; here the element type is written out so the
    /// arithmetic is unambiguous — the numbers are the spec's, not new
    /// ones, and the two FC6 tests share this one transcription rather
    /// than restating it.
    private func fc6Field() -> [Double] {
        (0..<64).map { (i: Int) -> Double in
            Double(SyntheticFeed.lcg(i * 13 + 1) % 1000) / 1000.0
        }
    }

    private func fc6Pooled(_ field: [Double]) -> [Double] {
        stride(from: 0, to: field.count, by: 8).map { (start: Int) -> Double in
            let block: ArraySlice<Double> = field[start ..< (start + 8)]
            let total: Double = block.reduce(0.0, +)
            return total / 8.0
        }
    }

    // MARK: - FC1 — the rate law

    // FC1 ★: side × delay = 320 cs at every rung; the loop duration is
    // the invariant and the rung sets the rate, 20/10/5 Hz.
    func testFC1RateLaw() {
        for rung in Rung.allCases {
            XCTAssertEqual(rung.side * rung.delayCs, FeedFormat.loopCs)
            XCTAssertEqual(FeedFormat.loopCs % rung.side, 0,
                           "integer centisecond delays only")
        }
        XCTAssertEqual(FeedFormat.loopCs, 320)
        XCTAssertEqual(FeedFormat.rungs, Rung.allCases,
                       "pyramid order IS declaration order — no second list")
        XCTAssertEqual(FeedFormat.rungs.map(\.delayCs), [5, 10, 20])
        XCTAssertEqual(FeedFormat.rungs.map(\.rateHz), [20, 10, 5])
    }

    // FC1, THE ANTI-FORK GATE: FeedFormat derives its delays from the
    // ONE shipping loop constant, so it must agree with the shipping
    // table cell for cell. Fails the moment the two disagree.
    func testFC1NoForkedDelayTable() {
        for rung in Rung.allCases {
            XCTAssertEqual(rung.delayCs, RungTelemetry.delayCs[rung.side],
                           "FeedFormat and TriScaleLadder must not fork the delay table")
        }
        XCTAssertEqual(RungTelemetry.delayCs.count, Rung.allCases.count)
        // TL4's cap, restated from the other side: 128 has no integer
        // delay, which is why `Rung` cannot express it.
        XCTAssertNotEqual(FeedFormat.loopCs % (2 * Rung.fine.side), 0)
    }

    // FC1: 5 cs / 20 Hz / stride-4 are stated in four places already
    // (conflict C3). Pin all four to the rate law so FeedFormat cannot
    // become the fifth statement.
    func testFC1MatchesShippingCadences() {
        XCTAssertEqual(Int(GIFEncoder.frameDelayCentiseconds), Rung.fine.delayCs)
        XCTAssertEqual(CameraConfig.targetFPS, Int(Rung.fine.rateHz))
        // ⚠ The live slow state is DEFINED from the ladder
        // (`refreshStride = fine.side / coarse.side`,
        // `ringFrames = coarse.frames`), so comparing it back to a
        // ratio of those same terms is X == X — it passes at any
        // `loopCs` and gates nothing. Assert the PHYSICAL span
        // instead: the quantity a wrong loop actually breaks is TIME.
        XCTAssertEqual(
            DyadPipeline.Live.ringFrames * Rung.coarse.delayCs,
            RungTelemetry.loopCs,
            "the live read must hold exactly one loop of feed")
        XCTAssertEqual(
            DyadPipeline.Live.refreshStride * Rung.fine.delayCs,
            Rung.coarse.delayCs,
            "a stride of fine frames must be one coarse frame of time")
        XCTAssertEqual(Rung.fine.frames, CameraConfig.totalFrames)
        XCTAssertEqual(Rung.fine.side, CameraConfig.outputSize)
    }

    // MARK: - FC2 — κ halves time exactly as it halves space

    func testFC2FramesAreSide() {
        for rung in Rung.allCases { XCTAssertEqual(rung.frames, rung.side) }
        for (a, b) in zip(FeedFormat.rungs, FeedFormat.rungs.dropFirst()) {
            XCTAssertEqual(a.frames, 2 * b.frames)
            XCTAssertEqual(a.cells, 8 * b.cells)
        }
        XCTAssertEqual(FeedFormat.rungs.map(\.cells), [262144, 32768, 4096])
        XCTAssertEqual(FeedFormat.kappaCells, 8, "the 2×2×2 spacetime atom (OV10)")
        XCTAssertEqual(Rung.fine.pooled, .mid)
        XCTAssertEqual(Rung.mid.pooled, .coarse)
        XCTAssertNil(Rung.coarse.pooled, "the ladder stops; nil, not an invalid rung")
    }

    func testFC2PoolHalvesTime() throws {
        let fine = makeCube(.fine) { Double($0 % 1000) / 1000 }
        let mid = try XCTUnwrap(FeedFormat.pool(fine))
        XCTAssertEqual(mid.rung, .mid)
        XCTAssertEqual(mid.rung.frames, fine.rung.frames / 2)
        for plane in [mid.l, mid.a, mid.b, mid.d] {
            XCTAssertEqual(plane.count, 32 * 32 * 32)
        }
        let coarse = try XCTUnwrap(FeedFormat.pool(mid))
        XCTAssertEqual(coarse.rung, .coarse)
        for plane in [coarse.l, coarse.a, coarse.b, coarse.d] {
            XCTAssertEqual(plane.count, 16 * 16 * 16)
        }
        XCTAssertNil(FeedFormat.pool(coarse))
    }

    // MARK: - FC3 — four channels, OKLab, depth carried

    func testFC3FourChannels() {
        XCTAssertEqual(FeedChannel.allCases, [.l, .a, .b, .d])
        XCTAssertEqual(FeedChannel.allCases.count, 4)
        XCTAssertEqual(FeedFormat.colourChannelCount, 3)
        for rung in Rung.allCases {
            XCTAssertEqual(FeedFormat.values(at: rung), 4 * rung.cells)
        }
        XCTAssertEqual(FeedFormat.bytesPerCell, 5, "8-bit OKLab + fp16 depth")
        XCTAssertEqual(MemoryLayout<Float16>.size, 2)
    }

    // FC3: κ is a MEAN, so the payload must be OKLab — averaging the
    // gamma code averages the code, not the colour. Fixture chosen so
    // gamma bites hardest: half black, half white in every κ block.
    func testFC3PayloadIsOKLabNotSRGB() throws {
        let frames = makeFrames(
            colour: { t, y, x -> (Float, Float, Float) in
                (t + y + x) % 2 == 0 ? (0, 0, 0) : (1, 1, 1)
            },
            depth: { _, _, _ in DepthSignal.fill })
        let fine = try XCTUnwrap(FeedFormat.cube(from: frames))
        let mid = try XCTUnwrap(FeedFormat.pool(fine))

        let black = DyadPalette.oklab(fromSRGBUnit: (0, 0, 0))
        let white = DyadPalette.oklab(fromSRGBUnit: (1, 1, 1))
        let labMean = OKLabColor(l: (black.l + white.l) / 2,
                                 a: (black.a + white.a) / 2,
                                 b: (black.b + white.b) / 2)
        // The κ block is 8 cells: Wilkinson's n·ε bound on an 8-term
        // sum of magnitudes ≤ 1.
        let tol = 8 * Double.ulpOfOne
        let pooled = mid.lab(at: 0)
        XCTAssertEqual(pooled.l, labMean.l, accuracy: tol)
        XCTAssertEqual(pooled.a, labMean.a, accuracy: tol)
        XCTAssertEqual(pooled.b, labMean.b, accuracy: tol)

        // ...and it is NOT the OKLab of the sRGB mean. Stated as a
        // strict relative claim so no threshold is invented.
        let labOfSRGBMean = DyadPalette.oklab(fromSRGBUnit: (0.5, 0.5, 0.5))
        XCTAssertLessThan(DyadPalette.dLab2(pooled, labMean),
                          DyadPalette.dLab2(pooled, labOfSRGBMean))
        XCTAssertNotEqual(labMean.l, labOfSRGBMean.l,
                          "the fixture must be one where gamma bites")
    }

    // FC3: depth is CARRIED, never derived from colour.
    func testFC3DepthIsCarriedNotDerived() throws {
        let colour = makeCube(.fine) { Double($0 % 997) / 997 }
        var lowDepth = colour, highDepth = colour
        lowDepth.d = colour.d.map { $0 / 4 }
        highDepth.d = colour.d.map { 1 - $0 / 4 }

        let pooledLow = try XCTUnwrap(FeedFormat.pool(lowDepth))
        let pooledHigh = try XCTUnwrap(FeedFormat.pool(highDepth))
        XCTAssertEqual(pooledLow.l, pooledHigh.l)
        XCTAssertEqual(pooledLow.a, pooledHigh.a)
        XCTAssertEqual(pooledLow.b, pooledHigh.b)
        XCTAssertNotEqual(pooledLow.d, pooledHigh.d,
                          "identical colour must not collapse different depth")

        // And no transform of the colour planes moves d.
        var recoloured = lowDepth
        recoloured.l = colour.l.map { 1 - $0 }
        recoloured.a = colour.a.map { -$0 }
        recoloured.b = [Double](repeating: 0, count: colour.b.count)
        let pooledRecoloured = try XCTUnwrap(FeedFormat.pool(recoloured))
        XCTAssertEqual(pooledRecoloured.d, pooledLow.d)
    }

    // T-P1: the one shipping-code addition. The unit-sRGB entry point
    // must be BIT-identical to the 8-bit one on the 8-bit grid — the
    // gate that lets FeedFormat convert before rounding (TL2) without
    // forking the Ottosson pipeline.
    func testFC3OKLabUnitParity() {
        for v in 0...255 {
            let grey8 = DyadPalette.oklab(fromSRGB8: (UInt8(v), UInt8(v), UInt8(v)))
            let greyU = DyadPalette.oklab(
                fromSRGBUnit: (Double(v) / 255, Double(v) / 255, Double(v) / 255))
            XCTAssertEqual(grey8, greyU, "channel value \(v)")
        }
        // A stratified 4096-triple sample over the cube (16³ corners
        // of the 8-bit grid) — every one bit-identical.
        for r in stride(from: 0, through: 255, by: 17) {
            for g in stride(from: 0, through: 255, by: 17) {
                for b in stride(from: 0, through: 255, by: 17) {
                    let rgb8 = (UInt8(r), UInt8(g), UInt8(b))
                    XCTAssertEqual(
                        DyadPalette.oklab(fromSRGB8: rgb8),
                        DyadPalette.oklab(fromSRGBUnit: (Double(r) / 255,
                                                         Double(g) / 255,
                                                         Double(b) / 255)),
                        "triple \(rgb8)")
                }
            }
        }
    }

    // MARK: - FC4 / FC5 — the byte budget

    // FC4 ★: the pyramid tax is EXACTLY 73/64. Asserted on the integer
    // pair — a Double would forfeit the spec's Rational exactness.
    func testFC4PyramidTax() {
        let tax = FeedFormat.pyramidTax
        XCTAssertEqual(tax.numerator * 64, tax.denominator * 73)
        XCTAssertEqual(tax.numerator, 299008)
        XCTAssertEqual(tax.denominator, Rung.fine.cells)
        XCTAssertEqual(FeedFormat.rungs.reduce(0) { $0 + $1.cells }, 299008)
        XCTAssertEqual(Rung.mid.cells * 8, Rung.fine.cells)
        XCTAssertEqual(Rung.coarse.cells * 8, Rung.mid.cells)
        XCTAssertLessThan(tax.numerator * 100, tax.denominator * 115)
    }

    // FC5 ★: the whole three-rung pyramid at honest typing is smaller
    // than today's single fp32 rung, by more than 2×.
    func testFC5CheaperThanToday() {
        XCTAssertEqual(FeedFormat.pyramidBytes, 1_495_040)
        XCTAssertEqual(FeedFormat.todayBytes, 4_194_304)
        XCTAssertLessThan(FeedFormat.pyramidBytes, FeedFormat.todayBytes)
        XCTAssertGreaterThan(FeedFormat.todayBytes, 2 * FeedFormat.pyramidBytes)
        XCTAssertLessThan(FeedFormat.bytes(at: .fine), FeedFormat.todayBytes)
        XCTAssertEqual(FeedFormat.pyramidBytes,
                       FeedFormat.rungs.reduce(0) { $0 + FeedFormat.bytes(at: $1) })
    }

    // FC5's PREMISE, made a live assertion: today's retention really is
    // an fp32 triple plus an fp32 depth (CapturedFrame.swift:18, :21),
    // read from MemoryLayout so a type change breaks the test rather
    // than rotting a comment.
    func testFC5TodayTypingWitness() {
        XCTAssertEqual(MemoryLayout<(Float, Float, Float)>.size, 12)
        XCTAssertEqual(MemoryLayout<Float>.size, 4)
        XCTAssertEqual(FeedFormat.todayBytesPerCell, 16)
        XCTAssertEqual(FeedFormat.todayBytes,
                       Rung.fine.cells * FeedFormat.todayBytesPerCell)
    }

    // MARK: - FC6 — depth carries the boundary; pooling biases it

    // FC6: κ preserves the mean EXACTLY. Mirrors the spec's own
    // fixture (64 values lcg(i*13+1) mod 1000 / 1000, pooled by 8).
    // The spec computes in Rational; Swift computes in Double, so the
    // tolerance is Wilkinson's bound for an n-term summation,
    // n·ε·max|xᵢ| with n = 64 — derived from the operation, not chosen.
    func testFC6MeanPreserved() {
        let field = fc6Field()
        let pooled = fc6Pooled(field)
        let bound = Double(field.count) * .ulpOfOne * (field.map { abs($0) }.max() ?? 0)
        XCTAssertEqual(mean(pooled), mean(field), accuracy: bound)
    }

    // FC6: and it SHRINKS the variance — strict, tolerance-free. This
    // pins the DIRECTION of the bias, which is the whole point of the
    // axiom: a coarse-rung mixture fit is over-confident until lifted.
    func testFC6VarianceShrinks() {
        let field = fc6Field()
        let pooled = fc6Pooled(field)
        XCTAssertLessThan(FeedFormat.variance(pooled), FeedFormat.variance(field))
    }

    // FC6: E[σ²_within] is an IDENTITY, not a tunable — the law of
    // total variance, and it telescopes down the ladder. The lift
    // argument liftedDepthFit uses (Var(fine) − Var(coarse)) must
    // equal the sum of the per-step within-block variances.
    // Tolerance: Wilkinson's n·ε bound over the fine rung's cells.
    func testFC6WithinVarianceTelescopes() throws {
        let frames = makeFrames(colour: { _, _, _ -> (Float, Float, Float) in (0.5, 0.5, 0.5) },
                                depth: self.twoPhaseDepth)
        let pyramid = try XCTUnwrap(FeedFormat.pyramid(from: frames))
        let (fine, mid, coarse) = (pyramid[0], pyramid[1], pyramid[2])
        let byDifference = FeedFormat.variance(fine.d) - FeedFormat.variance(coarse.d)
        let byTelescope = FeedFormat.depthWithinVariance(fine)
                        + FeedFormat.depthWithinVariance(mid)
        let bound = Double(fine.d.count) * .ulpOfOne * FeedFormat.variance(fine.d)
        XCTAssertEqual(byDifference, byTelescope, accuracy: bound)
        XCTAssertGreaterThan(byDifference, 0)
    }

    // FC6 ★: the τ-lift is in the right DIRECTION. The naive coarse
    // fit is over-confident (σ too small, crossover pulled toward the
    // midpoint); lifting restores σ and brings the crossover back to
    // the fine rung's. Both claims are relative — no threshold.
    func testFC6TauLiftIsTheRightDirection() throws {
        let frames = makeFrames(colour: { _, _, _ -> (Float, Float, Float) in (0.5, 0.5, 0.5) },
                                depth: self.twoPhaseDepth)
        let pyramid = try XCTUnwrap(FeedFormat.pyramid(from: frames))
        let (fine, coarse) = (pyramid[0], pyramid[2])

        let fineFit = DepthMixture.fit(fine.d)
        let naivePooled = DepthMixture.fit(coarse.d)
        let lifted = FeedFormat.liftedDepthFit(fine: fine, coarse: coarse)

        XCTAssertLessThan(FeedFormat.variance(coarse.d), FeedFormat.variance(fine.d),
                          "pooling must shrink the depth variance (FC6)")
        XCTAssertGreaterThan(lifted.sigma, naivePooled.sigma,
                             "the lift un-shrinks the tied σ")
        XCTAssertLessThan(abs(lifted.crossover - fineFit.crossover),
                          abs(naivePooled.crossover - fineFit.crossover),
                          "the lifted crossover must agree with the fine rung's")
        // The lift changes only the second moment (DM11).
        XCTAssertEqual(lifted.muF, naivePooled.muF)
        XCTAssertEqual(lifted.muB, naivePooled.muB)
        XCTAssertEqual(lifted.piB, naivePooled.piB)
    }

    // MARK: - FC7 — the attractor ladder (arithmetic/telemetry only)

    func testFC7AttractorLadder() {
        let a = FeedFormat.attractors
        XCTAssertEqual(a, [1, 1, 2, 4, 8, 16, 32, 64, 64, 32, 16, 8, 4, 2, 1, 1])
        XCTAssertEqual(a.reduce(0, +), FeedFormat.paletteSize)
        XCTAssertEqual(a.count, 16)
        XCTAssertEqual(a, Array(a.reversed()))
        XCTAssertEqual(a.max(), 64)
        XCTAssertEqual(a.sorted(by: >).prefix(2).reduce(0, +), FeedFormat.paletteSize / 2,
                       "half the palette sits in two of the sixteen basins")
        let half = FeedFormat.shellHalf
        for k in 2..<half.count { XCTAssertEqual(half[k], 2 * half[k - 1]) }
        XCTAssertEqual(half.reduce(0, +), FeedFormat.paletteSize / 2)
    }

    // FC7, THE ANTI-FORK GATE for the palette side: the spec's
    // shellHalf IS the shipping ladder, not a copy of it.
    func testFC7ReusesShippingLadder() {
        XCTAssertEqual(FeedFormat.shellHalf, DyadPalette.ladder)
        XCTAssertEqual(FeedFormat.paletteSize, CameraConfig.paletteSize)
        XCTAssertEqual(FeedFormat.shellHalf.count, DyadPalette.levelCount)
        XCTAssertEqual(FeedFormat.shellHalf.reduce(0, +), DyadPalette.primaryCount)
    }

    // MARK: - FC8 — the 64³ tiles exactly by 4³

    func testFC8TilingIsAPartition() {
        // The spec's own scale model (8 by 2), and the two-rung span
        // at the resolution of depth (16 by 4).
        for (side, k) in [(8, 2), (16, 4)] {
            let tiles = FeedFormat.tiles(side: side, tileSide: k)
            XCTAssertEqual(tiles.count, (side / k) * (side / k) * (side / k))
            let covered = tiles.flatMap { FeedFormat.cells(ofTile: $0, tileSide: k) }
            XCTAssertEqual(covered.sorted(), FeedFormat.coords(side: side).sorted())
            XCTAssertEqual(Set(covered).count, side * side * side,
                           "no cell twice, no cell missing")
            XCTAssertTrue(covered.allSatisfy { cell in
                FeedFormat.cells(ofTile: FeedFormat.tile(of: cell, tileSide: k),
                                 tileSide: k).contains(cell)
            }, "every cell lies in the tile `tile(of:)` names")
        }
        // The app-scale arithmetic FC8 actually states.
        XCTAssertEqual(FeedFormat.tileSide, 4)
        XCTAssertEqual(FeedFormat.tileCount, 4096)
        XCTAssertEqual(Rung.fine.side % FeedFormat.tileSide, 0)
        XCTAssertEqual(Rung.fine.cells,
                       FeedFormat.tileCount * FeedFormat.tileSide
                       * FeedFormat.tileSide * FeedFormat.tileSide)
    }

    // FC8: the tile is not a chosen block size — it is the two-rung
    // span, i.e. exactly one rung-16 judgment (TL9 vocabulary).
    func testFC8TileSideIsTheJudgment() {
        XCTAssertEqual(FeedFormat.tileSide * FeedFormat.tileSide * FeedFormat.tileSide,
                       RungTelemetry.samplesPerJudgment)
        XCTAssertEqual(FeedFormat.tileCount, RungTelemetry.judgmentsPerLoop)
        XCTAssertEqual(FeedFormat.tileCount, Rung.coarse.cells)
        XCTAssertEqual(Rung.fine.side, RungTelemetry.baseRungSide)
        XCTAssertEqual(Rung.coarse.side, RungTelemetry.depthRungSide)
    }

    // FC8, conflict C8: DyadPipeline.pairDither already computes this
    // partition inline (4×4 spatial blocks × 4-frame temporal groups).
    // This documents the duplication so it cannot silently diverge —
    // the refactor itself touches the pixel path and is NOT taken here.
    func testFC8MatchesShippingBlockPool() {
        let side = Rung.fine.side
        let rung = FeedFormat.tileSide          // DyadPipeline's inline `rung = 4`
        let bSide = side / rung                 // its `bSide`
        XCTAssertEqual(bSide, Rung.coarse.side)
        let sample = [0, 1, 3, 4, 7, 15, 16, 31, 32, 60, 62, 63]
        for t in sample {
            for y in sample {
                for x in sample {
                    let cell = FeedCell(t: t, y: y, x: x)
                    let tile = FeedFormat.tile(of: cell, tileSide: rung)
                    XCTAssertEqual(tile.t, t / rung, "temporal group (spacetime[f / 4])")
                    XCTAssertEqual(tile.y, y / rung, "by = y / rung")
                    XCTAssertEqual(tile.x, x / rung, "bx = x / rung")
                    // The pipeline's flat block index, from a pixel p.
                    let p = y * side + x
                    XCTAssertEqual(((p / side) / rung) * bSide + (p % side) / rung,
                                   tile.y * bSide + tile.x)
                }
            }
        }
    }

    // MARK: - FC9 — tightness, for ANY bond weight

    // FC9 ★: E(cube) = Σ tile interiors + walls, EXACTLY, for both of
    // the spec's unrelated witness weights, at two scales.
    func testFC9TightnessAnyWeight() {
        for (side, k) in [(8, 2), (16, 4)] {
            let cells = specIndexCube(side: side)
            let all = FeedFormat.bonds(side: side)
            let interior = FeedFormat.interiorBonds(side: side, tileSide: k)
            let walls = FeedFormat.wallBonds(side: side, tileSide: k)
            let tiles = FeedFormat.tiles(side: side, tileSide: k)

            // wallCount is integer-valued in Double: exact ==.
            let wTotal = FeedFormat.energy(cells, side: side, bonds: all,
                                           weight: FeedFormat.wallCountWeight)
            let wTiles = tiles.reduce(0.0) {
                $0 + FeedFormat.tileEnergy(cells, side: side, tile: $1, tileSide: k,
                                           weight: FeedFormat.wallCountWeight)
            }
            let wWalls = FeedFormat.energy(cells, side: side, bonds: walls,
                                           weight: FeedFormat.wallCountWeight)
            XCTAssertEqual(wTotal, wTiles + wWalls)
            XCTAssertEqual(wTiles, FeedFormat.energy(cells, side: side, bonds: interior,
                                                     weight: FeedFormat.wallCountWeight))

            // spread is a sum of squares: Wilkinson's n·ε bound over
            // the bond count, derived from the summation itself.
            let sTotal = FeedFormat.energy(cells, side: side, bonds: all,
                                           weight: FeedFormat.spreadWeight)
            let sTiles = tiles.reduce(0.0) {
                $0 + FeedFormat.tileEnergy(cells, side: side, tile: $1, tileSide: k,
                                           weight: FeedFormat.spreadWeight)
            }
            let sWalls = FeedFormat.energy(cells, side: side, bonds: walls,
                                           weight: FeedFormat.spreadWeight)
            let bound = Double(all.count) * .ulpOfOne * sTotal
            XCTAssertEqual(sTotal, sTiles + sWalls, accuracy: bound)
            XCTAssertEqual(sTiles, FeedFormat.energy(cells, side: side, bonds: interior,
                                                     weight: FeedFormat.spreadWeight),
                           accuracy: bound)
        }
    }

    // FC9: interior and wall bonds partition the bond set — disjointly,
    // with nothing left over. The count is the OPEN-boundary count
    // 3·side²·(side−1): this energy does NOT wrap in time, unlike the
    // polyphase laws RL3/TL10 (conflict C6).
    func testFC9BondsPartition() {
        for (side, k) in [(8, 2), (16, 4)] {
            let all = FeedFormat.bonds(side: side)
            let interior = FeedFormat.interiorBonds(side: side, tileSide: k)
            let walls = FeedFormat.wallBonds(side: side, tileSide: k)
            XCTAssertEqual(all.count, 3 * side * side * (side - 1))
            XCTAssertEqual(interior.count + walls.count, all.count)
            XCTAssertTrue(Set(interior).isDisjoint(with: Set(walls)))
            XCTAssertEqual(Set(interior).union(Set(walls)), Set(all))
        }
    }

    // FC9 ★: the weight is a PARAMETER, never baked in. The identity
    // holds for a third, ad-hoc weight the test supplies — OKLab cells
    // under DyadPalette.dLab2, the cost PhaseTiling.hs actually uses.
    // This is the test that fails if anyone later adds a default.
    func testFC9WeightIsNotBakedIn() {
        let side = 8, k = 2
        let indices = specIndexCube(side: side)
        let cells = indices.map { i -> OKLabColor in
            let u = Double(i) / 6
            return DyadPalette.oklab(fromSRGBUnit: (u, 1 - u, u * u))
        }
        let weight: (OKLabColor, OKLabColor) -> Double = { DyadPalette.dLab2($0, $1) }

        let all = FeedFormat.bonds(side: side)
        let interior = FeedFormat.interiorBonds(side: side, tileSide: k)
        let walls = FeedFormat.wallBonds(side: side, tileSide: k)
        let tiles = FeedFormat.tiles(side: side, tileSide: k)

        let total = FeedFormat.energy(cells, side: side, bonds: all, weight: weight)
        let byTiles = tiles.reduce(0.0) {
            $0 + FeedFormat.tileEnergy(cells, side: side, tile: $1, tileSide: k,
                                       weight: weight)
        }
        let byWalls = FeedFormat.energy(cells, side: side, bonds: walls, weight: weight)
        let bound = Double(all.count) * .ulpOfOne * total
        XCTAssertEqual(total, byTiles + byWalls, accuracy: bound)
        XCTAssertEqual(byTiles,
                       FeedFormat.energy(cells, side: side, bonds: interior, weight: weight),
                       accuracy: bound)
        XCTAssertGreaterThan(total, 0, "the fixture must actually cost something")
    }

    // MARK: - FC10 — the sampler interface

    /// FC10 ★, the compile-time half: one generic drain, both feeds.
    private func drain(_ source: some FeedSource, rung: Rung) -> [FeedSample] {
        FeedFormat.coords(side: rung.side).map { source.sample(rung: rung, at: $0) }
    }

    func testFC10SamplerTotality() {
        let feed = SyntheticFeed()
        for side in [4, 8] {
            XCTAssertTrue(FeedFormat.coords(side: side).allSatisfy { cell in
                Self.inUnit(feed.sample(side: side, at: cell))
            }, "feedTotal at side \(side)")
        }
    }

    /// The spec's `inUnit`: every component of a sample in [0,1].
    private static func inUnit(_ s: FeedSample) -> Bool {
        [s.r, s.g, s.b, s.depth].allSatisfy { $0 >= 0 && $0 <= 1 }
    }

    func testFC10SamplerPurityAndRung() {
        let feed = SyntheticFeed()
        let origin = FeedCell(t: 0, y: 0, x: 0)
        XCTAssertEqual(feed.sample(side: 8, at: origin), feed.sample(side: 8, at: origin))
        XCTAssertNotEqual(feed.sample(side: 8, at: origin), feed.sample(side: 16, at: origin))
        var distinct = [FeedSample]()
        for cell in FeedFormat.coords(side: 8).prefix(32) {
            let s = feed.sample(side: 8, at: cell)
            if !distinct.contains(s) { distinct.append(s) }
        }
        XCTAssertGreaterThan(distinct.count, 1, "a feed must not be constant")
    }

    // FC10: parity with the Haskell, EXACT. Every component is k/256 —
    // a dyadic rational, exactly representable in Double — so this
    // asserts `==` and never `accuracy:`. Golden values transcribed
    // from spec/output/FeedCompression.hs's `syntheticFeed`.
    func testFC10SpecParityExact() {
        let feed = SyntheticFeed()
        let golden: [[Double]] = [
            [190, 43, 152, 5],      // (0,0,0)
            [241, 94, 203, 56],     // (0,0,1)
            [36, 145, 254, 107],    // (0,0,2)
            [87, 196, 49, 158],     // (0,0,3)
            [138, 247, 100, 209],   // (0,0,4)
            [189, 42, 151, 4],      // (0,0,5)
            [240, 93, 202, 55],     // (0,0,6)
            [35, 144, 253, 106],    // (0,0,7)
            [86, 195, 48, 157],     // (0,1,0)
            [137, 246, 99, 208],    // (0,1,1)
            [188, 41, 150, 3],      // (0,1,2)
            [239, 92, 201, 54],     // (0,1,3)
        ]
        for (cell, g) in zip(FeedFormat.coords(side: 8), golden) {
            let s = feed.sample(side: 8, at: cell)
            XCTAssertEqual(s, FeedSample(r: g[0] / 256, g: g[1] / 256,
                                         b: g[2] / 256, depth: g[3] / 256),
                           "cell (\(cell.t),\(cell.y),\(cell.x))")
        }
        XCTAssertEqual(feed.sample(side: 8, at: FeedCell(t: 1, y: 2, x: 3)),
                       FeedSample(r: 71 / 256, g: 180 / 256, b: 33 / 256, depth: 142 / 256))
        XCTAssertEqual(feed.sample(side: 16, at: FeedCell(t: 0, y: 0, x: 0)),
                       FeedSample(r: 214 / 256, g: 67 / 256, b: 176 / 256, depth: 29 / 256))
    }

    // FC10 ★: synthetic and real inhabit the SAME TYPE. That `drain`
    // accepts both is the assertion — the compiler checks it; the
    // runtime checks only that both answer for every cell, in range.
    func testFC10SyntheticAndRealSameType() throws {
        let frames = makeFrames(
            colour: { t, y, x -> (Float, Float, Float) in
                let last = Float(Rung.fine.side - 1)
                return (Float(x) / last, Float(y) / last, Float(t) / last)
            },
            depth: self.twoPhaseDepth)
        let pyramid = try XCTUnwrap(FeedFormat.pyramid(from: frames))

        // ONE generic function, both feeds — the compile is the axiom.
        let synthetic = drain(SyntheticFeed(), rung: .coarse)
        let real = drain(CubeFeed(pyramid: pyramid), rung: .coarse)
        for samples in [synthetic, real] {
            XCTAssertEqual(samples.count, Rung.coarse.cells)
            XCTAssertTrue(samples.allSatisfy(Self.inUnit))
        }
        // Totality is structural, including for a rung this feed does
        // not carry: the answer is the producer contract's fill.
        let partial = CubeFeed(cubes: [.coarse: pyramid[2]])
        XCTAssertEqual(partial.sample(rung: .fine, at: FeedCell(t: 0, y: 0, x: 0)),
                       .fill)
    }

    // FC10 / conflict C4: depth in the format is DepthSignal space,
    // never meters. The near/far fixture is built through the producer
    // contract itself, so a meters value entering the format would
    // both break the ordering and trip cube(from:)'s precondition.
    func testFC10DepthIsSignalSpace() throws {
        let nearMeters: Float = 0.3, farMeters: Float = 1.2
        let frames = makeFrames(
            colour: { _, _, _ -> (Float, Float, Float) in (0.5, 0.5, 0.5) },
            depth: { _, _, x in
                // Near on the left half of the frame, far on the right.
                DepthSignal.signalOrFill(
                    meters: x < Rung.fine.side / 2 ? nearMeters : farMeters)
            })
        let pyramid = try XCTUnwrap(FeedFormat.pyramid(from: frames))
        let feed = CubeFeed(pyramid: pyramid)

        XCTAssertTrue(FeedFormat.coords(side: Rung.coarse.side).allSatisfy { cell in
            let d = feed.sample(rung: .coarse, at: cell).depth
            return d >= 0 && d <= 1
        }, "depth never leaves DepthSignal space")
        let near = feed.sample(rung: .coarse, at: FeedCell(t: 0, y: 0, x: 0)).depth
        let far = feed.sample(rung: .coarse, at: FeedCell(t: 0, y: 0, x: Rung.coarse.side - 1)).depth
        XCTAssertGreaterThan(near, far, "1 = near, 0 = far — DepthSignal, not meters")

        // The producer's own value survives pooling up to the two κ
        // summations: Wilkinson's n·ε with n = 8 per step, two steps.
        let poolBound = Double(2 * FeedFormat.kappaCells) * .ulpOfOne
        XCTAssertEqual(near, Double(DepthSignal.signal(meters: nearMeters)),
                       accuracy: poolBound)
        XCTAssertEqual(far, Double(DepthSignal.signal(meters: farMeters)),
                       accuracy: poolBound)

        // DM6: meters are an OUTPUT, never an input. Round-tripping the
        // stored SIGNAL back through metersOf returns the fixture's
        // metres — at Float precision, because DepthSignal produced the
        // signal in Float, times the same two-step pooling bound.
        let meterBound = Double(nearMeters) * Double(Float.ulpOfOne)
                       * Double(2 * FeedFormat.kappaCells)
        XCTAssertEqual(DepthMixture.metersOf(signal: near), Double(nearMeters),
                       accuracy: meterBound)
    }
}
