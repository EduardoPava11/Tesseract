// ════════════════════════════════════════════════════════════════
// EditDialTests: the eFig dial moves bytes, or it is not a dial
//
// ★ WHY THIS FILE EXISTS. Reweave could represent all five axes of
// RoleAllocation's edit space and EXECUTE exactly one point of 32768.
// Its own header named the blocker: "the shipped solver exposes
// depth-4 nodes only (PairTree `nodes16`), so general depths need the
// descent to record every level". The descent already VISITED every
// level and recorded one of them, so the whole edit space was
// unreachable for want of about two kilobytes of node means.
//
// PairTree.Figures now carries `levels`, and `truncated(toFigureDepth:)`
// applies PT5's prefix law as a lookup. This file is the gate on that.
//
// ★ AND THE ANTI-VACUITY TEST IS THE POINT. The failure mode this
// codebase keeps hitting is a control that reports success and changes
// nothing: a dial that silently returns the identity would make the
// surface lie about what it did. So the load-bearing assertion here is
// not that truncation is correct, it is that the dial MOVES EXPORTED
// BYTES, and that the identity position still does not.
// ════════════════════════════════════════════════════════════════

import XCTest
@testable import Tesseract

final class EditDialTests: XCTestCase {

    // MARK: - Fixture

    /// A deterministic figure-over-ground cube. Small frame count: the
    /// dial is a per-frame table property, so 8 frames exercise it and
    /// 64 only cost time.
    private func cube(side: Int = 64, frames: Int = 8) -> CubeStore.Cube {
        var rgb: [[(Float, Float, Float)]] = []
        var depth: [[Float]] = []
        let cx = Float(side) / 2, cy = Float(side) / 2, r = Float(side) / 3
        for f in 0..<frames {
            var fr = [(Float, Float, Float)](), fd = [Float]()
            fr.reserveCapacity(side * side); fd.reserveCapacity(side * side)
            let drift = Float(f) / Float(max(1, frames))
            for y in 0..<side {
                for x in 0..<side {
                    let dx = Float(x) - cx - 3 * drift, dy = Float(y) - cy
                    let u = Float(x) / Float(side - 1), v = Float(y) / Float(side - 1)
                    if dx * dx + dy * dy < r * r {
                        fr.append((0.55 + 0.30 * u, 0.34 + 0.18 * v, 0.26 + 0.10 * u))
                        fd.append(0.85)                    // near, in SIGNAL units
                    } else {
                        fr.append((0.16 + 0.10 * v, 0.20 + 0.12 * u, 0.38 + 0.22 * v))
                        fd.append(0.15)                    // far
                    }
                }
            }
            rgb.append(fr); depth.append(fd)
        }
        return CubeStore.Cube(side: side, rgb: rgb, depths: depth)
    }

    private func stats() -> DyadPalette.Stats {
        let c = cube(side: 32, frames: 1)
        let samples = c.rgb[0].map { DyadPipeline.srgb8(from: $0) }
        return DyadPalette.analyze(samples,
                                   weights: [Double](repeating: 1, count: samples.count))
    }

    // MARK: - ★ The prefix law, on the shipped tree

    func testEveryLevelIsRecordedAtTheRightSize() {
        let f = PairTree.solveFigures(stats: stats())
        XCTAssertEqual(f.levels.count, 8, "depths 0 through 7")
        for d in 0...7 {
            XCTAssertEqual(f.levels[d].count, 1 << d,
                           "level \(d) must hold 2^\(d) node means")
        }
        XCTAssertEqual(f.levels[7].count, 128, "the leaves")
        XCTAssertEqual(f.levels[4].count, f.nodes16.count)
    }

    /// nodes16 was the ONLY level recorded before this change, so it is
    /// the one place a regression would be silent.
    func testNodes16IsExactlyLevelFour() {
        let f = PairTree.solveFigures(stats: stats())
        for (a, b) in zip(f.nodes16, f.levels[4]) {
            XCTAssertEqual(a.l, b.l, accuracy: 0)
            XCTAssertEqual(a.a, b.a, accuracy: 0)
            XCTAssertEqual(a.b, b.b, accuracy: 0)
        }
    }

