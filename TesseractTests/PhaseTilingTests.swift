// PhaseTilingTests.swift
// Tesseract
//
// Swift gate for the PhaseTiling port (spec/statistics/PhaseTiling.hs
// is authoritative — PD1–PD10). Every axiom is either a case here or
// is discharged STRUCTURALLY by a type in PhaseTiling.swift, and each
// structural discharge carries a comment in the source naming the
// axiom it stands for. Nothing is silently dropped.
//
// ── FIXTURE FIDELITY ────────────────────────────────────────────
//
// The spec is exact over ℚ; this port is Double. Two consequences,
// both handled explicitly rather than papered over:
//
//   1. The spec's palette is `n % 1000` in ℚ; the Swift fixture is
//      Double(n)/1000, which is NOT binary-exact. So the INTEGER
//      conclusions (phase counts, bond counts, rank DISAGREEMENT)
//      are asserted bit-for-bit against the Haskell run, and the
//      real-valued ones within PhaseTiling.summationSlack. Nothing
//      is asserted against the spec's printed 248.460 / 1043.000.
//
//   2. The spec's model tiles 8³ by 2³ (64 tiles), standing in for
//      the app's 64³ by 4³ (4096 tiles) — "the decomposition is
//      size-independent". The port pins the tile to ANELoop.blockSide
//      because the tile IS the ANELoop block, so the fixture carries
//      the spec's model cube REPLICATED ×2 on all three axes to 16³.
//      Uniform ×2 replication maps spec tile (tb, yb, xb) onto port
//      tile (tb, yb, xb) cell-for-cell with every spec cell counted
//      8 times, so φ is IDENTICAL per tile and the phase counts are
//      the spec's exactly: FACE 4 / BAND 28 / SOLID 32 over 64 tiles.
//      (The energies are not the spec's — replication adds zero-cost
//      bonds — which is why no float total is asserted against it.)
//
// A second, non-replicated fixture at the real dimensions (64³ over
// 4096 tiles, built through the Data/LCT initializer) exercises the
// shipping shape and the per-frame-table extension.

import XCTest
@testable import Tesseract

// MARK: - Fixtures (test-only; never in shipping code)

enum PhaseTilingFixtures {

    // The spec's model: side 8 tiled by 2³.
    static let specSide = 8
    static let specTile = 2
    /// specTile · replication == ANELoop.blockSide — the fixture's
    /// whole reason for existing, stated as an identity rather than
    /// as a literal 2.
    static let replication = ANELoop.blockSide / specTile

    /// The spec's LCG, verbatim (Haskell Int is 64-bit; 1103515245 ·
    /// s stays well inside Int64 for s < 2³¹, so &* cannot wrap).
    static func lcg(_ s: Int) -> Int { (1103515245 &* s &+ 12345) % 2147483648 }

    /// The spec's palette: 128 figure primaries and their σ mirrors.
    static let palette: [OKLabColor] = {
        var figs: [OKLabColor] = []
        figs.reserveCapacity(DyadPalette.primaryCount)
        for i in 0..<DyadPalette.primaryCount {
            figs.append(OKLabColor(
                l: Double(lcg(i * 7 + 1) % 900 + 50) / 1000,
                a: Double(lcg(i * 13 + 2) % 400 - 200) / 1000,
                b: Double(lcg(i * 29 + 5) % 400 - 200) / 1000))
        }
        return figs + figs.reversed().map(DyadPalette.comp)
    }()

    static func specIdx(_ t: Int, _ y: Int, _ x: Int) -> Int {
        (t * specSide + y) * specSide + x
    }

    /// The spec's cube: a figure region, a ground region, a boundary.
    static let specIndices: [Int] = {
        var c = [Int](repeating: 0, count: specSide * specSide * specSide)
        for t in 0..<specSide {
            for y in 0..<specSide {
                for x in 0..<specSide {
                    let i = specIdx(t, y, x)
                    let inFigure = (y - 4) * (y - 4) + (x - 4) * (x - 4) <= 4 + t % 2
                    c[i] = inFigure
                        ? lcg(i * 3 + 1) % DyadPalette.primaryCount
                        : 255 - (lcg(i * 5 + 2) % 16)
                }
            }
        }
        return c
    }()

    /// The spec's 8³ colour field. The spec's `idx (t,y,x)` and the
    /// house layout x + side·(y + side·f) are the same ordering.
    static let specField: [OKLabColor] =
        specIndices.map { palette[$0 % PhaseTiling.entryCount] }

