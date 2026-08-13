// OctaveReadTests.swift
// TesseractTests
//
// Swift-side gates for the OctaveRead port — one test per axiom of
// spec/quantization/Octave.hs (OV1–OV13, the authority). Pure logic:
// no camera, no simulator dependency beyond XCTest itself.
//
// SCALE: the Haskell proves the field laws on a 1/8-linear scale
// model (sides 8 ∥ 4 ∥ 2) only because 64³ cells of ℚ³ is not a
// runghc-sized object. Swift has no such limit, so these tests run at
// the REAL rungs 64 ∥ 32 ∥ 16. Strictly stronger than the spec's
// model; the scale-model caveat does not survive the port.
//
// EXACTNESS: the spec is exact over ℚ, this port is IEEE-754 Double.
// OV4a/OV6/OV7/OV8/OV12 are asserted as BIT-EXACT equality anyway,
// because κ's balanced-tree summation and ×0.125 scaling commute with
// rounding (see OctaveRead.pool). If one of those fails, the fix is
// pool's summation order, NOT a loosened assertion. The laws that do
// need slack (OV4b, OV5, OV9, OV10, OV13) take it from
// OctaveRead.meanErrorBound — Higham Thm 4.6 — never a hand-picked
// epsilon (★NO NAKED CONSTANTS).
//
// The POINT SAMPLE lives here and only here: `decimate` is OV13's
// counter-example operator, not part of the machine, so porting it
// into the app target would put a point-sample rung derivation one
// autocomplete away from the exact thing OV13 forbids.

import XCTest
@testable import Tesseract

final class OctaveReadTests: XCTestCase {

    private typealias Rung = OctaveRead.Rung
    private typealias Field = OctaveRead.Field
    private typealias Dial = OctaveRead.Dial

    // MARK: - Fixture (the spec's §4 generator, at the real rungs)

    /// The spec's LCG, same constants as every other suite
    /// (TriScaleLadderTests, PairTreeTests): s ↦ (1103515245·s + 12345)
    /// mod 2³¹.
    private static func lcg(_ s: Int) -> Int {
        (1103515245 &* s &+ 12345) % 2147483648
    }

    /// The spec's feed: structure at every rung — a ramp (coarse), a
    /// block pattern (mid/coarse) and per-cell wobble (fine). Every
    /// denominator is the spec's, generalised by the rung ratio rather
    /// than copied as a literal: 3·side was 24 at side 8, and 8·midSide
    /// was 32 at midSide 4, so both the structure AND the magnitudes
    /// survive the move to real size. The block term lands on the
    /// COARSE rung (divisor = side / coarse side). The wobble is what
    /// makes OV13's inequality bite: sub-block structure that a mean
    /// averages away and a point sample keeps.
    private static func makeFeed() -> Field {
        let side = Rung.fine.side
        let midSide = Rung.mid.side
        let blockDiv = side / Rung.coarse.side
        let midDiv = side / midSide
        var cells = [OKLabColor]()
        cells.reserveCapacity(Rung.fine.cellCount)
        for t in 0..<side {
            for y in 0..<side {
                for x in 0..<side {
                    let i = (t * side + y) * side + x
                    let ramp = Double(t + y + x) / Double(3 * side)
                    let block = Double((t / blockDiv + x / blockDiv) % 2) / 8
                    cells.append(OKLabColor(
                        l: ramp + block + Double(lcg(i * 7 + 1) % 33) / 512,
                        a: Double(lcg(i * 13 + 5) % 41) / 512
                            + Double(y / midDiv) / Double(8 * midSide),
                        b: Double(lcg(i * 29 + 3) % 37) / 512
                            - Double(x / midDiv) / Double(8 * midSide)))
                }
            }
        }
        guard let field = Field(rung: .fine, cells: cells) else {
            preconditionFailure("fixture must be a lawful fine field")
        }
        return field
    }

    /// Built once: 64³ cells is 6 MB and every test wants the same feed.
    private static let sharedFeed = makeFeed()
    private static let sharedReads = OctaveRead.Reads(fine: sharedFeed)!

    private var feed: Field { OctaveReadTests.sharedFeed }
    private var reads: OctaveRead.Reads { OctaveReadTests.sharedReads }

