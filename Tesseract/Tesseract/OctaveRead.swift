// OctaveRead.swift
// Tesseract
//
// THE THREE PARALLEL READS — 64³ ∥ 32³ ∥ 16³. Port of
// spec/quantization/Octave.hs (OV1–OV13 — the Haskell spec is
// authoritative). The live feed is read at three rungs AT ONCE and
// the three streams describe ONE scene, because κ — the exact mean
// over a 2×2×2 spacetime block, in OKLab — COMPOSES (OV13).
//
// 16 is the floor because 16² = 256 = |palette| (OV2): at that rung
// the image and the colour table are the same size, one pixel per
// entry, and the 256 distribute as DyadPalette.ladder mirrored
// through σ (OV3). Below it three quarters of the table could not be
// addressed even once.
//
// ★ THE GATE. OV13 holds for a MEAN and FAILS for a point sample.
// The 64³ fine read this file consumes is whatever the capture funnel
// delivers, and that funnel POINT-SAMPLES: Quantize.metal:196-199
// (downsampleRGB, one texel per 12×12 block, 144:1) and :212-215
// (downsampleDepth, 16:1) — docs/CAPTURE-FUNNELS.md §1. The box
// prefilter that would fix it is rate-ladder step S2
// (spec/output/RateLadder.hs), and it is GATED, twice: on Daniel's
// S2–S6 step-order ruling, and on the device probe of the delivered
// buffer dimensions (★NO CROP CHANGES; CAPTURE-FUNNELS §2 shows the
// 768 crop may not even fit the .photo preview buffer). So this file
// changes NOTHING upstream. It derives every coarser rung by κ and
// only by κ — there is no point-sample entry point here — which
// makes the three reads mutually coherent while all three still
// inherit the funnel's aliasing. Coherence BELOW 64 is the property
// this port can honestly claim today; coherence WITH the sensor
// arrives with S2.
//
// THE CARRIER IS A MEAN, and that is why this is not RungCube.
// TriScaleLadder runs the same 2×2×2 pool on exact UInt64 SUMS of
// post-quantization lattice levels, and TL2 forbids a mean there
// (sums compose transitively; rounded means do not). Octave's κ is a
// mean over PRE-quantization OKLab. One operator, two carriers: the
// sum carrier keeps TL2, this one keeps OV4/OV5 exactness. Nothing
// in TriScaleLadder.swift changes; OctaveReadTests bridges the two.
//
// THE POOLING SPACE IS OKLab, matching shipping precedent exactly
// (DyadPipeline.chaosPool — the export's dither and the live
// surface's alike — already pools in OKLab). OV5 says the mean survives every dial setting IN WHATEVER
// SPACE κ RUNS; it does NOT claim linear-light exposure invariance,
// and this file must not be "fixed" into linear RGB.
//
// EXACT ℚ IN THE SPEC, IEEE-754 Double HERE. The gap is closed by a
// summation ruling, not by a tolerance blanket: κ sums its eight
// children as a BALANCED BINARY TREE and scales by 0.125, so OV12
// and pool ∘ up = id are BIT-EXACT (scaling by a power of two is
// exact and commutes with rounding), and OV6/OV7/OV8 are exact
// because their weight ratios are exactly 1.0 or the same correctly
// rounded quotient. Only the grand-mean laws (OV4b, OV5) and the
// cross-implementation comparisons (OV9, OV10, OV13a) need slack,
// and that slack is meanErrorBound — Higham Thm 4.6 — never a
// hand-picked epsilon (★NO NAKED CONSTANTS).
//
// MEASUREMENT/ALGEBRA ONLY: nothing here is wired to a manager, to
// ExportSettings, or to any GIF byte. ATLAS §7 steps 1–4 change no
// bytes; step 5 (the dial in the SET cover) is Daniel's to rule.

import Foundation

enum OctaveRead {

    // MARK: - § 0. Vector ops (the spec's §0, kept local)

    // OKLabColor is a shipping type; no operator extensions are hung
    // on it. PairTree.swift keeps its own arithmetic the same way.

