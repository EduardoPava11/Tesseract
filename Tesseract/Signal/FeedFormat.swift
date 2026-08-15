// FeedFormat.swift
// Tesseract
//
// Swift port of spec/output/FeedCompression.hs — the WIRE FORMAT the
// three rungs write, and the shape the synthetic sampler must inhabit.
// The Haskell spec is authoritative (axioms FC1–FC10).
//
// A RUNG IS A RATE. κ (the 2×2×2 spacetime atom, Octave OV10) halves
// time exactly as it halves space, so the loop duration is the
// invariant and the rung sets the rate: side × delay = 320 cs at 64,
// 32 and 16 alike (FC1). That table already ships — RungTelemetry
// .delayCs (TriScaleLadder.swift:50) — and DyadPipeline.Live's
// refreshStride slow state has been the rung-16 rate all along.
//
// THE CARRIER here is OKLab+depth MEANS of the raw feed, pooled before
// quantization. That is NOT TriScaleLadder's carrier: RungCube holds
// exact UInt64 lattice-level sums of QUANTIZED indices, post-palette.
// Same ladder, different point in the pipeline; the two do not merge.
// (FeedCube cannot adopt the exact-sum carrier either: OKLab values of
// sRGB8 inputs are irrational, so no integer grid makes sums exact.)
//
// κ IS A MEAN, so the colour channels are OKLab, never gamma sRGB —
// averaging a nonlinear code averages the code, not the colour (spec
// § 2, PhaseTiling PD1). The conversion happens ONCE, on the way in,
// from unit sRGB — never through an 8-bit round trip, because rounded
// means do not compose (TriScaleLadder TL2).
//
// DEPTH IS DepthSignal SPACE, NEVER METERS (FC10, conflict C4).
// DepthSignal is the producer contract (s ∈ [0,1], 1 = near, 0.5 =
// fill) and DepthMixture.metersOf exists only to REPORT a crossover
// (DM6: meters are an OUTPUT, never an input). Nothing in this file
// calls metersOf or accepts meters; cube(from:) preconditions the
// boundary.
//
// MEASUREMENT ONLY in v1 (decree-bound, like the tri-scale ladder):
// the ARITHMETIC here reads nothing back into the encoder, and it
// trains nothing on captured data (★NO-CAPTURE-TRAINING — the corpus
// is the sampler PROGRAM).
//
// ⚠ BUT `Rung` IS LOAD-BEARING FOR EXPORTED PIXELS. It is the one
// symbol in this file the shipping path derives from:
//   · DyadPipeline.chaosRung   = Rung.fine.side / Rung.coarse.side
//     → chaosPool / pairDitherFrame → Output.indexFrames → the GIF
//   · DyadPipeline.Live.refreshStride, .ringFrames
// Editing a `Rung` raw value as though it were telemetry MOVES EVERY
// EXPORTED BACKGROUND INDEX (coarse 16 → 8 turns the σ-side blur from
// a 4×4 block mean into an 8×8 one). `testFC1RateLaw` fails on such an
// edit, but read this before trusting the "measurement only" framing.
// Atlas stage FEEDING, coordinate WEAVING × METER — the same square
// RUNGING occupies, for the same reason (it computes a tower nothing
// reads).
//
// NON-GOALS, stated so they are not mistaken for omissions:
//   · No serializer. FC3/FC4/FC5 are ARITHMETIC laws about honest
//     typing (8-bit OKLab + fp16 depth); no axiom pins the a/b range
//     needed to quantize OKLab's opponent axes into a byte, and
//     inventing one would be a naked constant (conflict C7). An
//     actual 5 B/cell packing is OWED a new axiom deriving that
//     range from the sRGB gamut's OKLab extent.
//   · FC5's todayBytes counts CapturedFrame's 12 + 4 = 16 B/cell,
//     exactly as the spec states it. The burst that actually
//     survives is QuantizedFrame (indices + optional fp32 triples +
//     fp32 depths, ≥ 17 B/cell), which only strengthens FC5; it is
//     footnoted here and asserted nowhere (conflict C5).
//   · FC7 is ported as ARITHMETIC/TELEMETRY ONLY. The shipping
//     figure half is the analytic PAIR TREE (PT7–PT9,
//     CameraConfig.pairTree default ON) and the σ half is GENERATED
//     by the ground law; the binomial ladder survives as the
//     balanced tree's growth rings. Nothing here routes assignment
//     (conflict C1).