    // MARK: - Helpers (the counter-example operator and the meters)

    /// ★ OV13's counter-example: nearest-neighbour decimation, one
    /// sample per 2×2×2 block — what Quantize.metal:196-199 ships.
    /// Test-only, deliberately absent from OctaveRead.
    private func decimate(_ f: Field) -> Field? {
        guard let target = f.rung.coarser else { return nil }
        let h = target.side
        var out = [OKLabColor]()
        out.reserveCapacity(target.cellCount)
        for tb in 0..<h {
            for yb in 0..<h {
                for xb in 0..<h { out.append(f[2 * tb, 2 * yb, 2 * xb]) }
            }
        }
        return Field(rung: target, cells: out)
    }

    /// An INDEPENDENT one-shot 4×4×4 mean over the fine field: a
    /// different traversal from pool ∘ pool, so OV13's composition
    /// claim is a real check and not definitionally true. The 64
    /// children are summed pairwise so the Higham Thm 4.6 bound
    /// applies to both sides of the comparison; the independence is in
    /// the traversal, not in the summation rule.
    private func bruteCoarse(_ f: Field) -> Field? {
        guard f.rung == .fine else { return nil }
        let h = Rung.coarse.side
        let k = f.side / h
        var out = [OKLabColor]()
        out.reserveCapacity(Rung.coarse.cellCount)
        for tb in 0..<h {
            for yb in 0..<h {
                for xb in 0..<h {
                    var block = [OKLabColor]()
                    block.reserveCapacity(k * k * k)
                    for dt in 0..<k {
                        for dy in 0..<k {
                            for dx in 0..<k {
                                block.append(f[tb * k + dt, yb * k + dy, xb * k + dx])
                            }
                        }
                    }
                    out.append(OctaveRead.pairwiseMean(block[...]))
                }
            }
        }
        return Field(rung: .coarse, cells: out)
    }

    /// The t ↔ x transpose: g[t, y, x] = f[x, y, t]. OV10's fixture.
    private func transposeTX(_ f: Field) -> Field? {
        let n = f.side
        var out = [OKLabColor]()
        out.reserveCapacity(f.cells.count)
        for t in 0..<n {
            for y in 0..<n {
                for x in 0..<n { out.append(f[x, y, t]) }
            }
        }
        return Field(rung: f.rung, cells: out)
    }

    private func maxAbsDiff(_ f: Field, _ g: Field) -> Double {
        var worst = 0.0
        for i in 0..<f.cells.count {
            worst = max(worst, abs(f.cells[i].l - g.cells[i].l))
            worst = max(worst, abs(f.cells[i].a - g.cells[i].a))
            worst = max(worst, abs(f.cells[i].b - g.cells[i].b))
        }
        return worst
    }

    private func maxAbsDiff(_ p: OKLabColor, _ q: OKLabColor) -> Double {
        max(abs(p.l - q.l), max(abs(p.a - q.a), abs(p.b - q.b)))
    }

    // ── The tolerances, all derived from Higham Thm 4.6 ────────────

    /// γ_k · absSum: the SUM bound, i.e. meanErrorBound with its 1/n
    /// scaled back off (the mean is the sum divided by a power of two,
    /// which is exact).
    private func sumBound(count: Int, absSum: Double) -> Double {
        Double(count) * OctaveRead.meanErrorBound(count: count, absSum: absSum)
    }

    /// Tolerance between two roundings of the same block mean, where
    /// each output cell averages `blockCells` fine cells of L1 mass
    /// `blockAbsSum`: γ_k for the one-shot pairwise mean, plus γ_3 per
    /// composed 8-child pooling level (two levels at most here).
    private func blockMeanTolerance(blockCells: Int, blockAbsSum: Double) -> Double {
        (sumBound(count: blockCells, absSum: blockAbsSum)
            + 2 * sumBound(count: 8, absSum: blockAbsSum)) / Double(blockCells)
    }

    /// Tolerance on Σ‖v‖²: the pairwise sum bound over `count` terms
    /// plus twice γ_3 for the squared relative perturbation a pooled
    /// cell carries (squaring doubles a relative error).
    private func energyTolerance(count: Int, energy: Double) -> Double {
        sumBound(count: count, absSum: energy) + 2 * sumBound(count: 8, absSum: energy)
    }