    private static func vAdd(_ p: OKLabColor, _ q: OKLabColor) -> OKLabColor {
        OKLabColor(l: p.l + q.l, a: p.a + q.a, b: p.b + q.b)
    }

    private static func vSub(_ p: OKLabColor, _ q: OKLabColor) -> OKLabColor {
        OKLabColor(l: p.l - q.l, a: p.a - q.a, b: p.b - q.b)
    }

    private static func vScale(_ s: Double, _ p: OKLabColor) -> OKLabColor {
        OKLabColor(l: s * p.l, a: s * p.a, b: s * p.b)
    }

    private static func vNorm2(_ p: OKLabColor) -> Double {
        p.l * p.l + p.a * p.a + p.b * p.b
    }

    private static let vZero = OKLabColor(l: 0, a: 0, b: 0)

    // MARK: - § 1. The rungs and the ladder (OV1, OV2, OV3)

    /// The three lawful rungs. Three cases, no more: a fourth rung is
    /// not a runtime error, it is not expressible (OV1 — STRUCTURAL).
    /// Sides are DERIVED — 64 = TriScaleLadder's base rung, 16 = the
    /// resolution of depth (TL9), 32 = the rung between them.
    enum Rung: CaseIterable, Sendable {
        case fine, mid, coarse

        var side: Int {
            switch self {
            case .fine: return RungTelemetry.baseRungSide            // 64
            case .mid: return RungTelemetry.baseRungSide / 2         // 32
            case .coarse: return RungTelemetry.depthRungSide         // 16
            }
        }

        /// side³ — one cell per (frame, row, column) of the cube.
        var cellCount: Int { side * side * side }

        /// One rung down, or nil at the BIJECTION FLOOR (OV2 —
        /// STRUCTURAL): pooling past 16 would produce 8² = 64 < 256
        /// and un-addressable table entries. The floor is enforced by
        /// the type, not by a check the caller may forget.
        var coarser: Rung? {
            switch self {
            case .fine: return .mid
            case .mid: return .coarse
            case .coarse: return nil
            }
        }

        /// One rung up, or nil at the ceiling: 128 has no integer GIF
        /// delay (TL4, RungTelemetry.delayCs), so the ladder caps at 64.
        var finer: Rung? {
            switch self {
            case .fine: return nil
            case .mid: return .fine
            case .coarse: return .mid
            }
        }
    }

    /// ★ THE LADDER (OV3): DyadPalette's binomial shell half mirrored
    /// through the σ-involution (PT6) —
    /// 1,1,2,4,8,16,32,64,64,32,16,8,4,2,1,1. Sixteen shells, one per
    /// row of the rung-16 image, summing to the whole palette. The
    /// half is not restated here; it IS DyadPalette.ladder.
    static let ladder: [Int] = DyadPalette.ladder + DyadPalette.ladder.reversed()

    // MARK: - § 2. The field (the spec's flat (t, y, x) cube)

    /// One read: side³ OKLab cells, flat index t·side² + y·side + x —
    /// frame-major then row-major, the SAME order TriScaleLadder.rung64
    /// fills and DyadPipeline.pairDither indexes. The third axis is
    /// FRAME and κ cannot tell it from x or y (OV10).
    struct Field: Equatable, Sendable {
        let rung: Rung
        let cells: [OKLabColor]

        /// nil unless cells.count == rung.cellCount (the size half of
        /// OV4, structural).
        init?(rung: Rung, cells: [OKLabColor]) {
            guard cells.count == rung.cellCount else { return nil }
            self.rung = rung
            self.cells = cells
        }

        /// The count is right by construction at every internal call
        /// site (κ, σ and the blend all size their output from a Rung).
        fileprivate init(unchecked rung: Rung, cells: [OKLabColor]) {
            self.rung = rung
            self.cells = cells
        }

        var side: Int { rung.side }

        subscript(t: Int, y: Int, x: Int) -> OKLabColor {
            cells[(t * side + y) * side + x]
        }
    }

