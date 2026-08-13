// PhaseTiling.swift
// Tesseract
//
// Swift port of spec/statistics/PhaseTiling.hs — the Haskell spec is
// authoritative (axioms PD1–PD10). The 64³ export cube tiled by 4³
// phase blocks, with the bond energy computed in OKLab:
//
//     E = Σ over adjacent cells ‖c_p − c_q‖²
//
// Daniel (2026-08-13): "I need tight phase diagram energy
// computation so that I can tile the 64³ … please do the energy
// calculation in the correct color space!"
//
// WHY THE SPACE IS THE WHOLE POINT (PD1, PD2). A domain-wall COUNT
// is colourblind: it cannot tell a wall between two near-identical
// greens from a wall between black and white, both cost 1. In OKLab
// the metric is Euclidean AND perceptual, so a bond costs ΔE_OK² —
// what the wall LOOKS like it costs. PD2 exhibits a configuration
// where the two energies RANK TILES DIFFERENTLY, so the colourblind
// form is a different answer, not a cheap approximation.
//
// TIGHT means additive (PD3: E = Σ tile interiors + walls, exactly)
// and incremental (PD9: re-solving ONE tile changes only that tile's
// interior and its own walls). Together those license a full 4096-
// tile re-solve as 4096 independent recomputations.
//
// THE TILING IS THE BOUNDARY (PD7, PD8): φ = 0 → FACE (all figure,
// deep palette), φ = 1 → SOLID (all ground, shallow palette),
// otherwise BAND — the boundary, where both depths live and where
// the rate goes (PD10). m_st (the staggered magnetisation, the Néel
// detector for the Bayer band) and s (index diversity) are MEASURED
// and reported per tile — never used as axes.
//
// ── STANDING NOTES FOR THE NEXT READER ──────────────────────────
//
// C1  E_dist in DyadEnergy.swift is INDEX-DOMAIN (σ-spin domain
//     walls over `index ≥ 128`, spec/statistics/PhaseEnergy.hs PE4 —
//     the Ising identity). This file is the PERCEPTUAL bond energy,
//     Σ ΔE_OK² over spacetime bonds. Both are authoritative FOR THEIR
//     OWN QUANTITY; PD2 proves they rank tiles differently, so
//     neither approximates the other. DyadEnergy is load-bearing
//     shipping telemetry ("DYAD ENERGY v1") — do not change its
//     numbers or its space. The spec's own refuted colourblind form
//     (full index inequality) is ported below as `indexWalls`, kept
//     ONLY to be refuted by the PD2 test.
//
// C2  THE TIME AXIS IS OPEN. The spec's `bonds`/`bondsAt` use
//     `inside`, not a wrap: frame 63 and frame 0 share NO bond.
//     Everywhere else in this codebase time is a torus (TL10's exact
//     t-wrap, the loop torus in the chaos-blur laws). Wrapping here
//     would be an implementer's decision, and it is not one —
//     a t-wrap needs a spec change first.
//
// C3  `s` means two different things in the two spec headers.
//     `Tile.sDiv` is the spec's `sDiv`: distinct indices / tile
//     voxels, tile-local, ∈ (0,1]. DyadEnergy's `sOcc` is a
//     normalized Shannon occupancy entropy, frame-global. Never
//     compare or substitute the two.
//
// C4  ONE PALETTE (spec) vs PER-FRAME LCTs (the 2026-08-12 decree).
//     The spec models one global `colourOf`; the shipping export
//     carries one 768-byte Local Color Table per frame. Carried here
//     as a declared EXTENSION (the DyadPalette weighted-stats
//     precedent): the energy is a function of COLOURS, so resolving
//     each cell through its own frame's table leaves PD1–PD10 intact,
//     and with identical tables this reproduces the spec exactly
//     (pinned by testIdenticalTablesReproduceTheSpec).
//
// C6  `poolLab` is NOT TriScaleLadder's pool. RungCube pools exact
//     UInt64 lattice-level SUMS because rounded means do not compose
//     (TL1/TL2) — index domain. PD6 pools OKLab COLOURS with a plain
//     mean, because the spec §4 header says so in as many words:
//     "Pooling is done on COLOURS in OKLab — never on indices, which
//     are labels." Same 2×2×2 atom, different objects; do not
//     deduplicate them. It is also not PhaseTelemetry.bands, which
//     splits an ERROR field into Haar bands (PP1).
//
// ARITHMETIC. The spec is exact over ℚ; this port is Double, so
// every "exactly" in PD3/PD9 becomes "within accumulated round-off".
// The tolerance is DERIVED — `summationSlack` below — never guessed.
//
// MEASUREMENT ONLY (STEP 1). Nothing is wired: no GIF byte, no
// index, no table depends on this file, and it trains nothing
// (★NO-CAPTURE-TRAINING). Appending `trace` to the DYAD comment
// beside "PHASE F v1" is STEP 2 and awaits Daniel's ruling.