    /// Tolerance on a grand mean that has been through `stages`
    /// poolings before being summed.
    private func grandMeanTolerance(_ f: Field, stages: Int) -> Double {
        Double(1 + stages) * OctaveRead.meanErrorBound(
            count: f.cells.count, absSum: OctaveRead.l1Mass(f))
    }

    /// The L1 mass of the heaviest block of `blockCells` fine cells —
    /// the absSum the block-mean bound is stated in.
    private func maxBlockL1(_ f: Field, blockSide k: Int) -> Double {
        let h = f.side / k
        var worst = 0.0
        for tb in 0..<h {
            for yb in 0..<h {
                for xb in 0..<h {
                    var mass = 0.0
                    for dt in 0..<k {
                        for dy in 0..<k {
                            for dx in 0..<k {
                                let c = f[tb * k + dt, yb * k + dy, xb * k + dx]
                                mass += abs(c.l) + abs(c.a) + abs(c.b)
                            }
                        }
                    }
                    worst = max(worst, mass)
                }
            }
        }
        return worst
    }

    // MARK: - OV1  the rung set {64, 32, 16}, factor 2, floor 16

    func testRungSetIsFactorTwoWithFloorSixteen() {
        XCTAssertEqual(Rung.allCases.count, 3,
                       "OV1: three rungs, and a fourth is unrepresentable")
        let sides = Rung.allCases.map(\.side)
        XCTAssertEqual(sides, [64, 32, 16], "OV1: the rung set is {64, 32, 16}")
        XCTAssertEqual(Rung.fine.side, RungTelemetry.baseRungSide,
                       "OV1: the ceiling is TriScaleLadder's base rung, derived")
        XCTAssertEqual(Rung.coarse.side, RungTelemetry.depthRungSide,
                       "OV1: the floor is the resolution of depth (TL9), derived")
        XCTAssertEqual(Rung.mid.side, Rung.fine.side / 2,
                       "OV1: adjacent rungs differ by a factor of two")
        XCTAssertEqual(Rung.mid.side, Rung.coarse.side * 2,
                       "OV1: adjacent rungs differ by a factor of two")
        XCTAssertNil(Rung.coarse.coarser,
                     "OV1/OV2: nothing below the floor, structurally")
        XCTAssertNil(Rung.fine.finer,
                     "OV1: nothing above 64 — 128 has no integer GIF delay (TL4)")
        XCTAssertEqual(Rung.fine.cellCount, 64 * 64 * 64, "OV1: side³ cells")
        XCTAssertEqual(Rung.coarse.cellCount, 16 * 16 * 16, "OV1: side³ cells")
    }

    // MARK: - OV2  ★ THE BIJECTION FLOOR: 16² = 256 = |palette|

    func testBijectionFloor() {
        let floorSide = Rung.coarse.side
        XCTAssertEqual(floorSide * floorSide, CameraConfig.paletteSize,
                       "OV2: at rung 16 the image and the colour table are the "
                       + "same size — one pixel per entry")
        XCTAssertLessThan((floorSide / 2) * (floorSide / 2), CameraConfig.paletteSize,
                          "OV2: 8² = 64 < 256 — three quarters of the table "
                          + "could not be addressed even once")
        for rung in Rung.allCases {
            XCTAssertGreaterThanOrEqual(rung.side * rung.side, CameraConfig.paletteSize,
                                        "OV2: every lawful rung addresses the whole table")
        }
        XCTAssertNil(OctaveRead.pool(reads.coarse),
                     "OV2: κ cannot produce a rung below the floor")
    }

    // MARK: - OV3  ★ THE LADDER 1,1,2,4,8,16,32,64 mirrored