    // MARK: - § 3. κ and σ's structural half (OV4, OV12)

    /// κ — side n → n/2, each output cell the EXACT mean of its 2×2×2
    /// spacetime block, in OKLab. nil at the floor (OV2).
    ///
    /// SUMMATION ORDER IS PART OF THE CONTRACT: the eight children are
    /// summed as a BALANCED BINARY TREE ((a+b)+(c+d)) + ((e+f)+(g+h))
    /// and scaled by 0.125. Scaling by a power of two is exact in
    /// IEEE-754 and commutes with rounding, so this makes OV12 hold
    /// BIT-EXACTLY in Double (the one-shot mean of eight and three
    /// composed binary means round identically) and makes pool ∘ up
    /// the exact identity. A naive left-fold would not.
    static func pool(_ f: Field) -> Field? {
        guard let target = f.rung.coarser else { return nil }
        let n = f.side
        let h = target.side
        let plane = n * n
        let src = f.cells
        var out = [OKLabColor](repeating: vZero, count: target.cellCount)
        for tb in 0..<h {
            let t0 = (2 * tb) * plane
            let t1 = t0 + plane
            for yb in 0..<h {
                let y0 = (2 * yb) * n
                let y1 = y0 + n
                for xb in 0..<h {
                    let x0 = 2 * xb
                    // (dt, dy) row starts; each row contributes x0, x0 + 1.
                    let r00 = t0 + y0 + x0
                    let r01 = t0 + y1 + x0
                    let r10 = t1 + y0 + x0
                    let r11 = t1 + y1 + x0
                    let s00 = vAdd(src[r00], src[r00 + 1])
                    let s01 = vAdd(src[r01], src[r01 + 1])
                    let s10 = vAdd(src[r10], src[r10 + 1])
                    let s11 = vAdd(src[r11], src[r11 + 1])
                    let sum = vAdd(vAdd(s00, s01), vAdd(s10, s11))
                    out[(tb * h + yb) * h + xb] = vScale(0.125, sum)
                }
            }
        }
        return Field(unchecked: target, cells: out)
    }

    /// σ's structural half: replication, one cell → 2×2×2. nil at the
    /// ceiling. (The LEARNED half x ± g(x) lives in OctaveCodec and is
    /// out of scope here; OV5 holds for both — a normalised mixture of
    /// equal-mean fields has that mean whatever the expansion.)
    static func up(_ f: Field) -> Field? {
        guard let target = f.rung.finer else { return nil }
        let n = f.side
        let m = target.side
        let src = f.cells
        var out = [OKLabColor](repeating: vZero, count: target.cellCount)
        var w = 0
        for t in 0..<m {
            let ts = (t / 2) * n * n
            for y in 0..<m {
                let ys = ts + (y / 2) * n
                for x in 0..<m {
                    out[w] = src[ys + x / 2]
                    w += 1
                }
            }
        }
        return Field(unchecked: target, cells: out)
    }

    /// Lift a field to the fine rung by repeated replication. Total by
    /// construction: `up` stops exactly at the ceiling, which is .fine.
    static func liftToFine(_ f: Field) -> Field {
        var g = f
        while let lifted = up(g) { g = lifted }
        return g
    }

    /// Σ‖v‖² — the departure meter OV9 is stated in.
    static func energy(_ f: Field) -> Double {
        pairwiseSum(f.cells[...], vNorm2)
    }

    /// Σ|l| + |a| + |b| — the L1 mass the error bound is stated in.
    static func l1Mass(_ f: Field) -> Double {
        pairwiseSum(f.cells[...]) { abs($0.l) + abs($0.a) + abs($0.b) }
    }

    /// The field's exact mean (pairwise summation; every rung's cell
    /// count is a power of two, so the final division is exact).
    static func mean(_ f: Field) -> OKLabColor {
        pairwiseMean(f.cells[...])
    }