import Foundation

enum PhaseTiling {

    // MARK: - § 0. The shape constants (all named, none naked)

    /// The tile IS the ANELoop block: 4³ over 64³ = 4096, the same
    /// decomposition, so a phase label lines up 1:1 with a refinable
    /// block (ANELoop.blockSide / .blockVoxels / .localXYT).

    /// 256 entries = the involution doubling the 128 primaries (DY3).
    static let entryCount = 2 * DyadPalette.primaryCount
    /// A GIF color table is RGB triples — a format fact, not a tuning.
    static let rgbChannels = 3
    /// 768 bytes: the Local Color Table size the export contract pins.
    static let tableBytes = entryCount * rgbChannels

    // MARK: - § 1. Phase (PD7)

    /// The three phases of a tile (PD7). Spec order FACE < BAND <
    /// SOLID (`deriving (Eq, Ord, Enum, Bounded)`), so the raw values
    /// match the spec's `[minBound .. maxBound]`.
    ///
    /// STRUCTURAL DISCHARGE OF PD7's exhaustiveness and mutual
    /// exclusivity: an enum of exactly three cases makes a tile with
    /// no phase, or with two, unrepresentable. The axiom is not
    /// dropped — it is made untestable by construction.
    enum Phase: Int, CaseIterable, Sendable, Comparable {
        case face = 0, band = 1, solid = 2
        static func < (l: Phase, r: Phase) -> Bool { l.rawValue < r.rawValue }
    }

    /// PD7: total and CONSTANT-FREE — the classifier reads only
    /// whether the σ-fraction is 0, 1, or neither. Compared as
    /// INTEGER COUNTS, never as a Double φ: φ is a ratio of counts in
    /// the spec (ℚ), and integer comparison removes every
    /// float-equality hazard. The NO NAKED CONSTANTS decree is
    /// satisfied by the spec itself, not by a comment.
    static func phase(groundCount: Int, voxelCount: Int) -> Phase {
        if groundCount == 0 { return .face }
        if groundCount == voxelCount { return .solid }
        return .band
    }

    // MARK: - § 2. The cube (the carrier)

    /// The index cube plus each frame's own 256-entry table in OKLab.
    /// EXTENSION over the spec (C4): the spec models ONE global
    /// palette; the shipping app carries per-frame LCTs.
    struct Cube: Sendable {
        let side: Int
        let frameCount: Int
        /// frameCount × side² palette indices, pixel p = x + side·y.
        let indices: [[UInt8]]
        /// frameCount × entryCount resolved table colours.
        let tableLabs: [[OKLabColor]]

        /// Fails unless the 4³ decomposition partitions the cube and
        /// every table is a full LCT.
        ///
        /// STRUCTURAL DISCHARGE OF PD8's totality: a cube the tiling
        /// cannot partition cannot be constructed, so no cell can be
        /// orphaned or doubled downstream.
        init?(indexFrames: [[UInt8]], tables: [Data]) {
            let b = ANELoop.blockSide
            guard let first = indexFrames.first,
                  indexFrames.count == tables.count,
                  indexFrames.count % b == 0 else { return nil }
            let area = first.count
            let s = Int(Double(area).squareRoot().rounded())
            guard s > 0, s * s == area, s % b == 0,
                  indexFrames.allSatisfy({ $0.count == area }),
                  tables.allSatisfy({ $0.count == PhaseTiling.tableBytes })
            else { return nil }
            var labs: [[OKLabColor]] = []
            labs.reserveCapacity(tables.count)
            for table in tables {
                let bytes = [UInt8](table)
                labs.append((0..<PhaseTiling.entryCount).map { i in
                    let o = i * PhaseTiling.rgbChannels
                    return DyadPalette.oklab(
                        fromSRGB8: (bytes[o], bytes[o + 1], bytes[o + 2]))
                })
            }
            self.side = s
            self.frameCount = indexFrames.count
            self.indices = indexFrames
            self.tableLabs = labs
        }