import Foundation

// ════════════════════════════════════════════════════════════════
// § 0. The one thing the shipping palette does not yet expose
// ════════════════════════════════════════════════════════════════

extension DyadPalette {

    /// Unit-sRGB entry point: the same Ottosson pipeline as
    /// `oklab(fromSRGB8:)`, entered BEFORE the 8-bit grid. Needed
    /// here because κ is a MEAN and rounding to 8 bits first would
    /// round before averaging (TL2).
    ///
    /// ⚠ PLACEMENT DEBT: this belongs in DyadPalette.swift, with
    /// `oklab(fromSRGB8:)` delegating to it at c/255. This port was
    /// forbidden from editing shipping files, so it lands here as an
    /// extension of the same type — one call site, one name, and the
    /// move is a pure cut-and-paste when a later step takes it. The
    /// duplicated matrix rows are the cost, and they are GATED:
    /// `FeedFormatTests.testFC3OKLabUnitParity` asserts bit-identity
    /// against `oklab(fromSRGB8:)` for all 256 values per channel, so
    /// a drift in either copy fails the suite rather than the render.
    static func oklab(fromSRGBUnit rgb: (Double, Double, Double)) -> OKLabColor {
        let r = srgbToLinear(rgb.0)
        let g = srgbToLinear(rgb.1)
        let b = srgbToLinear(rgb.2)
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let l3 = cbrt(l), m3 = cbrt(m), s3 = cbrt(s)
        return OKLabColor(
            l: 0.2104542553 * l3 + 0.7936177850 * m3 - 0.0040720468 * s3,
            a: 1.9779984951 * l3 - 2.4285922050 * m3 + 0.4505937099 * s3,
            b: 0.0259040371 * l3 + 0.7827717662 * m3 - 0.8086757660 * s3)
    }
}

// ════════════════════════════════════════════════════════════════
// § 1. The rungs, as rates
// ════════════════════════════════════════════════════════════════

/// FC1/FC2: a rung is a RATE, not a resolution. The set is CLOSED at
/// {64, 32, 16} — 128 has no integer centisecond delay (320/128 = 2.5),
/// which is why the ladder caps at 64 (TriScaleLadder TL4). Making it
/// an enum is what makes an off-ladder rung unrepresentable: FC1's
/// integer-delay clause is STRUCTURAL here, not asserted.
enum Rung: Int, CaseIterable, Sendable {
    case fine   = 64      // 64 frames, 5 cs, 20 Hz — the export cube
    case mid    = 32      // 32 frames, 10 cs, 10 Hz
    case coarse = 16      // 16 frames, 20 cs, 5 Hz — the resolution of depth (TL9)

    var side: Int { rawValue }

    /// FC2, structural: κ halves time with space, so frames IS side.
    /// CameraConfig already ships S = K (CubeMode.frameCount == rawValue).
    var frames: Int { rawValue }

    var cells: Int { side * side * side }

    /// FC1: derived from the ONE shipping loop constant, never re-declared.
    var delayCs: Int { RungTelemetry.loopCs / side }

    var rateHz: Double { Double(frames) * 100 / Double(RungTelemetry.loopCs) }

    /// One κ step down; nil at the coarse end of the ladder — so
    /// "one rung below 16" is `nil`, not an invalid rung (FC2).
    var pooled: Rung? { Rung(rawValue: rawValue / 2) }
}

/// FC3: the payload is four channels. Not three, not five — a
/// three- or five-channel payload is unrepresentable.
enum FeedChannel: Int, CaseIterable, Sendable { case l, a, b, d }

/// A cell of a rung, frame-major then row-major — the (t, y, x) order
/// of the spec's `idx` and of RungCube's storage.
struct FeedCell: Equatable, Hashable, Comparable, Sendable {
    let t: Int, y: Int, x: Int

    func linear(side: Int) -> Int { t * side * side + y * side + x }

    /// FC10 totality: an out-of-range cell is answered by the nearest
    /// in-range one rather than by a trap. In-range cells are
    /// untouched, so spec parity is unaffected.
    func clamped(side: Int) -> FeedCell {
        FeedCell(t: min(max(t, 0), side - 1),
                 y: min(max(y, 0), side - 1),
                 x: min(max(x, 0), side - 1))
    }