    /// The spec's own 2³-tile phases, computed independently of
    /// PhaseTiling — the reference the port must reproduce.
    static let specPhases: [PhaseTiling.Phase] = {
        var out: [PhaseTiling.Phase] = []
        let n = specSide / specTile
        for tb in 0..<n {
            for yb in 0..<n {
                for xb in 0..<n {
                    var ground = 0
                    for dt in 0..<specTile {
                        for dy in 0..<specTile {
                            for dx in 0..<specTile {
                                let i = specIndices[specIdx(tb * specTile + dt,
                                                            yb * specTile + dy,
                                                            xb * specTile + dx)]
                                if i >= DyadPalette.primaryCount { ground += 1 }
                            }
                        }
                    }
                    out.append(PhaseTiling.phase(
                        groundCount: ground,
                        voxelCount: specTile * specTile * specTile))
                }
            }
        }
        return out
    }()

    /// THE MODEL CUBE: the spec's 8³ replicated ×2 to 16³, so a 4³
    /// port tile is exactly a 2³ spec tile (see the header note).
    /// Every frame carries the SAME table — the spec's single-palette
    /// case, which is C4's degenerate case.
    static let model: PhaseTiling.Cube = {
        let side = specSide * replication
        let frames = specSide * replication
        var idx = [[UInt8]](repeating: [UInt8](repeating: 0, count: side * side),
                            count: frames)
        for t in 0..<frames {
            for y in 0..<side {
                for x in 0..<side {
                    idx[t][x + side * y] = UInt8(specIndices[
                        specIdx(t / replication, y / replication, x / replication)])
                }
            }
        }
        return PhaseTiling.Cube(
            side: side, frameCount: frames, indices: idx,
            tableLabs: [[OKLabColor]](repeating: palette, count: frames))
    }()

    /// THE SHIPPING SHAPE: 64 frames of 64², 4096 tiles, built
    /// through the Data/LCT initializer with a DIFFERENT table per
    /// frame — the per-frame-palette extension (C4) under test.
    static let synthetic64: PhaseTiling.Cube? = {
        let side = 64, frames = 64
        var tables: [Data] = []
        for f in 0..<frames {
            var bytes = [UInt8]()
            bytes.reserveCapacity(PhaseTiling.tableBytes)
            for i in 0..<PhaseTiling.entryCount {
                let s = (f + 1) * 31 + i * 7
                bytes.append(UInt8(lcg(s * 3 + 1) % 256))
                bytes.append(UInt8(lcg(s * 5 + 2) % 256))
                bytes.append(UInt8(lcg(s * 11 + 3) % 256))
            }
            tables.append(Data(bytes))
        }
        var idx = [[UInt8]](repeating: [UInt8](repeating: 0, count: side * side),
                            count: frames)
        let c = side / 2
        for t in 0..<frames {
            for y in 0..<side {
                for x in 0..<side {
                    let i = (t * side + y) * side + x
                    // The spec's sphere-in-ground, scaled to 64².
                    let inFigure = (y - c) * (y - c) + (x - c) * (x - c)
                        <= 256 + 64 * (t % 2)
                    idx[t][x + side * y] = UInt8(inFigure
                        ? lcg(i * 3 + 1) % DyadPalette.primaryCount
                        : 255 - (lcg(i * 5 + 2) % 16))
                }
            }
        }
        return PhaseTiling.Cube(indexFrames: idx, tables: tables)
    }()

    // MARK: Helpers

    /// The spec's single-palette flat energy, transcribed here so the
    /// port is checked against an INDEPENDENT traversal (C4's pin).
    static func singlePaletteEnergy(_ cube: PhaseTiling.Cube,
                                    palette pal: [OKLabColor]) -> Double {
        let s = cube.side, f = cube.frameCount
        func colour(_ t: Int, _ p: Int) -> OKLabColor {
            pal[Int(cube.indices[t][p]) % PhaseTiling.entryCount]
        }
        var e = 0.0
        for t in 0..<f {
            for y in 0..<s {
                for x in 0..<s {
                    let p = x + s * y
                    let c = colour(t, p)
                    if t + 1 < f { e += DyadPalette.dLab2(c, colour(t + 1, p)) }
                    if y + 1 < s { e += DyadPalette.dLab2(c, colour(t, p + s)) }
                    if x + 1 < s { e += DyadPalette.dLab2(c, colour(t, p + 1)) }
                }
            }
        }
        return e
    }

    /// DyadEnergy's σ-spin domain walls (PE4's Ising form) restricted
    /// to one tile's interior bonds — the SHIPPING index-domain meter,
    /// reproduced here only so PD2 can refute it (C1). This lives in
    /// the test file on purpose: nothing in PhaseTiling.swift may
    /// depend on it.
    static func spinWalls(_ cube: PhaseTiling.Cube, tile ti: Int) -> Int {
        let b = ANELoop.blockSide, s = cube.side
        let (bx, by, bt) = PhaseTiling.origin(cube, tile: ti)
        func ground(_ f: Int, _ p: Int) -> Bool {
            cube.indices[f][p] >= UInt8(DyadPalette.primaryCount)
        }
        var n = 0
        for lt in 0..<b {
            for ly in 0..<b {
                for lx in 0..<b {
                    let f = bt * b + lt
                    let p = (by * b + ly) * s + (bx * b + lx)
                    let g = ground(f, p)
                    if lt + 1 < b, g != ground(f + 1, p) { n += 1 }
                    if ly + 1 < b, g != ground(f, p + s) { n += 1 }
                    if lx + 1 < b, g != ground(f, p + 1) { n += 1 }
                }
            }
        }
        return n
    }