        /// Colour-domain constructor: the spec's model cube arrives
        /// as OKLab rationals, not as sRGB8 bytes, so the fixtures
        /// build through here. Also the edit path's rebuild.
        init(side: Int, frameCount: Int,
             indices: [[UInt8]], tableLabs: [[OKLabColor]]) {
            self.side = side
            self.frameCount = frameCount
            self.indices = indices
            self.tableLabs = tableLabs
        }

        /// The cell's colour, resolved through ITS OWN frame's table.
        @inline(__always) func lab(frame f: Int, pixel p: Int) -> OKLabColor {
            tableLabs[f][Int(indices[f][p])]
        }

        var tilesPerAxis: Int { side / ANELoop.blockSide }
        var tileFrames: Int { frameCount / ANELoop.blockSide }
        var tileCount: Int { tilesPerAxis * tilesPerAxis * tileFrames }
    }

    // MARK: - § 3. Tile and Tiling

    struct Tile: Sendable, Equatable {
        /// bi = bx + sb·(by + sb·bt) — ANELoop's block address.
        let index: Int
        let bx: Int, by: Int, bt: Int
        /// = ANELoop.blockVoxels.
        let voxelCount: Int
        /// Voxels with index ≥ DyadPalette.primaryCount (the spec's
        /// `isGround i = i >= 128`).
        let groundCount: Int
        /// Distinct palette indices in the tile.
        let distinctCount: Int
        /// Σ sign(t+y+x)·spin over the tile, SIGNED and exact — the
        /// spec's `mSt` numerator before `abs`.
        let staggered: Int
        /// Σ dE2 over this tile's interior bonds.
        let interior: Double

        /// φ: the σ-side fraction. MEASURED AND REPORTED.
        var phi: Double { Double(groundCount) / Double(voxelCount) }
        /// m_st: the staggered magnetisation, the Néel detector for
        /// the Bayer band. MEASURED AND REPORTED — never an axis.
        var mSt: Double { abs(Double(staggered)) / Double(voxelCount) }
        /// The spec's `sDiv` — index diversity, tile-local. NOT
        /// DyadEnergy's frame-global `sOcc` (C3). Reported only.
        var sDiv: Double { Double(distinctCount) / Double(voxelCount) }
        /// PD7: a total function of φ alone.
        var phase: Phase {
            PhaseTiling.phase(groundCount: groundCount, voxelCount: voxelCount)
        }
    }

    struct Tiling: Sendable, Equatable {
        let tiles: [Tile]
        /// Σ tiles.interior.
        let interior: Double
        /// Σ dE2 over wall bonds.
        let walls: Double
        let faceCount: Int, bandCount: Int, solidCount: Int
        let bondCount: Int, interiorBondCount: Int, wallBondCount: Int

        /// STRUCTURAL DISCHARGE OF PD3: the total is DEFINED as the
        /// decomposition. There is no path in this file that resums
        /// the bonds to produce it, so "E = Σ interiors + walls"
        /// cannot drift. The flat sum is the test, not the source.
        var total: Double { interior + walls }
        var bandFraction: Double { Double(bandCount) / Double(tiles.count) }
    }

    // MARK: - § 4. Bonds

    /// The spacetime bond set is OPEN on all three axes INCLUDING
    /// TIME (C2 — the spec's `inside`, not a wrap; a t-wrap needs a
    /// spec change first, it is not an implementer's call).
    /// Closed form, derived not tuned: at side S over F frames,
    ///   bonds = (F−1)·S² + 2·F·S·(S−1)          (774144 at 64³)
    static func bondCount(side: Int, frameCount: Int) -> Int {
        (frameCount - 1) * side * side + 2 * frameCount * side * (side - 1)
    }

    /// Interior bonds: each of the tileCount blocks is itself an open
    /// b³ lattice, so it carries 3·(b−1)·b² bonds.
    ///   interior = 3·tileCount·(b−1)·b²          (589824 at 64³)
    ///   walls    = bonds − interior              (184320 at 64³)
    static func interiorBondCount(side: Int, frameCount: Int) -> Int {
        let b = ANELoop.blockSide
        let tiles = (side / b) * (side / b) * (frameCount / b)
        return 3 * tiles * (b - 1) * b * b
    }