    func testLadderIsDyadPalettesShellsMirrored() {
        let ladder = OctaveRead.ladder
        XCTAssertEqual(ladder, DyadPalette.ladder + DyadPalette.ladder.reversed(),
                       "OV3: the ladder IS DyadPalette's shells plus their σ-mirror")
        XCTAssertEqual(ladder, [1, 1, 2, 4, 8, 16, 32, 64, 64, 32, 16, 8, 4, 2, 1, 1],
                       "OV3: Daniel's ladder, written out")
        XCTAssertEqual(ladder.reduce(0, +), CameraConfig.paletteSize,
                       "OV3: the shells sum to the whole palette")
        XCTAssertEqual(DyadPalette.ladder.reduce(0, +), DyadPalette.primaryCount,
                       "OV3: the half is the 128 primaries the solver already builds")
        XCTAssertEqual(ladder, ladder.reversed(),
                       "OV3: σ-symmetric about its middle (PT6)")
        XCTAssertEqual(ladder.count, Rung.coarse.side,
                       "OV3: one shell per row of the rung-16 image")
        for (a, b) in zip(DyadPalette.ladder.dropFirst(), DyadPalette.ladder.dropFirst(2)) {
            XCTAssertEqual(b, 2 * a, "OV3: the half doubles after its first step")
        }
    }

    // MARK: - OV4a  pool ∘ up = id, EXACTLY

    func testPoolAfterUpIsExactlyIdentity() throws {
        let upMid = try XCTUnwrap(OctaveRead.up(reads.mid))
        XCTAssertEqual(try XCTUnwrap(OctaveRead.pool(upMid)), reads.mid,
                       "OV4: pool ∘ up is the identity, BIT-EXACT — replication "
                       + "then a balanced-tree mean scaled by 0.125 cannot round")
        let upCoarse = try XCTUnwrap(OctaveRead.up(reads.coarse))
        XCTAssertEqual(try XCTUnwrap(OctaveRead.pool(upCoarse)), reads.coarse,
                       "OV4: pool ∘ up is the identity at the floor too")
    }

    // MARK: - OV4b  all three reads share one mean

    func testAllThreeReadsShareOneMean() {
        let tolerance = grandMeanTolerance(feed, stages: 2)
        let mFine = OctaveRead.mean(reads.fine)
        let mMid = OctaveRead.mean(reads.mid)
        let mCoarse = OctaveRead.mean(reads.coarse)
        XCTAssertLessThanOrEqual(maxAbsDiff(mFine, mMid), tolerance,
                                 "OV4: κ conserves the mean (fine vs mid)")
        XCTAssertLessThanOrEqual(maxAbsDiff(mMid, mCoarse), tolerance,
                                 "OV4: κ conserves the mean (mid vs coarse)")
        XCTAssertLessThanOrEqual(maxAbsDiff(mFine, mCoarse), tolerance,
                                 "OV4: all three parallel reads describe one scene's colour")
        XCTAssertEqual(reads.fine.cells.count, Rung.fine.cellCount, "OV4: sizes")
        XCTAssertEqual(reads.mid.cells.count, Rung.mid.cellCount, "OV4: sizes")
        XCTAssertEqual(reads.coarse.cells.count, Rung.coarse.cellCount, "OV4: sizes")
    }

    // MARK: - OV5  ★ MEAN INVARIANCE at every dial setting

    func testMeanInvarianceAtEveryDial() {
        // The spec's eight settings plus the degenerate all-zero.
        let settings = [(0, 0, 7), (7, 0, 0), (0, 7, 0), (1, 1, 1),
                        (4, 2, 1), (1, 2, 4), (7, 7, 7), (2, 5, 3), (0, 0, 0)]
        let tolerance = grandMeanTolerance(feed, stages: 2)
        let target = OctaveRead.mean(feed)
        for (c, m, f) in settings {
            let blended = OctaveRead.blend(Dial(coarse: c, mid: m, fine: f), reads)
            XCTAssertEqual(blended.rung, .fine,
                           "OV5: the blend always lands on the fine rung — dial (\(c), \(m), \(f))")
            XCTAssertLessThanOrEqual(maxAbsDiff(OctaveRead.mean(blended), target), tolerance,
                                     "OV5: exposure, white point and cast cannot drift "
                                     + "— dial (\(c), \(m), \(f))")
        }
    }

    // MARK: - OV6  identity: pure-fine is an exact pass-through