    /// PT5: a truncated index names the coarser level's node. Stated
    /// on the SHIPPED analytic tree rather than on a dyadic fixture,
    /// which is the gap the adversarial run found in PT5 itself.
    func testTruncationIsThePrefixLaw() {
        let f = PairTree.solveFigures(stats: stats())
        for d in 0...6 {
            let t = f.truncated(toFigureDepth: d)
            let shift = 7 - d
            for j in 0..<128 {
                let expect = DyadPalette.srgb8(
                    from: DyadPalette.chromaClamp(
                        DyadPalette.clampL(f.levels[d][j >> shift])))
                XCTAssertEqual(t.figures8[j].0, expect.0, "leaf \(j) at depth \(d)")
                XCTAssertEqual(t.figures8[j].1, expect.1)
                XCTAssertEqual(t.figures8[j].2, expect.2)
            }
        }
    }

    func testDepthSevenIsTheIdentity() {
        let f = PairTree.solveFigures(stats: stats())
        let t = f.truncated(toFigureDepth: PairTree.fullDepth)
        XCTAssertEqual(t.figures8.count, f.figures8.count)
        for j in 0..<f.figures8.count {
            XCTAssertTrue(t.figures8[j] == f.figures8[j], "leaf \(j)")
        }
    }

    /// The dial's MEANING: fewer, coarser figure primaries. If this
    /// does not hold the control is decorative.
    func testCoarserDepthsRealiseFewerColours() {
        let f = PairTree.solveFigures(stats: stats())
        var previous = 0
        for d in 0...7 {
            var seen = Set<Int>()
            for c in f.truncated(toFigureDepth: d).figures8 {
                seen.insert(Int(c.0) << 16 | Int(c.1) << 8 | Int(c.2))
            }
            let distinct = seen.count
            XCTAssertLessThanOrEqual(distinct, 1 << d,
                "depth \(d) cannot realise more than 2^\(d) colours")
            // ★ MONOTONE UPWARD, because d ascends. The first version of
            // this assertion had the comparison backwards and failed on a
            // perfectly correct 1, 2, 4, 8, 16, 32, 64, 128.
            XCTAssertGreaterThanOrEqual(distinct, previous,
                "a deeper tree cannot realise FEWER colours than a shallower one")
            previous = distinct
        }
    }

    // MARK: - ★ THE ANTI-VACUITY GATE: the dial moves exported bytes

    func testTheIdentityEditReproducesTheOrdinaryExport() throws {
        let c = cube()
        let plain = try XCTUnwrap(
            GIFMachine.makeGIF(rgb: c.rgb, depths: c.depths),
            "the fixture must export at all")
        switch Reweave.reweave(cube: c, edit: .identity) {
        case .failure(let why):
            XCTFail("the identity edit must not refuse: \(why)")
        case .success(let out):
            XCTAssertEqual(out.data, plain.data,
                "reweave at the identity must be the ordinary export, byte for byte")
        }
    }

    func testTheFigureDialChangesTheExportedBytes() throws {
        let c = cube()
        let base = try XCTUnwrap(GIFMachine.makeGIF(rgb: c.rgb, depths: c.depths))
        var moved = 0
        for d in 0...6 {
            var e = Reweave.Edit.identity
            e.fig = d
            switch Reweave.reweave(cube: c, edit: e) {
            case .failure(let why):
                XCTFail("eFig \(d) must be executable now, got \(why)")
            case .success(let out):
                if out.data != base.data { moved += 1 }
            }
        }
        XCTAssertEqual(moved, 7,
            """
            Every coarser figure depth must produce a DIFFERENT GIF. A dial \
            that reports success and emits identical bytes is the failure \
            this file exists to prevent.
            """)
    }

    /// eGnd is still refused, and the refusal must SAY so rather than
    /// quietly returning the identity result.
    func testTheGroundDialStillRefusesWithAReason() {
        var e = Reweave.Edit.identity
        e.gnd = (Reweave.Edit.identity.gnd + 1) % 8
        switch Reweave.reweave(cube: cube(), edit: e) {
        case .success:
            XCTFail("eGnd is not implemented; succeeding here would be a lie")
        case .failure(let why):
            guard case .notYetLawful(let reason) = why else {
                return XCTFail("expected a reasoned refusal, got \(why)")
            }
            XCTAssertTrue(reason.contains("S5"),
                          "the refusal must name what is missing")
        }
    }
}