    // PD1's bond cost is DyadPalette.dLab2 — the spec's `dE2` is
    // already in the codebase, character for character. Every site
    // below calls it directly; adding a forwarding wrapper here would
    // be new surface for nothing.

    /// The flat energy over EVERY bond. PD3's cross-check only —
    /// `tile` never calls it.
    static func energy(_ cube: Cube) -> Double {
        let s = cube.side, f = cube.frameCount
        var e = 0.0
        for t in 0..<f {
            for y in 0..<s {
                for x in 0..<s {
                    let p = x + s * y
                    let c = cube.lab(frame: t, pixel: p)
                    if t + 1 < f {
                        e += DyadPalette.dLab2(c, cube.lab(frame: t + 1, pixel: p))
                    }
                    if y + 1 < s {
                        e += DyadPalette.dLab2(c, cube.lab(frame: t, pixel: p + s))
                    }
                    if x + 1 < s {
                        e += DyadPalette.dLab2(c, cube.lab(frame: t, pixel: p + 1))
                    }
                }
            }
        }
        return e
    }

    /// Σ dE2 over every wall bond. A bond crosses a tile boundary iff
    /// the incremented coordinate lands on a multiple of the block
    /// side — the blocks are aligned, so no membership search is
    /// needed.
    static func wallEnergy(_ cube: Cube) -> Double {
        let s = cube.side, f = cube.frameCount, b = ANELoop.blockSide
        var e = 0.0
        for t in 0..<f {
            for y in 0..<s {
                for x in 0..<s {
                    let p = x + s * y
                    let c = cube.lab(frame: t, pixel: p)
                    if t + 1 < f, (t + 1) % b == 0 {
                        e += DyadPalette.dLab2(c, cube.lab(frame: t + 1, pixel: p))
                    }
                    if y + 1 < s, (y + 1) % b == 0 {
                        e += DyadPalette.dLab2(c, cube.lab(frame: t, pixel: p + s))
                    }
                    if x + 1 < s, (x + 1) % b == 0 {
                        e += DyadPalette.dLab2(c, cube.lab(frame: t, pixel: p + 1))
                    }
                }
            }
        }
        return e
    }

    // MARK: - § 5. Tile addressing (ANELoop's arithmetic, mirrored)

    /// The tile's block coordinates from its address, exactly as
    /// ANELoop decomposes `bi` (ANELoop.swift § refineFarBlocks).
    static func origin(_ cube: Cube, tile ti: Int) -> (bx: Int, by: Int, bt: Int) {
        let sb = cube.tilesPerAxis
        return (ti % sb, (ti / sb) % sb, ti / (sb * sb))
    }

    /// The (frame, pixel) of local voxel v of tile ti. Mirrors
    /// ANELoop's block address arithmetic exactly — `f = bt·4 + lt`,
    /// `p = (by·4 + ly)·side + (bx·4 + lx)`, with the in-tile raster
    /// order taken from ANELoop.localXYT, not re-derived. This is the
    /// reuse guarantee: a BAND label and an ANELoop refinable block
    /// are the same object.
    static func address(_ cube: Cube, tile ti: Int, voxel v: Int)
        -> (frame: Int, pixel: Int)
    {
        let b = ANELoop.blockSide
        let (bx, by, bt) = origin(cube, tile: ti)
        let (lx, ly, lt) = ANELoop.localXYT(v)
        return (bt * b + lt, (by * b + ly) * cube.side + (bx * b + lx))
    }

    /// Σ dE2 over one tile's interior bonds. O(blockVoxels).
    static func tileEnergy(_ cube: Cube, tile ti: Int) -> Double {
        let b = ANELoop.blockSide, s = cube.side
        let (bx, by, bt) = origin(cube, tile: ti)
        var e = 0.0
        for lt in 0..<b {
            for ly in 0..<b {
                for lx in 0..<b {
                    let f = bt * b + lt
                    let p = (by * b + ly) * s + (bx * b + lx)
                    let c = cube.lab(frame: f, pixel: p)
                    if lt + 1 < b {
                        e += DyadPalette.dLab2(c, cube.lab(frame: f + 1, pixel: p))
                    }
                    if ly + 1 < b {
                        e += DyadPalette.dLab2(c, cube.lab(frame: f, pixel: p + s))
                    }
                    if lx + 1 < b {
                        e += DyadPalette.dLab2(c, cube.lab(frame: f, pixel: p + 1))
                    }
                }
            }
        }
        return e
    }