    /// Balanced binary tree sum. For a power-of-two count this is the
    /// same tree κ uses on its eight children, which is what makes
    /// OV12 bit-exact rather than merely close.
    static func pairwiseSum(_ v: ArraySlice<OKLabColor>) -> OKLabColor {
        let n = v.count
        if n == 0 { return vZero }
        if n == 1 { return v[v.startIndex] }
        let mid = v.startIndex + n / 2
        return vAdd(pairwiseSum(v[v.startIndex..<mid]), pairwiseSum(v[mid..<v.endIndex]))
    }

    /// The pairwise-summed mean of a slice. Exposed (internal) because
    /// OV12 is a claim about eight cells, not about a whole Field.
    static func pairwiseMean(_ v: ArraySlice<OKLabColor>) -> OKLabColor {
        guard !v.isEmpty else { return vZero }
        return vScale(1 / Double(v.count), pairwiseSum(v))
    }

    /// Scalar twin of the above, for the meters.
    private static func pairwiseSum(_ v: ArraySlice<OKLabColor>,
                                    _ term: (OKLabColor) -> Double) -> Double {
        let n = v.count
        if n == 0 { return 0 }
        if n == 1 { return term(v[v.startIndex]) }
        let mid = v.startIndex + n / 2
        return pairwiseSum(v[v.startIndex..<mid], term)
             + pairwiseSum(v[mid..<v.endIndex], term)
    }

    /// The flat field of a single colour, at the fine rung — the
    /// degenerate all-zero dial's output and OV9's reference field.
    static func flat(_ colour: OKLabColor) -> Field {
        Field(unchecked: .fine,
              cells: [OKLabColor](repeating: colour, count: Rung.fine.cellCount))
    }

    /// Cellwise difference, for OV9's departure meter. nil unless the
    /// two fields sit on the same rung.
    static func difference(_ f: Field, _ g: Field) -> Field? {
        guard f.rung == g.rung else { return nil }
        var out = [OKLabColor](repeating: vZero, count: f.cells.count)
        for i in 0..<f.cells.count { out[i] = vSub(f.cells[i], g.cells[i]) }
        return Field(unchecked: f.rung, cells: out)
    }

    // MARK: - § 4. The three parallel reads (OV13)

    /// The three streams, read from one feed at once. Constructible
    /// ONLY from a fine field and ONLY through κ — there is no
    /// initialiser that takes three independent fields, because three
    /// unrelated fields would not satisfy OV13.
    struct Reads: Sendable {
        let fine: Field
        let mid: Field
        let coarse: Field

        /// nil unless `fine.rung == .fine`.
        init?(fine: Field) {
            guard fine.rung == .fine,
                  let mid = OctaveRead.pool(fine),
                  let coarse = OctaveRead.pool(mid) else { return nil }
            self.fine = fine
            self.mid = mid
            self.coarse = coarse
        }
    }

    // MARK: - § 5. The dial (OV11) and the blend (OV5–OV9)

    /// A point of the simplex over the three reads. Values are clamped
    /// into 0 ..< stateCount at construction, so an out-of-grid dial
    /// cannot exist (OV11 — STRUCTURAL). Wired to NOTHING: no
    /// ExportSettings field, no SET cover control (ATLAS §7 step 5 is
    /// Daniel's ruling, and the SIMPLICITY decree forbids a surface
    /// without one).
    struct Dial: Equatable, Sendable {
        let coarse: Int, mid: Int, fine: Int

        init(coarse: Int, mid: Int, fine: Int) {
            func grid(_ w: Int) -> Int { min(max(0, w), Dial.stateCount - 1) }
            self.coarse = grid(coarse)
            self.mid = grid(mid)
            self.fine = grid(fine)
        }

        /// 8 — one state per ladder level = one per pair-tree
        /// generation plus the root (RoleAllocation widgetCells =
        /// treeDepth + 1, OV11). Derived from DyadPalette.ladder.count,
        /// never written as a literal.
        static var stateCount: Int { DyadPalette.ladder.count }

        /// (0, 0, 7): the fine read alone = today's bytes (OV6).
        static let identity = Dial(coarse: 0, mid: 0, fine: Dial.stateCount - 1)
    }