    /// Lexicographic in (t, y, x) — the `linear` order, so `sorted()`
    /// agrees with storage order at any side.
    static func < (a: FeedCell, b: FeedCell) -> Bool {
        (a.t, a.y, a.x) < (b.t, b.y, b.x)
    }
}

/// FC10: one sample of the feed. All four components in [0,1] —
/// depth is DepthSignal space (1 = near, 0 = far), NEVER meters.
struct FeedSample: Equatable, Sendable {
    let r: Double, g: Double, b: Double, depth: Double

    /// The no-evidence answer. FC10 demands a TOTAL function, and the
    /// producer contract already names the value that stands for
    /// "no signal here": DepthSignal.fill. Not a fresh constant —
    /// the same neutral, read across all four channels.
    static let fill = FeedSample(r: Double(DepthSignal.fill),
                                 g: Double(DepthSignal.fill),
                                 b: Double(DepthSignal.fill),
                                 depth: Double(DepthSignal.fill))
}

/// FC3: one rung of the compressed feed — four planes of side³,
/// frame-major then row-major. L/a/b are OKLab means; d is the
/// DepthSignal mean.
struct FeedCube: Equatable, Sendable {
    let rung: Rung
    var l: [Double], a: [Double], b: [Double], d: [Double]

    func lab(at i: Int) -> OKLabColor { OKLabColor(l: l[i], a: a[i], b: b[i]) }
}

// ════════════════════════════════════════════════════════════════
// § 2. The rate law, the byte budget, and compression
// ════════════════════════════════════════════════════════════════

enum FeedFormat {

    /// FC1: the loop is the invariant. Aliased, not re-declared —
    /// 5 cs / 20 Hz / stride-4 are already stated in four places
    /// (GIFEncoder.frameDelayCentiseconds, CameraConfig.targetFPS,
    /// RungTelemetry.delayCs, DyadPipeline.Live.refreshStride) and this
    /// file must not become the fifth (conflict C3).
    static var loopCs: Int { RungTelemetry.loopCs }

    /// Pyramid order: fine → coarse.
    static let rungs: [Rung] = [.fine, .mid, .coarse]

    /// κ, the 2×2×2 spacetime atom (Octave OV10) — the 8:1 ratio of
    /// RateLadder RL1. Derived from the ladder itself, so the pooling
    /// block size cannot disagree with the rung it produces.
    static var kappaCells: Int { Rung.fine.cells / Rung.mid.cells }

    // MARK: - § 2. The byte budget (FC3, FC4, FC5)
    //
    // These are ARITHMETIC laws about honest typing, not a serializer.
    // No naked constants: the colour channel count is the payload
    // minus depth, the colour width is the wire's own index width
    // (RateLadder RL5, H_max = 8 bits = UInt8), depth is fp16.

    /// FC3: L, a, b — the payload's four channels less the depth one.
    static var colourChannelCount: Int { FeedChannel.allCases.count - 1 }

    /// FC3: one value per channel per cell.
    static func values(at rung: Rung) -> Int {
        FeedChannel.allCases.count * rung.cells
    }

    /// FC3: honest typing — 8-bit OKLab + fp16 depth = 5 B/cell.
    static var bytesPerCell: Int {
        colourChannelCount * MemoryLayout<UInt8>.size + MemoryLayout<Float16>.size
    }

    /// What CapturedFrame retains TODAY: fp32 sRGB triple + fp32 depth
    /// (CapturedFrame.swift:18, :21). Read from the layout so FC5's
    /// premise cannot silently rot if those fields change type.
    static var todayBytesPerCell: Int {
        MemoryLayout<(Float, Float, Float)>.size + MemoryLayout<Float>.size
    }

    static func bytes(at rung: Rung) -> Int { rung.cells * bytesPerCell }

    static var pyramidBytes: Int { rungs.reduce(0) { $0 + bytes(at: $1) } }

    static var todayBytes: Int { Rung.fine.cells * todayBytesPerCell }

    /// FC4: exactly 73/64. Returned as an EXACT ratio (unreduced,
    /// 299008/262144) — a Double would forfeit the spec's Rational
    /// exactness, and the gate is `num * 64 == den * 73`.
    static var pyramidTax: (numerator: Int, denominator: Int) {
        (rungs.reduce(0) { $0 + $1.cells }, Rung.fine.cells)
    }