    /// Σ dE2 over wall bonds with AT LEAST ONE endpoint in tile ti —
    /// PD9's "its own walls". Six faces × b² = ≤ 96 bonds, and no
    /// bond is double-counted within a call: a bond with both ends in
    /// ti is interior by definition, and the six faces are disjoint.
    static func wallEnergyAround(_ cube: Cube, tile ti: Int) -> Double {
        let b = ANELoop.blockSide, s = cube.side, fc = cube.frameCount
        let (bx, by, bt) = origin(cube, tile: ti)
        let x0 = bx * b, y0 = by * b, t0 = bt * b
        var e = 0.0
        func bond(_ f0: Int, _ p0: Int, _ f1: Int, _ p1: Int) {
            e += DyadPalette.dLab2(cube.lab(frame: f0, pixel: p0),
                                   cube.lab(frame: f1, pixel: p1))
        }
        // ±t faces.
        for ly in 0..<b {
            for lx in 0..<b {
                let p = (y0 + ly) * s + (x0 + lx)
                if t0 + b < fc { bond(t0 + b - 1, p, t0 + b, p) }
                if t0 > 0 { bond(t0 - 1, p, t0, p) }
            }
        }
        // ±y faces.
        for lt in 0..<b {
            for lx in 0..<b {
                let f = t0 + lt, x = x0 + lx
                if y0 + b < s { bond(f, (y0 + b - 1) * s + x, f, (y0 + b) * s + x) }
                if y0 > 0 { bond(f, (y0 - 1) * s + x, f, y0 * s + x) }
            }
        }
        // ±x faces.
        for lt in 0..<b {
            for ly in 0..<b {
                let f = t0 + lt, y = y0 + ly
                if x0 + b < s { bond(f, y * s + x0 + b - 1, f, y * s + x0 + b) }
                if x0 > 0 { bond(f, y * s + x0 - 1, f, y * s + x0) }
            }
        }
        return e
    }

    /// ★ Kept ONLY to be refuted (PD2): the colourblind form — the
    /// count of interior bonds whose two INDICES differ. Mirrors the
    /// spec's `energyIndex` exactly (full index inequality; NOT
    /// DyadEnergy's σ-spin flip, which is coarser still — C1). Never
    /// used to steer anything.
    static func indexWalls(_ cube: Cube, tile ti: Int) -> Int {
        let b = ANELoop.blockSide, s = cube.side
        let (bx, by, bt) = origin(cube, tile: ti)
        var n = 0
        for lt in 0..<b {
            for ly in 0..<b {
                for lx in 0..<b {
                    let f = bt * b + lt
                    let p = (by * b + ly) * s + (bx * b + lx)
                    let i = cube.indices[f][p]
                    if lt + 1 < b, i != cube.indices[f + 1][p] { n += 1 }
                    if ly + 1 < b, i != cube.indices[f][p + s] { n += 1 }
                    if lx + 1 < b, i != cube.indices[f][p + 1] { n += 1 }
                }
            }
        }
        return n
    }

    // MARK: - § 6. The tiling

    /// One tile's full measurement: the order parameters (all three
    /// computed, only φ classifying — PD7) and the interior term.
    static func measure(_ cube: Cube, tile ti: Int) -> Tile {
        let s = cube.side
        let (bx, by, bt) = origin(cube, tile: ti)
        var ground = 0, staggered = 0, distinct = 0
        var seen = [Bool](repeating: false, count: entryCount)
        for v in 0..<ANELoop.blockVoxels {
            let (f, p) = address(cube, tile: ti, voxel: v)
            let i = Int(cube.indices[f][p])
            if !seen[i] { seen[i] = true; distinct += 1 }
            let isGround = i >= DyadPalette.primaryCount
            if isGround { ground += 1 }
            // The staggered sign is on the ABSOLUTE spacetime
            // checkerboard, as in the spec's `sign (t, y, x)`.
            let sign = (f + p / s + p % s) % 2 == 0 ? 1 : -1
            staggered += sign * (isGround ? 1 : -1)
        }
        return Tile(index: ti, bx: bx, by: by, bt: bt,
                    voxelCount: ANELoop.blockVoxels,
                    groundCount: ground,
                    distinctCount: distinct,
                    staggered: staggered,
                    interior: tileEnergy(cube, tile: ti))
    }