    func testPureFineIsExactPassThrough() {
        XCTAssertEqual(OctaveRead.blend(.identity, reads), feed,
                       "OV6: the default dial reproduces today's bytes EXACTLY "
                       + "— the weight ratio is exactly 1.0")
        let one = OctaveRead.blend(Dial(coarse: 0, mid: 0, fine: 1), reads)
        XCTAssertEqual(one, feed, "OV6: any pure-fine setting is the identity")
        XCTAssertEqual(OctaveRead.blend(Dial(coarse: 0, mid: 0, fine: 7), reads), one,
                       "OV6: the dial is scale-free — (0,0,7) ≡ (0,0,1)")
        XCTAssertEqual(Dial.identity, Dial(coarse: 0, mid: 0, fine: 7),
                       "OV6: the identity dial is (0, 0, 7)")
    }

    // MARK: - OV7  pure-coarse / pure-mid are the upsampled reads

    func testPureCoarseAndPureMid() throws {
        let liftedCoarse = try XCTUnwrap(OctaveRead.up(try XCTUnwrap(OctaveRead.up(reads.coarse))))
        let liftedMid = try XCTUnwrap(OctaveRead.up(reads.mid))
        XCTAssertEqual(OctaveRead.blend(Dial(coarse: 7, mid: 0, fine: 0), reads), liftedCoarse,
                       "OV7: pure-coarse is the 16-rung read upsampled twice, EXACTLY")
        XCTAssertEqual(OctaveRead.blend(Dial(coarse: 0, mid: 7, fine: 0), reads), liftedMid,
                       "OV7: pure-mid is the 32-rung read upsampled once, EXACTLY")
        let tolerance = grandMeanTolerance(feed, stages: 2)
        let target = OctaveRead.mean(feed)
        XCTAssertLessThanOrEqual(maxAbsDiff(OctaveRead.mean(liftedCoarse), target), tolerance,
                                 "OV7: the extreme the dial can reach still holds the mean")
        XCTAssertLessThanOrEqual(maxAbsDiff(OctaveRead.mean(liftedMid), target), tolerance,
                                 "OV7: so does pure-mid")
    }

    // MARK: - OV8  the blend is convex and scale-free

    func testBlendIsConvexAndScaleFree() throws {
        let equal = OctaveRead.blend(Dial(coarse: 1, mid: 1, fine: 1), reads)
        XCTAssertEqual(OctaveRead.blend(Dial(coarse: 2, mid: 2, fine: 2), reads), equal,
                       "OV8: (2,2,2) ≡ (1,1,1) — 2/6 and 1/3 are the same Double, "
                       + "IEEE division being correctly rounded")
        XCTAssertEqual(OctaveRead.blend(Dial(coarse: 3, mid: 3, fine: 3), reads), equal,
                       "OV8: (3,3,3) ≡ (1,1,1), bit-exact")

        // An independently built equal-thirds field. ⚠ It must not be
        // `third*c + third*m + third*f`: that is `blend`'s own
        // expression, operation for operation and association for
        // association, so the difference would be exactly 0.0 at every
        // cell and the tolerance below would be decorative — the
        // assertion could not tell `blend` from `liftToFine(coarse)`.
        // Sum THEN divide: the same convex combination by a different
        // floating-point path, so agreement is a real measurement.
        let liftedCoarse = try XCTUnwrap(OctaveRead.up(try XCTUnwrap(OctaveRead.up(reads.coarse))))
        let liftedMid = try XCTUnwrap(OctaveRead.up(reads.mid))
        var cells = [OKLabColor]()
        cells.reserveCapacity(feed.cells.count)
        for i in 0..<feed.cells.count {
            let c = liftedCoarse.cells[i], m = liftedMid.cells[i], f = feed.cells[i]
            cells.append(OKLabColor(l: (c.l + m.l + f.l) / 3,
                                    a: (c.a + m.a + f.a) / 3,
                                    b: (c.b + m.b + f.b) / 3))
        }
        let independent = try XCTUnwrap(Field(rung: .fine, cells: cells))
        let tolerance = blockMeanTolerance(blockCells: 8,
                                           blockAbsSum: maxBlockL1(feed, blockSide: 2))
        XCTAssertLessThanOrEqual(maxAbsDiff(independent, equal), tolerance,
                                 "OV8: the blend is a convex combination of the three reads")
    }