    // MARK: - § 2b. Compression — RGB+depth feed → OKLab+depth rungs

    /// The fine rung, straight off the burst. nil unless the burst is
    /// the full 64 frames of 64² (Rung.fine.frames × side²).
    ///
    /// The conversion is unit sRGB → OKLab in ONE step. Routing
    /// through srgb8 first (the DyadPipeline path, which is correct
    /// there because the palette is 8-bit) would round before the
    /// mean, and rounded means do not compose (TL2).
    ///
    /// Depth is CARRIED, never derived (FC3), and it is DepthSignal
    /// space — the precondition is the boundary guard against a
    /// meters value entering the format (conflict C4).
    static func cube(from frames: [CapturedFrame]) -> FeedCube? {
        let rung = Rung.fine
        let side = rung.side
        let plane = side * side
        guard frames.count == rung.frames,
              frames.allSatisfy({ $0.rgb.count == plane && $0.depths.count == plane })
        else { return nil }

        let n = rung.cells
        var l = [Double](repeating: 0, count: n)
        var a = [Double](repeating: 0, count: n)
        var b = [Double](repeating: 0, count: n)
        var d = [Double](repeating: 0, count: n)
        var v = 0
        for frame in frames {
            for p in 0..<plane {
                let px = frame.rgb[p]
                let lab = DyadPalette.oklab(
                    fromSRGBUnit: (Double(px.0), Double(px.1), Double(px.2)))
                let s = Double(frame.depths[p])
                precondition(s.isFinite && s >= 0 && s <= 1,
                             "FeedFormat: depth must be DepthSignal space [0,1] "
                             + "(1 = near, 0.5 = fill) — meters are an OUTPUT (DM6)")
                l[v] = lab.l; a[v] = lab.a; b[v] = lab.b; d[v] = s
                v += 1
            }
        }
        return FeedCube(rung: rung, l: l, a: a, b: b, d: d)
    }

    /// κ: one rung down by exact 2×2×2 spacetime mean pooling. nil at
    /// the coarse end. Accumulates in Double and stores Double — FC6's
    /// mean preservation is the reason no intermediate is ever
    /// narrowed.
    static func pool(_ cube: FeedCube) -> FeedCube? {
        guard let next = cube.rung.pooled else { return nil }
        let s = cube.rung.side, h = next.side, n = next.cells
        var l = [Double](repeating: 0, count: n)
        var a = [Double](repeating: 0, count: n)
        var b = [Double](repeating: 0, count: n)
        var d = [Double](repeating: 0, count: n)
        // The κ block: 2 in t, 2 in y, 2 in x (Octave OV10).
        let blockCells = Double(kappaCells)
        for f in 0..<h {
            for r in 0..<h {
                for col in 0..<h {
                    var sl = 0.0, sa = 0.0, sb = 0.0, sd = 0.0
                    for df in 0...1 {
                        for dr in 0...1 {
                            for dc in 0...1 {
                                let src = (2 * f + df) * s * s
                                        + (2 * r + dr) * s
                                        + (2 * col + dc)
                                sl += cube.l[src]; sa += cube.a[src]
                                sb += cube.b[src]; sd += cube.d[src]
                            }
                        }
                    }
                    let dst = f * h * h + r * h + col
                    l[dst] = sl / blockCells; a[dst] = sa / blockCells
                    b[dst] = sb / blockCells; d[dst] = sd / blockCells
                }
            }
        }
        return FeedCube(rung: next, l: l, a: a, b: b, d: d)
    }

    /// FC6: the within-block variance of the D channel that κ throws
    /// away — the E[σ²_within] term of the law of total variance, and
    /// exactly the argument DepthMixture.fitLifted(means:
    /// meanWithinVariance:) needs to un-shrink a coarse-rung fit
    /// (DM11/DM12). Computed on the SAME 2×2×2 blocks as `pool`; the
    /// block geometry is defined wherever side ≥ 2, even at the rung
    /// where the LADDER stops.
    static func depthWithinVariance(_ cube: FeedCube) -> Double {
        let s = cube.rung.side
        guard s >= 2 else { return 0 }
        let h = s / 2
        let blockCells = Double(kappaCells)
        var total = 0.0
        for f in 0..<h {
            for r in 0..<h {
                for col in 0..<h {
                    var sum = 0.0, sumSq = 0.0
                    for df in 0...1 {
                        for dr in 0...1 {
                            for dc in 0...1 {
                                let v = cube.d[(2 * f + df) * s * s
                                             + (2 * r + dr) * s
                                             + (2 * col + dc)]
                                sum += v; sumSq += v * v
                            }
                        }
                    }
                    let m = sum / blockCells
                    total += max(0, sumSq / blockCells - m * m)
                }
            }
        }
        return total / Double(h * h * h)
    }