    /// The whole measurement, one pass. PD8's totality (every tile is
    /// enumerated by address arithmetic, never by membership search)
    /// and PD3's decomposition are structural in this function.
    static func tile(_ cube: Cube) -> Tiling {
        var tiles: [Tile] = []
        tiles.reserveCapacity(cube.tileCount)
        var interior = 0.0
        var face = 0, band = 0, solid = 0
        for ti in 0..<cube.tileCount {
            let t = measure(cube, tile: ti)
            interior += t.interior
            switch t.phase {
            case .face: face += 1
            case .band: band += 1
            case .solid: solid += 1
            }
            tiles.append(t)
        }
        let bonds = bondCount(side: cube.side, frameCount: cube.frameCount)
        let inner = interiorBondCount(side: cube.side, frameCount: cube.frameCount)
        return Tiling(tiles: tiles,
                      interior: interior,
                      walls: wallEnergy(cube),
                      faceCount: face, bandCount: band, solidCount: solid,
                      bondCount: bonds,
                      interiorBondCount: inner,
                      wallBondCount: bonds - inner)
    }

    // MARK: - § 7. PD9 — incrementality

    /// Replace tile ti's blockVoxels indices (raster order =
    /// ANELoop.localXYT). Tables untouched.
    static func edit(_ cube: Cube, tile ti: Int, indices newIndices: [UInt8]) -> Cube {
        precondition(newIndices.count == ANELoop.blockVoxels,
                     "an edit must carry exactly one block of indices")
        var frames = cube.indices
        for v in 0..<ANELoop.blockVoxels {
            let (f, p) = address(cube, tile: ti, voxel: v)
            frames[f][p] = newIndices[v]
        }
        return Cube(side: cube.side, frameCount: cube.frameCount,
                    indices: frames, tableLabs: cube.tableLabs)
    }

    /// ★ PD9. Recomputes ONLY tile ti's interior term and ONLY the
    /// wall bonds incident on ti:
    ///
    ///   interior' = interior − tiles[ti].interior + tileEnergy(new, ti)
    ///   walls'    = walls − wallEnergyAround(old, ti)
    ///                     + wallEnergyAround(new, ti)
    ///
    /// Every other Tile value is CARRIED THROUGH unchanged — bit-
    /// identical, not recomputed. That is the law, and the test
    /// asserts exact equality on those. O(blockVoxels), not O(cube).
    static func update(_ tiling: Tiling, from old: Cube, to new: Cube,
                       tile ti: Int) -> Tiling {
        let previous = tiling.tiles[ti]
        let updated = measure(new, tile: ti)
        var tiles = tiling.tiles
        tiles[ti] = updated
        var face = tiling.faceCount
        var band = tiling.bandCount
        var solid = tiling.solidCount
        func bump(_ p: Phase, _ by: Int) {
            switch p {
            case .face: face += by
            case .band: band += by
            case .solid: solid += by
            }
        }
        bump(previous.phase, -1)
        bump(updated.phase, +1)
        return Tiling(tiles: tiles,
                      interior: tiling.interior - previous.interior + updated.interior,
                      walls: tiling.walls
                           - wallEnergyAround(old, tile: ti)
                           + wallEnergyAround(new, tile: ti),
                      faceCount: face, bandCount: band, solidCount: solid,
                      bondCount: tiling.bondCount,
                      interiorBondCount: tiling.interiorBondCount,
                      wallBondCount: tiling.wallBondCount)
    }

    // MARK: - § 8. PD6 — κ in OKLab

    /// The cube's colour field, house layout x + side·(y + side·f)
    /// (PhaseTelemetry's convention).
    static func field(_ cube: Cube) -> [OKLabColor] {
        var out: [OKLabColor] = []
        out.reserveCapacity(cube.side * cube.side * cube.frameCount)
        for f in 0..<cube.frameCount {
            for y in 0..<cube.side {
                for x in 0..<cube.side {
                    out.append(cube.lab(frame: f, pixel: x + cube.side * y))
                }
            }
        }
        return out
    }