    // MARK: - OV9  monotone in each dial

    func testMonotoneInEachDial() {
        let flat = OctaveRead.flat(OctaveRead.mean(feed))
        func departure(_ c: Int, _ m: Int, _ f: Int) -> Double {
            let blended = OctaveRead.blend(Dial(coarse: c, mid: m, fine: f), reads)
            guard let delta = OctaveRead.difference(blended, flat) else { return .nan }
            return OctaveRead.energy(delta)
        }
        let scale = max(departure(7, 0, 0), departure(0, 0, 7))
        let tolerance = energyTolerance(count: Rung.fine.cellCount, energy: scale)
        for w in 0...6 {
            XCTAssertLessThanOrEqual(departure(4, 0, w), departure(4, 0, w + 1) + tolerance,
                                     "OV9: departure from flat is non-decreasing in the "
                                     + "fine dial (coarse fixed at 4, fine \(w) → \(w + 1))")
            XCTAssertLessThanOrEqual(departure(0, 4, w), departure(0, 4, w + 1) + tolerance,
                                     "OV9: and in the fine dial against a fixed mid "
                                     + "(mid 4, fine \(w) → \(w + 1))")
        }
        XCTAssertLessThan(departure(7, 0, 0), departure(0, 0, 7),
                          "OV9: pure-coarse departs from flat LESS than pure-fine "
                          + "— κ has averaged the sub-block structure away")
    }

    // MARK: - OV10  ★ κ cannot tell x, y and FRAME apart

    func testKappaCannotTellFrameFromSpace() throws {
        let swapped = try XCTUnwrap(transposeTX(feed))
        let swappedReads = try XCTUnwrap(OctaveRead.Reads(fine: swapped))
        let meanTolerance = grandMeanTolerance(feed, stages: 2)
        XCTAssertLessThanOrEqual(
            maxAbsDiff(OctaveRead.mean(swappedReads.coarse), OctaveRead.mean(reads.coarse)),
            meanTolerance,
            "OV10: a t ↔ x transpose preserves the pooled mean")

        let coarseEnergy = OctaveRead.energy(reads.coarse)
        XCTAssertLessThanOrEqual(
            abs(OctaveRead.energy(swappedReads.coarse) - coarseEnergy),
            energyTolerance(count: Rung.coarse.cellCount, energy: coarseEnergy),
            "OV10: and the pooled energy — the FRAME axis is just another axis")
        let midEnergy = OctaveRead.energy(reads.mid)
        XCTAssertLessThanOrEqual(
            abs(OctaveRead.energy(swappedReads.mid) - midEnergy),
            energyTolerance(count: Rung.mid.cellCount, energy: midEnergy),
            "OV10: the same at the mid rung")

        XCTAssertEqual(try XCTUnwrap(transposeTX(swapped)), feed,
                       "OV10: the transpose is an involution, exactly")
    }

    // MARK: - OV11  the grid is 8 states per dial

    func testDialGridIsEightStates() {
        XCTAssertEqual(Dial.stateCount, DyadPalette.ladder.count,
                       "OV11: one state per ladder level = one per pair-tree "
                       + "generation plus the root (RoleAllocation widgetCells)")
        XCTAssertEqual(Dial.stateCount, 8, "OV11: which is 8")
        for w in 0..<(Dial.stateCount - 1) {
            let low = Dial(coarse: 0, mid: 0, fine: w)
            let high = Dial(coarse: 0, mid: 0, fine: w + 1)
            XCTAssertEqual(high.fine - low.fine, 1, "OV11: the weights step by one")
        }
        // Structural: an out-of-grid dial cannot exist.
        let clamped = Dial(coarse: -3, mid: 99, fine: 4)
        XCTAssertEqual(clamped, Dial(coarse: 0, mid: 7, fine: 4),
                       "OV11: out-of-grid settings are clamped at construction, "
                       + "so an unlawful dial is unrepresentable")
        for w in [Dial.identity.coarse, Dial.identity.mid, Dial.identity.fine] {
            XCTAssertTrue(w >= 0 && w < Dial.stateCount,
                          "OV11: the identity dial lives inside the grid")
        }
    }