    /// All three rungs. [fine, mid, coarse] — pyramid order, matching
    /// `rungs`. nil unless the burst is the full 64³.
    static func pyramid(from frames: [CapturedFrame]) -> [FeedCube]? {
        guard let fine = cube(from: frames),
              let mid = pool(fine),
              let coarse = pool(mid)
        else { return nil }
        return [fine, mid, coarse]
    }

    /// Population variance of a plane — the between/total terms of the
    /// law of total variance. Not mixture arithmetic; this file owns
    /// no mixture arithmetic (FC6 delegates).
    static func variance(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let n = Double(xs.count)
        let m = xs.reduce(0, +) / n
        return xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / n
    }

    /// FC6, convenience: the coarse-rung mixture fit, τ-lifted so its
    /// crossover is comparable to the fine rung's. Delegates to
    /// DepthMixture — this file owns no mixture arithmetic.
    ///
    /// The lift argument is the law of total variance read as an
    /// identity: pooling by equal-size blocks preserves the grand
    /// mean, so
    ///
    ///   E[σ²_within] = Var(fine.d) − Var(coarse.d)
    ///
    /// exactly — and that telescopes into Σ depthWithinVariance over
    /// the intermediate rungs, which is what DyadPipeline.Live
    /// computes at its own single two-rung span (the κ read). No
    /// constant enters; the identity is the whole argument.
    static func liftedDepthFit(fine: FeedCube, coarse: FeedCube) -> DepthMixture.Fit {
        let within = max(0, variance(fine.d) - variance(coarse.d))
        return DepthMixture.fitLifted(means: coarse.d, meanWithinVariance: within)
    }

    // MARK: - § 3. The attractor ladder — colour concentrations
    //
    // TELEMETRY ONLY. The shipping figure half is the ANALYTIC PAIR
    // TREE (PT7–PT9, CameraConfig.pairTree default ON) and the σ half
    // is GENERATED by the ground law — nothing here routes assignment.
    // The binomial ladder survives as the balanced tree's growth rings
    // (pair-tree decree), and this is its arithmetic statement.
    // FC7's prose "one per rung-16 row" is descriptive: no axiom binds
    // a basin to a palette row, and none is bound here (conflict C1).

    /// The spec's shellHalf IS DyadPalette.ladder — the same eight
    /// numbers, not a copy, so the two can never diverge.
    static var shellHalf: [Int] { DyadPalette.ladder }

    /// σ-symmetric: sixteen basins over the 256 colours.
    static var attractors: [Int] { shellHalf + shellHalf.reversed() }

    static var paletteSize: Int { CameraConfig.paletteSize }

    // MARK: - § 4. Tiling — the 64³ by 4³, and the additive energy

    /// FC8: the tile side is the TWO-RUNG SPAN, fine ÷ coarse = 4 —
    /// one tile is one rung-16 judgment (TL9), 4³ = 64 =
    /// RungTelemetry.samplesPerJudgment base samples. Not a constant:
    /// a consequence of where the ladder starts and stops.
    static var tileSide: Int { Rung.fine.side / Rung.coarse.side }

    /// 4096 tiles = RungTelemetry.judgmentsPerLoop = Rung.coarse.cells.
    static var tileCount: Int { Rung.coarse.cells }

    /// Every cell of a side³ cube, in storage order.
    static func coords(side: Int) -> [FeedCell] {
        var out = [FeedCell]()
        out.reserveCapacity(side * side * side)
        for t in 0..<side {
            for y in 0..<side {
                for x in 0..<side { out.append(FeedCell(t: t, y: y, x: x)) }
            }
        }
        return out
    }

    static func tile(of cell: FeedCell, tileSide k: Int) -> FeedCell {
        FeedCell(t: cell.t / k, y: cell.y / k, x: cell.x / k)
    }