    /// The mixture: every read lifted to the fine rung and blended by
    /// NORMALISED weights (OV8 — convex, so one dial moves exactly one
    /// read). All-zero is lawful and degenerate: the flat field of the
    /// feed's mean (OV5). Always returns a `.fine` field.
    ///
    /// A pure setting is EXACT, not approximate: its own weight is the
    /// quotient w/w = 1.0 and the others are 0.0, so the sum reduces to
    /// the untouched lifted read (OV6, OV7). Equal settings are exact
    /// too: 1/3, 2/6 and 3/9 are the same correctly rounded Double, so
    /// scale-freedom is bit-exact (OV8).
    static func blend(_ dial: Dial, _ reads: Reads) -> Field {
        let total = Double(dial.coarse + dial.mid + dial.fine)
        guard total > 0 else { return flat(mean(reads.fine)) }
        let wC = Double(dial.coarse) / total
        let wM = Double(dial.mid) / total
        let wF = Double(dial.fine) / total
        let liftedCoarse = liftToFine(reads.coarse).cells
        let liftedMid = liftToFine(reads.mid).cells
        let fine = reads.fine.cells
        var out = [OKLabColor](repeating: vZero, count: fine.count)
        for i in 0..<fine.count {
            out[i] = vAdd(vAdd(vScale(wC, liftedCoarse[i]), vScale(wM, liftedMid[i])),
                          vScale(wF, fine[i]))
        }
        return Field(unchecked: .fine, cells: out)
    }

    // MARK: - § 6. Adapters (the only impure edge)

    /// A fine read from the burst's staged OKLab frames, frame-major.
    /// nil unless frames.count == 64 and every frame is 64×64.
    static func fineRead(frames: [[OKLabColor]]) -> Field? {
        let side = Rung.fine.side
        guard frames.count == side,
              frames.allSatisfy({ $0.count == side * side }) else { return nil }
        var cells = [OKLabColor]()
        cells.reserveCapacity(Rung.fine.cellCount)
        for frame in frames { cells.append(contentsOf: frame) }
        return Field(unchecked: .fine, cells: cells)
    }

    /// A fine read from raw captured frames, in delivery order. Colour
    /// conversion is DELEGATED, never re-implemented:
    /// DyadPipeline.srgb8(from:) then DyadPalette.oklab(fromSRGB8:) —
    /// the exact two calls the live read already makes. No γ-staging
    /// here: staging is the assignment law (DY9), not the read.
    static func fineRead(captured frames: [CapturedFrame]) -> Field? {
        let side = Rung.fine.side
        guard frames.count == side,
              frames.allSatisfy({ $0.rgb.count == side * side }) else { return nil }
        return fineRead(frames: frames.map { frame in
            frame.rgb.map { DyadPalette.oklab(fromSRGB8: DyadPipeline.srgb8(from: $0)) }
        })
    }

    // MARK: - § 7. Numerical law (★NO NAKED CONSTANTS)

    /// Forward error bound for a pairwise-summed mean of `count`
    /// values whose absolute values sum to `absSum`:
    ///   γ_k · absSum / count,  k = ⌈log₂ count⌉,  γ_k = k·u/(1 − k·u),
    ///   u = .ulpOfOne / 2
    /// (Higham, *Accuracy and Stability of Numerical Algorithms* 2nd
    /// ed., Thm 4.6 — pairwise summation.) Division by a power of two
    /// is exact, so the mean inherits the sum's bound scaled by 1/n.
    /// This is the ONLY tolerance the tests may use; a hand-picked
    /// epsilon is a defect.
    static func meanErrorBound(count: Int, absSum: Double) -> Double {
        guard count > 1 else { return 0 }
        // ⌈log₂ count⌉ by bit width — exact for every Int, no float log.
        let k = Double(Int.bitWidth - (count - 1).leadingZeroBitCount)
        let u = Double.ulpOfOne / 2
        let ku = k * u
        guard ku < 1 else { return .infinity }
        return (ku / (1 - ku)) * abs(absSum) / Double(count)
    }
}