    // MARK: - OV12  the atom: 2×2×2 ↔ 1 is three composed 2 → 1 means

    func testAtomIsThreeComposedBinaryMeans() {
        // The spec's octet: eight consecutive cells. ⚠ These are NOT
        // κ's eight children — at the fine rung those sit at strides
        // 1, 64 and 4096, and this run is along x only. OV12 is a
        // claim about MEAN ALGEBRA (a one-shot mean of 8 equals three
        // composed binary means), not about traversal, so any eight
        // values test it; `pool`'s addressing is covered by OV4/OV13.
        let octet = feed.cells[64..<72]
        let oneShot = OctaveRead.pairwiseMean(octet)
        func binaryMeans(_ xs: [OKLabColor]) -> [OKLabColor] {
            stride(from: 0, to: xs.count, by: 2).map { i in
                OKLabColor(l: (xs[i].l + xs[i + 1].l) / 2,
                           a: (xs[i].a + xs[i + 1].a) / 2,
                           b: (xs[i].b + xs[i + 1].b) / 2)
            }
        }
        let composed = binaryMeans(binaryMeans(binaryMeans(Array(octet))))
        XCTAssertEqual(composed.count, 1, "OV12: three levels take eight to one")
        XCTAssertEqual(oneShot, composed[0],
                       "OV12: the one-shot mean of eight is BIT-EQUAL to three "
                       + "composed binary means. If this fails, pool's summation "
                       + "order is wrong — do not loosen the assertion.")
    }

    // MARK: - OV13a  ★ direct coarse read ≡ pooled fine read (MEAN)

    func testDirectCoarseReadEqualsPooledFineRead() throws {
        let pooled = try XCTUnwrap(OctaveRead.pool(try XCTUnwrap(OctaveRead.pool(feed))))
        let direct = try XCTUnwrap(bruteCoarse(feed))
        let tolerance = blockMeanTolerance(blockCells: 64,
                                           blockAbsSum: maxBlockL1(feed, blockSide: 4))
        XCTAssertLessThanOrEqual(maxAbsDiff(pooled, direct), tolerance,
                                 "OV13: κ COMPOSES — reading directly at rung 16 and "
                                 + "pooling the 64-rung read describe one scene. This "
                                 + "is what licenses three simultaneous reads.")
        XCTAssertEqual(pooled.rung, .coarse, "OV13: two poolings land on the floor")
    }

    // MARK: - OV13b  ★ and a POINT SAMPLE breaks it

    func testPointSampleBreaksParallelCoherence() throws {
        // ★ THE GATE. The shipping funnel point-samples
        // (Quantize.metal:196-199 downsampleRGB, one texel per 12×12
        // block; :212-215 downsampleDepth — docs/CAPTURE-FUNNELS.md §1),
        // so the coherence OV13 asserts does NOT reach the sensor today.
        // The box prefilter that would fix it is rate-ladder step S2,
        // gated on Daniel's S2–S6 step-order ruling AND on the device
        // probe of the delivered buffer dimensions (★NO CROP CHANGES).
        // This test is the standing proof that the two operators are
        // not interchangeable — the disagreement below is real
        // structure, orders of magnitude above the rounding bound, not
        // an inequality that a tighter Double would erase.
        let pooledTwice = try XCTUnwrap(OctaveRead.pool(try XCTUnwrap(OctaveRead.pool(feed))))
        let decimatedTwice = try XCTUnwrap(decimate(try XCTUnwrap(decimate(feed))))
        let coarseTolerance = blockMeanTolerance(blockCells: 64,
                                                 blockAbsSum: maxBlockL1(feed, blockSide: 4))
        XCTAssertGreaterThan(maxAbsDiff(decimatedTwice, pooledTwice), coarseTolerance,
                             "OV13: decimation does NOT compose with κ — the 16³ stream "
                             + "would disagree with the pooled 64³ stream about the "
                             + "same scene")

        let pooledOnce = try XCTUnwrap(OctaveRead.pool(feed))
        let decimatedOnce = try XCTUnwrap(decimate(feed))
        let midTolerance = blockMeanTolerance(blockCells: 8,
                                              blockAbsSum: maxBlockL1(feed, blockSide: 2))
        XCTAssertGreaterThan(maxAbsDiff(decimatedOnce, pooledOnce), midTolerance,
                             "OV13: one step is already enough to break it")
    }