    static func cells(ofTile tile: FeedCell, tileSide k: Int) -> [FeedCell] {
        var out = [FeedCell]()
        out.reserveCapacity(k * k * k)
        for dt in 0..<k {
            for dy in 0..<k {
                for dx in 0..<k {
                    out.append(FeedCell(t: tile.t * k + dt,
                                        y: tile.y * k + dy,
                                        x: tile.x * k + dx))
                }
            }
        }
        return out
    }

    static func tiles(side: Int, tileSide k: Int) -> [FeedCell] {
        coords(side: side / k)
    }

    /// An ordered adjacent pair. OPEN boundary on all three axes —
    /// TIME included (spec § 4). NOT the loop torus: the polyphase
    /// laws (RateLadder RL3, TriScaleLadder TL10) WRAP in time; this
    /// energy does not, and the bond counts differ because of it
    /// (conflict C6). Never hand these bonds to polyphase code.
    struct FeedBond: Equatable, Hashable, Sendable { let p: FeedCell, q: FeedCell }

    static func bonds(side: Int) -> [FeedBond] {
        var out = [FeedBond]()
        // Open boundary, three axes: 3·side²·(side−1) ordered pairs.
        out.reserveCapacity(3 * side * side * (side - 1))
        for p in coords(side: side) {
            let neighbours = [FeedCell(t: p.t + 1, y: p.y, x: p.x),
                              FeedCell(t: p.t, y: p.y + 1, x: p.x),
                              FeedCell(t: p.t, y: p.y, x: p.x + 1)]
            for q in neighbours where q.t < side && q.y < side && q.x < side {
                out.append(FeedBond(p: p, q: q))
            }
        }
        return out
    }

    static func interiorBonds(side: Int, tileSide k: Int) -> [FeedBond] {
        bonds(side: side).filter { tile(of: $0.p, tileSide: k) == tile(of: $0.q, tileSide: k) }
    }

    static func wallBonds(side: Int, tileSide k: Int) -> [FeedBond] {
        bonds(side: side).filter { tile(of: $0.p, tileSide: k) != tile(of: $0.q, tileSide: k) }
    }

    // ★ FC9 IS WEIGHT-INDEPENDENT. The spec states the law for ANY
    // bond cost and leaves the correct one to PhaseTiling.hs, which
    // computes ΔE² in OKLab and PROVES (PD2) that a colourblind index
    // count is a DIFFERENT answer, not an approximation. So the weight
    // is a PARAMETER of every function here and is never stored,
    // defaulted, or curried in — there is deliberately NO overload
    // without `weight:`. Generic in the cell type so an index cube
    // ([Int], the spec's witness weights) and a colour cube
    // ([OKLabColor], DyadPalette.dLab2) share one code path.

    static func energy<C>(_ cells: [C], side: Int, bonds: [FeedBond],
                          weight: (C, C) -> Double) -> Double {
        var total = 0.0
        for bond in bonds {
            total += weight(cells[bond.p.linear(side: side)],
                            cells[bond.q.linear(side: side)])
        }
        return total
    }

    /// The per-tile interior energy — the tile-local quantity FC9
    /// makes composable. Generated directly from the tile's own cells
    /// (not by filtering the cube's bonds), so `Σ tileEnergy ==
    /// energy(interiorBonds)` is a real cross-check of two
    /// independent constructions.
    static func tileEnergy<C>(_ cells: [C], side: Int, tile: FeedCell,
                              tileSide k: Int, weight: (C, C) -> Double) -> Double {
        var bs = [FeedBond]()
        bs.reserveCapacity(3 * k * k * (k - 1))
        for dt in 0..<k {
            for dy in 0..<k {
                for dx in 0..<k {
                    let p = FeedCell(t: tile.t * k + dt,
                                     y: tile.y * k + dy,
                                     x: tile.x * k + dx)
                    if dt + 1 < k { bs.append(FeedBond(p: p, q: FeedCell(t: p.t + 1, y: p.y, x: p.x))) }
                    if dy + 1 < k { bs.append(FeedBond(p: p, q: FeedCell(t: p.t, y: p.y + 1, x: p.x))) }
                    if dx + 1 < k { bs.append(FeedBond(p: p, q: FeedCell(t: p.t, y: p.y, x: p.x + 1))) }
                }
            }
        }
        return energy(cells, side: side, bonds: bs, weight: weight)
    }