    /// Descending order by value; ties → lowest tile index. Total and
    /// deterministic, so a ranking difference is a real difference.
    static func ranking<T: Comparable>(_ n: Int, by value: (Int) -> T) -> [Int] {
        (0..<n).sorted { a, b in
            let va = value(a), vb = value(b)
            return va == vb ? a < b : va > vb
        }
    }

    /// σ(i) = 255 − i: the DYAD involution itself.
    static let sigmaPermutation: [Int] =
        (0..<PhaseTiling.entryCount).map { DyadPalette.partner($0) }

    /// A shuffle from the house LCG (no randomness in tests).
    static func lcgPermutation(seed: Int) -> [Int] {
        var p = Array(0..<PhaseTiling.entryCount)
        var s = seed
        for i in stride(from: p.count - 1, to: 0, by: -1) {
            s = lcg(s)
            p.swapAt(i, s % (i + 1))
        }
        return p
    }

    /// A permutation that PRESERVES the dyad pairing: it rotates the
    /// figure half and carries the ground half by σ, so π(255 − i) =
    /// 255 − π(i) for every i.
    static let pairingPermutation: [Int] = {
        var p = [Int](repeating: 0, count: PhaseTiling.entryCount)
        for i in 0..<DyadPalette.primaryCount {
            let j = (i + 8) % DyadPalette.primaryCount
            p[i] = j
            p[DyadPalette.partner(i)] = DyadPalette.partner(j)
        }
        return p
    }()

    /// indices' = π(indices), tableLabs' = tableLabs ∘ π⁻¹ — the same
    /// colours on the same cells, under different labels.
    static func relabel(_ cube: PhaseTiling.Cube, by pi: [Int]) -> PhaseTiling.Cube {
        var idx = cube.indices
        for f in 0..<cube.frameCount {
            for p in 0..<idx[f].count { idx[f][p] = UInt8(pi[Int(idx[f][p])]) }
        }
        var tabs = cube.tableLabs
        for f in 0..<cube.frameCount {
            var t = tabs[f]
            for i in 0..<PhaseTiling.entryCount { t[pi[i]] = cube.tableLabs[f][i] }
            tabs[f] = t
        }
        return PhaseTiling.Cube(side: cube.side, frameCount: cube.frameCount,
                                indices: idx, tableLabs: tabs)
    }

    /// Apply a colour map to every frame's table — the gauge action.
    static func mapTables(_ cube: PhaseTiling.Cube,
                          _ g: (OKLabColor) -> OKLabColor) -> PhaseTiling.Cube {
        PhaseTiling.Cube(side: cube.side, frameCount: cube.frameCount,
                         indices: cube.indices,
                         tableLabs: cube.tableLabs.map { $0.map(g) })
    }
}

// MARK: - The gate

final class PhaseTilingTests: XCTestCase {

    // MARK: PD1 — the bond cost is a squared Euclidean metric

    func testBondCostIsAMetricSquared() {
        // ALL EXACT, no accuracy. dLab2 is dl²+da²+db²: swapping the
        // arguments negates each difference, and negation and squaring
        // are exact in IEEE-754, so symmetry is bit-identical. The sum
        // of three squares is 0 iff each square is 0, and a square is
        // 0 iff its difference is 0 — no tolerance is meaningful here.
        // (The one theoretical escape, a difference so small its square
        // underflows to zero, needs |Δ| < ~1.5e-162; OKLab coordinates
        // of distinct table entries are ~1e-3 apart.)
        let sample = Array(PhaseTilingFixtures.palette.prefix(12))
        for p in sample {
            XCTAssertEqual(DyadPalette.dLab2(p, p), 0)
            for q in sample {
                XCTAssertEqual(DyadPalette.dLab2(p, q), DyadPalette.dLab2(q, p))
                XCTAssertGreaterThanOrEqual(DyadPalette.dLab2(p, q), 0)
                XCTAssertEqual(DyadPalette.dLab2(p, q) == 0, p == q)
            }
        }
        XCTAssertGreaterThan(PhaseTiling.energy(PhaseTilingFixtures.model), 0)
    }

    // MARK: PD2 ★ — OKLab and the colourblind forms rank tiles differently