    // MARK: - B1 (bridge, NOT an axiom)

    /// ATLAS §7 step 4's claim — "BLEEDING's 4×4×4 block mean becomes
    /// level 2 of the octave" — checked against the SHIPPING pooling.
    /// Since EM13 the spatial half is callable (DyadPipeline.chaosPool,
    /// the one pool the export's dither and the live surface share), so
    /// this is a parity test, not a mirrored re-implementation; only the
    /// temporal half (4-frame groups aligned at frame 0) is spelled out.
    func testBleedingBlockMeanIsOctaveLevelTwo() throws {
        let side = feed.side
        let rung = DyadPipeline.chaosRung
        let bSide = side / rung
        let blockCount = bSide * bSide
        let spatial = (0..<side).map { f in
            DyadPipeline.chaosPool(
                labs: (0..<(side * side)).map { feed[f, $0 / side, $0 % side] },
                side: side)
        }
        XCTAssertEqual(spatial[0].count, blockCount)
        var cells = [OKLabColor]()
        cells.reserveCapacity(Rung.coarse.cellCount)
        for g in 0..<(side / rung) {
            for b in 0..<blockCount {
                var sl = 0.0, sa = 0.0, sb = 0.0
                for f in (rung * g)..<(rung * g + rung) {
                    sl += spatial[f][b].l; sa += spatial[f][b].a; sb += spatial[f][b].b
                }
                let n = Double(rung)
                cells.append(OKLabColor(l: sl / n, a: sa / n, b: sb / n))
            }
        }
        let bleeding = try XCTUnwrap(Field(rung: .coarse, cells: cells))
        let pooled = try XCTUnwrap(OctaveRead.pool(try XCTUnwrap(OctaveRead.pool(feed))))
        let tolerance = blockMeanTolerance(blockCells: 64,
                                           blockAbsSum: maxBlockL1(feed, blockSide: 4))
        XCTAssertLessThanOrEqual(maxAbsDiff(bleeding, pooled), tolerance,
                                 "B1: BLEEDING's 4×4×4 spacetime block mean IS level 2 "
                                 + "of the octave — the same operator, not a coincidence")
    }

    // MARK: - The adapters (the only impure edge)

    func testFineReadAdaptersRejectMalformedBursts() throws {
        let side = Rung.fine.side
        let frame = [OKLabColor](repeating: OKLabColor(l: 0, a: 0, b: 0), count: side * side)
        XCTAssertNotNil(OctaveRead.fineRead(frames: [[OKLabColor]](repeating: frame, count: side)),
                        "a full 64-frame burst of 64×64 frames is a lawful fine read")
        XCTAssertNil(OctaveRead.fineRead(frames: [[OKLabColor]](repeating: frame, count: side - 1)),
                     "a short burst is not a fine read")
        XCTAssertNil(OctaveRead.fineRead(frames: [[OKLabColor]](
            repeating: Array(frame.dropLast()), count: side)),
                     "an undersized frame is not a fine read")

        // The captured-frame adapter delegates its colour conversion to
        // the two calls the live read already makes; a constant burst must
        // land on exactly that colour.
        let pixel: (Float, Float, Float) = (0.25, 0.5, 0.75)
        let captured = (0..<side).map { i in
            CapturedFrame(index: i,
                          rgb: [(Float, Float, Float)](repeating: pixel, count: side * side),
                          depths: [Float](repeating: 0, count: side * side),
                          timestamp: 0)
        }
        let field = try XCTUnwrap(OctaveRead.fineRead(captured: captured))
        let expected = DyadPalette.oklab(fromSRGB8: DyadPipeline.srgb8(from: pixel))
        XCTAssertEqual(field.cells[0], expected,
                       "the adapter delegates colour conversion, never re-implements it")
        XCTAssertEqual(field.rung, .fine, "the captured adapter reads at the fine rung")
    }
}