    /// The spec's two unrelated witness weights, exported so the tests
    /// can show the law does not depend on which is chosen. They are
    /// WITNESSES, not defaults — nothing in the port calls them.
    static let wallCountWeight: @Sendable (Int, Int) -> Double = { $0 == $1 ? 0 : 1 }
    static let spreadWeight:    @Sendable (Int, Int) -> Double = { Double(($0 - $1) * ($0 - $1)) }

    // MARK: - § 5. The sampler — synthetic and real, one type
}

/// FC10 ★: the compressed format is a TOTAL function (rung, cell) →
/// sample. A synthetic corpus is a TERM OF THIS TYPE, not something
/// merely similar to one — which is what makes NO-CAPTURE-TRAINING
/// sound. Totality is structural: the protocol admits no failure
/// (non-optional, non-throwing).
protocol FeedSource: Sendable {
    func sample(rung: Rung, at cell: FeedCell) -> FeedSample
}

/// The spec's deterministic synthetic feed — the shape a sampler
/// program must have. Pure, rung-dependent, non-constant.
struct SyntheticFeed: FeedSource, Sendable {

    /// The spec's LCG (FeedCompression § 4): s ↦ (1103515245·s +
    /// 12345) mod 2³¹ — glibc's constants, already mirrored in
    /// TriScaleLadderTests.indexStream. Bit-exact with the Haskell.
    static func lcg(_ s: Int) -> Int {
        (1103515245 &* s &+ 12345) % (1 << 31)
    }

    /// The wire's own alphabet: one byte, 2⁸ codes (RateLadder RL5,
    /// H_max = 8 bits). Every sample component is k/256 — a DYADIC
    /// rational, exactly representable in Double, so parity with the
    /// Haskell's `Rational` is EXACT and needs no tolerance.
    private static let byteCodes = 1 << UInt8.bitWidth

    /// The primitive takes a raw side so the spec's own side-4 and
    /// side-8 fixtures reproduce byte-for-byte; the ladder rungs go
    /// through the protocol. 7919 and 31 are the spec's own mixing
    /// constants (FeedCompression § 5, `syntheticFeed`).
    func sample(side: Int, at cell: FeedCell) -> FeedSample {
        let c = cell.clamped(side: side)
        let base = side &* 7919 &+ c.linear(side: side) &* 31
        func h(_ k: Int) -> Double {
            Double(Self.lcg(base &+ k) % Self.byteCodes) / Double(Self.byteCodes)
        }
        return FeedSample(r: h(1), g: h(2), b: h(3), depth: h(4))
    }

    func sample(rung: Rung, at cell: FeedCell) -> FeedSample {
        sample(side: rung.side, at: cell)
    }
}

/// The real feed, inhabiting the same type. Reads the pyramid built by
/// FeedFormat.pyramid — the identity FC10 asserts.
///
/// Colour comes back out in sRGB, converted from the stored OKLab,
/// because FC10's Sample is (r,g,b,depth) in [0,1] — not Lab. The
/// sampler type is what makes synthetic ≡ real, and the synthetic side
/// emits RGB; returning Lab here would break the identity.
struct CubeFeed: FeedSource, Sendable {
    let cubes: [Rung: FeedCube]

    init(cubes: [Rung: FeedCube]) { self.cubes = cubes }

    /// From `FeedFormat.pyramid(from:)` output, in any order.
    init(pyramid: [FeedCube]) {
        self.cubes = Dictionary(pyramid.map { ($0.rung, $0) },
                                uniquingKeysWith: { _, latest in latest })
    }

    func sample(rung: Rung, at cell: FeedCell) -> FeedSample {
        // Totality (FC10): a rung this feed does not carry is answered
        // with the producer contract's no-evidence fill, never a trap.
        guard let cube = cubes[rung] else { return .fill }
        let i = cell.clamped(side: rung.side).linear(side: rung.side)
        let (lr, lg, lb) = DyadPalette.linearRGB(from: cube.lab(at: i))
        func unit(_ c: Double) -> Double {
            min(1, max(0, DyadPalette.linearToSrgb(min(1, max(0, c)))))
        }
        return FeedSample(r: unit(lr), g: unit(lg), b: unit(lb),
                          depth: min(1, max(0, cube.d[i])))
    }
}