    func testOKLabAndIndexCountRankTilesDifferently() {
        let cube = PhaseTilingFixtures.model
        let n = cube.tileCount

        let rankLab = PhaseTilingFixtures.ranking(n) {
            PhaseTiling.tileEnergy(cube, tile: $0)
        }
        let rankIdx = PhaseTilingFixtures.ranking(n) {
            PhaseTiling.indexWalls(cube, tile: $0)
        }
        // ★ The second ranking that matters: the SHIPPING meter's
        // space (DyadEnergy's σ-spin domain walls, PE4). C1 — the
        // index-domain meter is a different answer, not a coarse
        // version of this one.
        let rankSpin = PhaseTilingFixtures.ranking(n) {
            PhaseTilingFixtures.spinWalls(cube, tile: $0)
        }

        // Rank disagreement is an INTEGER conclusion: exact.
        XCTAssertNotEqual(rankLab, rankIdx)
        XCTAssertNotEqual(rankLab, rankSpin)

        // A concrete inversion: a pair the two orders disagree about.
        var inverted = false
        outer: for i in 0..<n {
            for j in 0..<n
            where PhaseTiling.tileEnergy(cube, tile: i)
                > PhaseTiling.tileEnergy(cube, tile: j)
               && PhaseTiling.indexWalls(cube, tile: i)
                < PhaseTiling.indexWalls(cube, tile: j) {
                inverted = true
                break outer
            }
        }
        XCTAssertTrue(inverted, "PD2 needs a tile pair the two energies order differently")

        // The spec's third clause: the values themselves differ.
        let interior = (0..<n).reduce(0.0) { $0 + PhaseTiling.tileEnergy(cube, tile: $1) }
        let indexTotal = (0..<n).reduce(0) { $0 + PhaseTiling.indexWalls(cube, tile: $1) }
        XCTAssertNotEqual(interior, Double(indexTotal))
        XCTAssertTrue((0..<n).contains {
            PhaseTiling.tileEnergy(cube, tile: $0)
                != Double(PhaseTiling.indexWalls(cube, tile: $0))
        })
    }

    // MARK: PD3 — additivity (structural in Tiling.total; tested here)

    func testAdditivity() throws {
        // The closed-form bond counts at the shipping shape. INTEGERS:
        // exact, and they are the contract's derived numbers.
        XCTAssertEqual(PhaseTiling.bondCount(side: 64, frameCount: 64), 774144)
        XCTAssertEqual(PhaseTiling.interiorBondCount(side: 64, frameCount: 64), 589824)
        XCTAssertEqual(PhaseTiling.bondCount(side: 64, frameCount: 64)
                     - PhaseTiling.interiorBondCount(side: 64, frameCount: 64), 184320)

        for cube in [PhaseTilingFixtures.model,
                     try XCTUnwrap(PhaseTilingFixtures.synthetic64)] {
            let t = PhaseTiling.tile(cube)
            // Exact: the bond sets partition the bond set.
            XCTAssertEqual(t.interiorBondCount + t.wallBondCount, t.bondCount)
            XCTAssertEqual(t.bondCount,
                           PhaseTiling.bondCount(side: cube.side,
                                                 frameCount: cube.frameCount))
            // The spec is exact over ℚ; here the flat traversal and the
            // tile-by-tile traversal sum the same terms in a DIFFERENT
            // ORDER, so the difference is pure round-off. Tolerance is
            // Higham's bound for a bondCount-term non-negative sum.
            XCTAssertEqual(PhaseTiling.energy(cube), t.total,
                           accuracy: PhaseTiling.summationSlack(t.total,
                                                                terms: t.bondCount))
        }

        // Disjointness, exact, on the cheap fixture: every bond is
        // interior XOR wall, and together they are every bond.
        let cube = PhaseTilingFixtures.model
        let s = cube.side, f = cube.frameCount, b = ANELoop.blockSide
        var interiorBonds = Set<Int>(), wallBonds = Set<Int>()
        for t in 0..<f {
            for y in 0..<s {
                for x in 0..<s {
                    let cell = x + s * (y + s * t)
                    func note(_ axis: Int, _ crosses: Bool) {
                        let id = cell * 3 + axis
                        if crosses { wallBonds.insert(id) } else { interiorBonds.insert(id) }
                    }
                    if t + 1 < f { note(0, (t + 1) % b == 0) }
                    if y + 1 < s { note(1, (y + 1) % b == 0) }
                    if x + 1 < s { note(2, (x + 1) % b == 0) }
                }
            }
        }
        XCTAssertTrue(interiorBonds.isDisjoint(with: wallBonds))
        let tiling = PhaseTiling.tile(cube)
        XCTAssertEqual(interiorBonds.count, tiling.interiorBondCount)
        XCTAssertEqual(wallBonds.count, tiling.wallBondCount)
        XCTAssertEqual(interiorBonds.count + wallBonds.count, tiling.bondCount)
    }

    // MARK: PD4 ★ — gauge invariance