    /// One κ step: the 2×2×2 spacetime MEAN of COLOURS (C6 — not
    /// TriScaleLadder's exact UInt64 lattice-level pool). Returns nil
    /// unless both dimensions are even.
    static func poolLab(_ f: [OKLabColor], side: Int, frameCount: Int)
        -> (field: [OKLabColor], side: Int, frameCount: Int)?
    {
        guard side % 2 == 0, frameCount % 2 == 0, side > 0, frameCount > 0,
              f.count == side * side * frameCount else { return nil }
        let hs = side / 2, hf = frameCount / 2
        var out: [OKLabColor] = []
        out.reserveCapacity(hs * hs * hf)
        // 8 = 2³, the pooling atom's voxel count — the ratio the whole
        // rate ladder is built on (RL1), not a tuning.
        let atom = Double(2 * 2 * 2)
        for tb in 0..<hf {
            for yb in 0..<hs {
                for xb in 0..<hs {
                    var l = 0.0, a = 0.0, b = 0.0
                    for dt in 0..<2 {
                        for dy in 0..<2 {
                            for dx in 0..<2 {
                                let v = f[(2 * xb + dx)
                                        + side * ((2 * yb + dy)
                                        + side * (2 * tb + dt))]
                                l += v.l; a += v.a; b += v.b
                            }
                        }
                    }
                    out.append(OKLabColor(l: l / atom, a: a / atom, b: b / atom))
                }
            }
        }
        return (out, hs, hf)
    }

    /// Σ dE2 over the open lattice of a colour field (C2: open in t).
    static func energyField(_ f: [OKLabColor], side: Int, frameCount: Int) -> Double {
        var e = 0.0
        for t in 0..<frameCount {
            for y in 0..<side {
                for x in 0..<side {
                    let i = x + side * (y + side * t)
                    let c = f[i]
                    if t + 1 < frameCount {
                        e += DyadPalette.dLab2(c, f[i + side * side])
                    }
                    if y + 1 < side { e += DyadPalette.dLab2(c, f[i + side]) }
                    if x + 1 < side { e += DyadPalette.dLab2(c, f[i + 1]) }
                }
            }
        }
        return e
    }

    /// PD6's quantity: energy PER BOND. Coarse rungs are calmer —
    /// a MEASURED property of real fields at the spec's scope, never
    /// asserted at runtime.
    static func energyDensity(_ f: [OKLabColor], side: Int, frameCount: Int) -> Double {
        energyField(f, side: side, frameCount: frameCount)
            / Double(bondCount(side: side, frameCount: frameCount))
    }

    // MARK: - § 9. Float slack (derived, not naked)

    /// Worst-case round-off of a naive left-to-right summation of n
    /// non-negative terms:
    ///
    ///     |Ê − E| ≤ n·ε·|E| / (1 − n·ε)
    ///
    /// (Higham, *Accuracy and Stability of Numerical Algorithms*,
    /// 2nd ed., §4.2). Every bond cost is a sum of three squares, so
    /// it is ≥ 0 and the non-negative bound applies. ε =
    /// Double.ulpOfOne. This is NOT a tuned constant: it is a
    /// function of the bond count the cube itself declares.
    static func summationSlack(_ e: Double, terms: Int) -> Double {
        let n = Double(terms) * Double.ulpOfOne
        guard n < 1 else { return .infinity }
        return n * abs(e) / (1 - n)
    }

    // MARK: - § 10. Trace (STEP 2 — placement awaits a ruling)

    /// "PHASE TILING v1 tiles=… face=… band=… solid=… band%=…
    ///  E=… Eint=… Ewall=… k64=… k32=… k16=…"
    ///
    /// Same shape as PhaseTelemetry's "PHASE F v1" line. NOT appended
    /// to any GIF comment at STEP 1 — doing so changes comment bytes
    /// and belongs to a STEP 2 Daniel approves.
    static func trace(_ t: Tiling, density: [Double]) -> String {
        // The ladder has three rungs (TL3: 64/32/16); a short density
        // array is padded so the line's shape never varies.
        let k = density + [Double](repeating: 0, count: max(0, 3 - density.count))
        return String(format: "PHASE TILING v1 tiles=%d face=%d band=%d solid=%d "
                            + "band%%=%.6g E=%.6g Eint=%.6g Ewall=%.6g "
                            + "k64=%.6g k32=%.6g k16=%.6g",
                      t.tiles.count, t.faceCount, t.bandCount, t.solidCount,
                      t.bandFraction, t.total, t.interior, t.walls,
                      k[0], k[1], k[2])
    }
}