    func testRelabellingPaletteIsFree() {
        // Daniel's framing: relabelling the palette is FREE. STRICT
        // EQUALITY, no accuracy — π only renames table slots, so every
        // cell resolves to the identical Double triple, every bond
        // produces the identical term, and the summation order is
        // unchanged. Anything but bit-identity is a bug, not round-off.
        let cube = PhaseTilingFixtures.model
        let base = PhaseTiling.tile(cube)
        for pi in [PhaseTilingFixtures.sigmaPermutation,
                   PhaseTilingFixtures.lcgPermutation(seed: 20260813),
                   PhaseTilingFixtures.pairingPermutation] {
            XCTAssertEqual(Set(pi).count, PhaseTiling.entryCount, "π must be a bijection")
            let relabelled = PhaseTiling.tile(PhaseTilingFixtures.relabel(cube, by: pi))
            XCTAssertEqual(relabelled.total, base.total)
            XCTAssertEqual(relabelled.interior, base.interior)
            XCTAssertEqual(relabelled.walls, base.walls)
            for i in 0..<base.tiles.count {
                XCTAssertEqual(relabelled.tiles[i].interior, base.tiles[i].interior)
            }
        }
    }

    func testIsometryInvariance() {
        let cube = PhaseTilingFixtures.model
        let base = PhaseTiling.energy(cube)
        let slack = PhaseTiling.summationSlack(
            base, terms: PhaseTiling.bondCount(side: cube.side,
                                               frameCount: cube.frameCount))

        // (a) NEGATION of the opponent axes — EXACT. Sign flips are
        // exact in binary floating point, each difference is negated,
        // each square is unchanged bit-for-bit, and the three-term sum
        // is added in the same order.
        let negated = PhaseTilingFixtures.mapTables(cube) {
            OKLabColor(l: $0.l, a: -$0.a, b: -$0.b)
        }
        XCTAssertEqual(PhaseTiling.energy(negated), base)

        // (b) The (a,b) SWAP — the spec's 90° flip. The three squared
        // terms are bit-identical (a swap moves values, it does not
        // compute), but the sum reassociates from (dl²+da²)+db² to
        // (dl²+db²)+da², and IEEE-754 addition is commutative yet NOT
        // associative. So this is asserted within the derived slack,
        // not bit-for-bit — the spec's exactness over ℚ does not
        // survive the reassociation, and pretending otherwise would be
        // a guessed claim.
        let swapped = PhaseTilingFixtures.mapTables(cube) {
            OKLabColor(l: $0.l, a: $0.b, b: $0.a)
        }
        XCTAssertEqual(PhaseTiling.energy(swapped), base, accuracy: slack)

        // (c) A rigid L-SHIFT. (l + c) − (l' + c) ≠ l − l' in general
        // — the shift is a rounded addition — so slack, not equality.
        let shifted = PhaseTilingFixtures.mapTables(cube) {
            OKLabColor(l: $0.l + 0.3, a: $0.a, b: $0.b)
        }
        XCTAssertEqual(PhaseTiling.energy(shifted), base, accuracy: slack)

        // (d) A genuine rotation of the (a,b) plane by 1 rad — an
        // isometry with irrational entries, so slack.
        let (c1, s1) = (cos(1.0), sin(1.0))
        let rotated = PhaseTilingFixtures.mapTables(cube) {
            OKLabColor(l: $0.l, a: c1 * $0.a - s1 * $0.b, b: s1 * $0.a + c1 * $0.b)
        }
        XCTAssertEqual(PhaseTiling.energy(rotated), base, accuracy: slack)
    }

    // MARK: PD5 — σ-invariance

    func testSigmaInvariance() {
        // EXACT: comp negates a and b, and negation is exact — the
        // same argument as PD4(a).
        let cube = PhaseTilingFixtures.model
        let complemented = PhaseTilingFixtures.mapTables(cube, DyadPalette.comp)
        XCTAssertEqual(PhaseTiling.energy(complemented), PhaseTiling.energy(cube))

        // comp ∘ comp = id, exactly, on 16 entries (the spec's sample).
        for p in PhaseTilingFixtures.palette.prefix(16) {
            XCTAssertEqual(DyadPalette.comp(DyadPalette.comp(p)), p)
        }
    }

    // MARK: PD6 — κ contracts

    func testCoarserRungsAreCalmerPerBond() throws {
        // HONESTY: PD6 is a MEASURED property of real colour fields,
        // not a universal theorem about mean pooling (a field can be
        // built whose pool is rougher per bond). This test asserts the
        // same chain the spec asserts, at the same scope — the spec's
        // own 8³ model field, and the shipping 64³ shape. It is never
        // asserted at runtime anywhere in the app.
        //
        // The ×2-replicated model CUBE is deliberately not used here:
        // its first pool undoes the replication and recovers the spec's
        // 8³ field, so the density RISES on that step. That is an
        // artifact of the fixture, not of κ — so the spec's field is
        // fed directly, and it reproduces the spec's own chain
        // (rung 8³ → 4³ → 2³).
        var field = PhaseTilingFixtures.specField
        var side = PhaseTilingFixtures.specSide
        var frames = PhaseTilingFixtures.specSide
        for _ in 0..<2 {
            let fine = PhaseTiling.energyDensity(field, side: side, frameCount: frames)
            let pooled = try XCTUnwrap(
                PhaseTiling.poolLab(field, side: side, frameCount: frames))
            let coarse = PhaseTiling.energyDensity(pooled.field,
                                                   side: pooled.side,
                                                   frameCount: pooled.frameCount)
            XCTAssertGreaterThan(fine, coarse)
            (field, side, frames) = (pooled.field, pooled.side, pooled.frameCount)
        }

        let cube = try XCTUnwrap(PhaseTilingFixtures.synthetic64)
        var f64 = PhaseTiling.field(cube)
        var s64 = cube.side
        var n64 = cube.frameCount
        for _ in 0..<2 {
            let fine = PhaseTiling.energyDensity(f64, side: s64, frameCount: n64)
            let pooled = try XCTUnwrap(
                PhaseTiling.poolLab(f64, side: s64, frameCount: n64))
            let coarse = PhaseTiling.energyDensity(pooled.field,
                                                   side: pooled.side,
                                                   frameCount: pooled.frameCount)
            XCTAssertGreaterThan(fine, coarse)
            (f64, s64, n64) = (pooled.field, pooled.side, pooled.frameCount)
        }

        // The pool refuses a side it cannot halve. ⚠ It must be handed
        // a CORRECTLY SIZED odd-sided field: passing `side: s64 + 1`
        // with the old cell count trips the count guard first, so the
        // nil proves nothing about parity and the assertion would
        // still pass with the parity clause deleted.
        let oddSide = s64 + 1                       // odd, unhalvable
        XCTAssertEqual(oddSide % 2, 1, "the fixture must actually be odd-sided")
        XCTAssertEqual(n64 % 2, 0,
                       "frameCount must stay halvable, or the nil is the "
                       + "time clause and says nothing about the side")
        let oddField = [OKLabColor](repeating: OKLabColor(l: 0.5, a: 0, b: 0),
                                    count: oddSide * oddSide * n64)
        XCTAssertNil(PhaseTiling.poolLab(oddField, side: oddSide, frameCount: n64),
                     "an odd side cannot be halved")
    }

    // MARK: PD7 — the phase is a total function of φ alone

    func testPhaseIsTotalInPhi() {
        // Exhaustiveness and mutual exclusivity are STRUCTURAL: the
        // enum has exactly three cases, so a tile with no phase or two
        // phases is unrepresentable. What is left to test is that the
        // classifier reads φ and nothing else.
        XCTAssertEqual(PhaseTiling.Phase.allCases.count, 3)
        XCTAssertEqual(PhaseTiling.Phase.allCases,
                       [.face, .band, .solid])          // the spec's derived Ord
        XCTAssertTrue(PhaseTiling.Phase.face < PhaseTiling.Phase.band)
        XCTAssertTrue(PhaseTiling.Phase.band < PhaseTiling.Phase.solid)

        let tiling = PhaseTiling.tile(PhaseTilingFixtures.model)
        for t in tiling.tiles {
            XCTAssertEqual(t.phase == .face, t.groundCount == 0)
            XCTAssertEqual(t.phase == .solid, t.groundCount == t.voxelCount)
            XCTAssertEqual(t.phase == .band,
                           t.groundCount > 0 && t.groundCount < t.voxelCount)
            // m_st and s are MEASURED AND REPORTED — never axes. They
            // are computed for every tile and constrain nothing.
            XCTAssertGreaterThanOrEqual(t.mSt, 0)
            XCTAssertLessThanOrEqual(t.mSt, 1)
            XCTAssertGreaterThan(t.sDiv, 0)
            XCTAssertLessThanOrEqual(t.sDiv, 1)
            XCTAssertEqual(t.phi, Double(t.groundCount) / Double(t.voxelCount))
        }
    }

    // MARK: PD8 — the tiling is total

    func testTilingIsTotal() throws {
        // Structural half: Cube.init? rejects any cube the 4³
        // decomposition cannot partition, so an unpartitionable cube
        // does not exist to be tested. Pin the rejections.
        let table = Data([UInt8](repeating: 0, count: PhaseTiling.tableBytes))
        let odd = [[UInt8]](repeating: [UInt8](repeating: 0, count: 6 * 6), count: 4)
        XCTAssertNil(PhaseTiling.Cube(indexFrames: odd,
                                      tables: [Data](repeating: table, count: 4)))
        let shortRun = [[UInt8]](repeating: [UInt8](repeating: 0, count: 8 * 8), count: 3)
        XCTAssertNil(PhaseTiling.Cube(indexFrames: shortRun,
                                      tables: [Data](repeating: table, count: 3)))
        let badTable = Data([UInt8](repeating: 0, count: PhaseTiling.tableBytes - 1))
        XCTAssertNil(PhaseTiling.Cube(
            indexFrames: [[UInt8]](repeating: [UInt8](repeating: 0, count: 8 * 8), count: 4),
            tables: [Data](repeating: badTable, count: 4)))

        for cube in [PhaseTilingFixtures.model,
                     try XCTUnwrap(PhaseTilingFixtures.synthetic64)] {
            let tiling = PhaseTiling.tile(cube)
            XCTAssertEqual(tiling.tiles.count, cube.tileCount)
            XCTAssertEqual(cube.tileCount,
                           cube.tilesPerAxis * cube.tilesPerAxis * cube.tileFrames)
            // Tile addresses are exactly 0..<tileCount, no repeats.
            XCTAssertEqual(tiling.tiles.map(\.index), Array(0..<cube.tileCount))
            // Every cell visited exactly once, every tile full.
            var visits = [Int](repeating: 0,
                               count: cube.side * cube.side * cube.frameCount)
            for ti in 0..<cube.tileCount {
                XCTAssertEqual(tiling.tiles[ti].voxelCount, ANELoop.blockVoxels)
                for v in 0..<ANELoop.blockVoxels {
                    let (f, p) = PhaseTiling.address(cube, tile: ti, voxel: v)
                    visits[p + cube.side * cube.side * f] += 1
                }
            }
            XCTAssertTrue(visits.allSatisfy { $0 == 1 })
            XCTAssertEqual(tiling.faceCount + tiling.bandCount + tiling.solidCount,
                           tiling.tiles.count)
        }
    }

    // MARK: PD9 ★ — incrementality

    func testEditingOneTileTouchesOnlyItsOwnTerms() {
        let old = PhaseTilingFixtures.model
        // The spec's target tile (1, 1, 1), through the port's own
        // address arithmetic — bi = bx + sb·(by + sb·bt).
        let sb = old.tilesPerAxis
        let ti = 1 + sb * (1 + sb * 1)
        let edited = (0..<ANELoop.blockVoxels).map { v -> UInt8 in
            let (f, p) = PhaseTiling.address(old, tile: ti, voxel: v)
            // The spec's edit: (i + 7) mod 128.
            return UInt8((Int(old.indices[f][p]) + 7) % DyadPalette.primaryCount)
        }
        let new = PhaseTiling.edit(old, tile: ti, indices: edited)

        let before = PhaseTiling.tile(old)
        let after = PhaseTiling.tile(new)

        // (a) EXACT: every other tile is carried, not recomputed —
        // identical cells through identical code in identical order.
        for i in 0..<before.tiles.count where i != ti {
            XCTAssertEqual(after.tiles[i], before.tiles[i])
        }
        // (b) the target really moved.
        XCTAssertNotEqual(after.tiles[ti].interior, before.tiles[ti].interior)

        // (c) Δtotal = Δinterior + Δwalls. The deltas are differences
        // of large sums, so the tolerance is the slack on the TOTAL,
        // not on the (tiny) delta.
        let slack = PhaseTiling.summationSlack(max(before.total, after.total),
                                               terms: before.bondCount)
        let dTotal = after.total - before.total
        let dInterior = after.tiles[ti].interior - before.tiles[ti].interior
        let dWalls = after.walls - before.walls
        XCTAssertEqual(dTotal, dInterior + dWalls, accuracy: slack)

        // (d) the O(blockVoxels) update agrees with the full re-solve.
        let incremental = PhaseTiling.update(before, from: old, to: new, tile: ti)
        XCTAssertEqual(incremental.interior, after.interior, accuracy: slack)
        XCTAssertEqual(incremental.walls, after.walls, accuracy: slack)
        XCTAssertEqual(incremental.total, after.total, accuracy: slack)
        // Integers: exact.
        XCTAssertEqual(incremental.faceCount, after.faceCount)
        XCTAssertEqual(incremental.bandCount, after.bandCount)
        XCTAssertEqual(incremental.solidCount, after.solidCount)
        XCTAssertEqual(incremental.bondCount, after.bondCount)
        XCTAssertEqual(incremental.interiorBondCount, after.interiorBondCount)
        XCTAssertEqual(incremental.wallBondCount, after.wallBondCount)
        for i in 0..<after.tiles.count {
            XCTAssertEqual(incremental.tiles[i].groundCount, after.tiles[i].groundCount)
            XCTAssertEqual(incremental.tiles[i].distinctCount, after.tiles[i].distinctCount)
            XCTAssertEqual(incremental.tiles[i].staggered, after.tiles[i].staggered)
            XCTAssertEqual(incremental.tiles[i].phase, after.tiles[i].phase)
        }
    }

    // MARK: PD10 ★ — the boundary is thin

    func testBoundaryIsThin() throws {
        // HONESTY: `2·band < tiles` is a property of THIS capture
        // geometry, not a law of all captures — a face filling the
        // frame can violate it. It is REPORTED, never enforced: there
        // is no precondition, assert, or guard on it anywhere in
        // shipping code, and this assertion is fixture-scoped exactly
        // as the spec's is.
        let tiling = PhaseTiling.tile(PhaseTilingFixtures.model)
        XCTAssertGreaterThan(tiling.bandCount, 0)
        XCTAssertLessThan(tiling.bandCount, tiling.tiles.count)
        XCTAssertGreaterThan(tiling.faceCount, 0)
        XCTAssertGreaterThan(tiling.solidCount, 0)
        XCTAssertEqual(tiling.faceCount + tiling.bandCount + tiling.solidCount,
                       tiling.tiles.count)
        XCTAssertLessThan(2 * tiling.bandCount, tiling.tiles.count)
        for t in tiling.tiles where t.phase == .band {
            XCTAssertGreaterThan(t.groundCount, 0)
            XCTAssertLessThan(t.groundCount, t.voxelCount)
        }

        // The spec's exact counts at its 8³/2³ model, reproduced by the
        // ×2 replication (see the header note). INTEGERS: bit-for-bit
        // against the Haskell run.
        XCTAssertEqual(tiling.tiles.count, 64)
        XCTAssertEqual(tiling.faceCount, 4)
        XCTAssertEqual(tiling.bandCount, 28)
        XCTAssertEqual(tiling.solidCount, 32)

        // The shipping shape also has all three phases and a thin band.
        let big = PhaseTiling.tile(try XCTUnwrap(PhaseTilingFixtures.synthetic64))
        XCTAssertEqual(big.tiles.count, 4096)
        XCTAssertGreaterThan(big.faceCount, 0)
        XCTAssertGreaterThan(big.bandCount, 0)
        XCTAssertGreaterThan(big.solidCount, 0)
        XCTAssertLessThan(2 * big.bandCount, big.tiles.count)
    }

    // MARK: The reuse guarantee — a tile IS an ANELoop block

    func testTileAddressingMatchesANELoopBlocks() throws {
        let cube = try XCTUnwrap(PhaseTilingFixtures.synthetic64)
        let side = cube.side, b = ANELoop.blockSide
        let sb = side / b
        for bi in 0..<cube.tileCount {
            // ANELoop's inline formula, transcribed (ANELoop.swift's
            // refineFarBlocks) — not called through PhaseTiling.
            let bx = bi % sb, by = (bi / sb) % sb, bt = bi / (sb * sb)
            for v in 0..<ANELoop.blockVoxels {
                let (lx, ly, lt) = ANELoop.localXYT(v)
                let f = bt * b + lt
                let p = (by * b + ly) * side + (bx * b + lx)
                let addr = PhaseTiling.address(cube, tile: bi, voxel: v)
                XCTAssertEqual(addr.frame, f)
                XCTAssertEqual(addr.pixel, p)
            }
            let o = PhaseTiling.origin(cube, tile: bi)
            XCTAssertEqual([o.bx, o.by, o.bt], [bx, by, bt])
        }
    }

    // MARK: C4 — the per-frame-table extension is sound

    func testIdenticalTablesReproduceTheSpec() {
        // The house pattern (DyadPalette's weighted stats): the
        // extension must reproduce the spec's degenerate case exactly.
        // Give every frame the same table and the cube collapses to the
        // spec's single global `colourOf`.
        let cube = PhaseTilingFixtures.model
        XCTAssertTrue(cube.tableLabs.allSatisfy { $0 == cube.tableLabs[0] })

        let independent = PhaseTilingFixtures.singlePaletteEnergy(
            cube, palette: PhaseTilingFixtures.palette)
        // Same terms, same traversal order, values looked up through a
        // single palette instead of per-frame tables — identical
        // Doubles, so EXACT.
        XCTAssertEqual(PhaseTiling.energy(cube), independent)

        // And the phases are the spec's own, tile for tile: the ×2
        // replication preserves φ exactly, so this is an INTEGER
        // identity against an independently computed reference.
        let tiling = PhaseTiling.tile(cube)
        XCTAssertEqual(tiling.tiles.map(\.phase), PhaseTilingFixtures.specPhases)

        // The trace exists and carries the decomposition (STEP 1: it is
        // wired to nothing — no GIF comment byte depends on it).
        let line = PhaseTiling.trace(tiling, density: [0.1, 0.01, 0.001])
        XCTAssertTrue(line.hasPrefix("PHASE TILING v1 "))
        XCTAssertTrue(line.contains("face=4"))
        XCTAssertTrue(line.contains("band=28"))
        XCTAssertTrue(line.contains("solid=32"))
    }
}
