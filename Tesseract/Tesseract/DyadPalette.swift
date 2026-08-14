// DyadPalette.swift
// Tesseract
//
// DYAD-256: 256 colors that are really 128 colors and a group action.
//
//   σ(i) = 255 − i            the index involution
//   T[σ(i)] = comp(T[i])      the table law (byte-exact)
//   comp(L,a,b) = (L,−a,−b)   hue+180° in OKLab is negation
//
// Primaries 0..127 are allocated by the binomial ladder
// [1,1,2,4,8,16,32,64] over concentric PC1×PC2 shells of the
// face's OKLab distribution; the σ half 128..255 is generated,
// never designed. Face pixels quantize to primaries only; the
// background takes the σ-mirror of its own nearest primary.
//
// v5-W (THE WADA GROUND, 2026-08-10): the displayed σ half is the
// Wada ground, not the raw gamut-max complement — hue+180° (the
// tritone survives; assignment still searches comp = negation),
// chroma muted by the dictionary's power law, lightness shifted as
// an ensemble to the dictionary's ground level. Constants are
// moments of Sanzo Wada's "A Dictionary of Colour Combinations"
// (1933–34), derivation: scripts/wada/derive.py. Table law:
// T[σ(i)] = ground(centroidL: L(T[0]), of: T[i]) — byte-exact,
// verifiable from table bytes alone.
//
// ★ THE FOURTH COORDINATE (2026-08-13, Daniel on the first 17 Pro
// export: "the colors are still muddy"): the ground family now
// carries a HUE ROTATION fitted to the background's own pixels —
// spec/quantization/GroundHue.hs, axioms GH1–GH15. GH1 is the
// diagnosis: (mean L, mean lnC, sd lnC) are all invariant under
// rotation about the neutral axis, so the family could be told how
// light and how colourful the wall is but never WHAT COLOUR it is,
// and under v7 the σ half carried the FIGURE's hue set for every
// background ever photographed (measured R = 0.9913, circular sd
// 7.6°). See § 3c.
//
// Port of spec/quantization/DyadPalette.hs — the Haskell spec is
// authoritative (axioms DY1–DY15). Weighted statistics are the one
// extension: weights = the depth/face mask; uniform weights must
// reproduce the spec's unweighted analyze exactly.

import Foundation

/// OKLab triple, Double precision.
struct OKLabColor: Equatable, Sendable {
    var l: Double
    var a: Double
    var b: Double
}

enum DyadPalette {

    // MARK: - § 1. The ladder and the involution

    static let ladder: [Int] = [1, 1, 2, 4, 8, 16, 32, 64]
    static let levelCount = 8
    static let primaryCount = 128

    /// offsets[k] = first primary index of level k (9 entries, last = 128).
    static let offsets: [Int] = ladder.reduce(into: [0]) { acc, n in
        acc.append(acc.last! + n)
    }

    /// The index involution. Primaries 0..127 ↔ complements 255..128.
    static func partner(_ i: Int) -> Int { 255 - i }

    // MARK: - § 2. OKLab (Björn Ottosson's matrices)

    static func srgbToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func linearToSrgb(_ c: Double) -> Double {
        c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    static func oklab(fromSRGB8 rgb: (UInt8, UInt8, UInt8)) -> OKLabColor {
        let r = srgbToLinear(Double(rgb.0) / 255)
        let g = srgbToLinear(Double(rgb.1) / 255)
        let b = srgbToLinear(Double(rgb.2) / 255)
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let l3 = cbrt(l), m3 = cbrt(m), s3 = cbrt(s)
        return OKLabColor(
            l: 0.2104542553 * l3 + 0.7936177850 * m3 - 0.0040720468 * s3,
            a: 1.9779984951 * l3 - 2.4285922050 * m3 + 0.4505937099 * s3,
            b: 0.0259040371 * l3 + 0.7827717662 * m3 - 0.8086757660 * s3)
    }

    static func linearRGB(from lab: OKLabColor) -> (Double, Double, Double) {
        let l3 = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b
        let m3 = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b
        let s3 = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b
        let l = l3 * l3 * l3, m = m3 * m3 * m3, s = s3 * s3 * s3
        return (  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                 -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                 -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    static func inGamut(_ lab: OKLabColor) -> Bool {
        let (r, g, b) = linearRGB(from: lab)
        return r >= -1e-6 && r <= 1 + 1e-6
            && g >= -1e-6 && g <= 1 + 1e-6
            && b >= -1e-6 && b <= 1 + 1e-6
    }

    static func srgb8(from lab: OKLabColor) -> (UInt8, UInt8, UInt8) {
        let (r, g, b) = linearRGB(from: lab)
        // Round half-to-even to match GHC's `round` in the spec.
        func to8(_ c: Double) -> UInt8 {
            let v = (linearToSrgb(min(1, max(0, c))) * 255).rounded(.toNearestOrEven)
            return UInt8(min(255, max(0, v)))
        }
        return (to8(r), to8(g), to8(b))
    }

    // MARK: - § 3. Comp — hue+180° is negation; clamp scales chroma only

    static func comp(_ lab: OKLabColor) -> OKLabColor {
        OKLabColor(l: lab.l, a: -lab.a, b: -lab.b)
    }

    /// Largest s ∈ [0,1] with (L, s·a, s·b) in gamut, by 40-step bisection.
    /// s = 0 (the gray of the same L) is always in gamut for L ∈ [0,1].
    static func chromaClamp(_ lab: OKLabColor) -> OKLabColor {
        if inGamut(lab) { return lab }
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if inGamut(OKLabColor(l: lab.l, a: lab.a * mid, b: lab.b * mid)) {
                lo = mid
            } else {
                hi = mid
            }
        }
        return OKLabColor(l: lab.l, a: lab.a * lo, b: lab.b * lo)
    }

    static func clampL(_ lab: OKLabColor) -> OKLabColor {
        OKLabColor(l: min(1, max(0, lab.l)), a: lab.a, b: lab.b)
    }

    // MARK: - § 3b. The ground law (phase-palette step 3, ruling R2)
    //
    // The σ half is generated by the Wada FAMILY — hue rotation
    // (§ 3c), chroma power law, rigid L-shift — with parameters
    // MOMENT-MATCHED to the capture's own background class (four
    // moments now, still zero hyperparameters; spec: PhasePalette.hs
    // § 10, PP8 and GroundHue.hs GH3/GH4). The
    // Wada dictionary constants demote to the PRIOR used on the
    // single-phase (BIC) fallback path, where the identity cap
    // (ground ≤ figure chroma) also lives — the dictionary's ROLE
    // law, not the scene's.

    /// Mean ground lightness over the dictionary's 1128 pairs.
    static let wadaGroundL = 0.6170482164370319
    /// ln-chroma power law of figure → ground (r = +0.30).
    static let wadaAlphaC = -1.3176036044137163
    static let wadaBetaC = 0.7469411483195036

    // MARK: - § 3c. THE FOURTH COORDINATE — the ground's OWN hue
    //
    // Spec: spec/quantization/GroundHue.hs (GH1–GH15), Daniel's
    // ruling 2026-08-13. GH2 states the whole arc as ONE law:
    //
    //     R_table = R_figure · cos(|Δh| / 2)
    //
    // v5-W forced Δh = π (R_table = 0 whatever the scene — the blue
    // haze); v7 forced Δh = 0 (R_table = R_figure, i.e. exactly as
    // monochrome as a face is). Both are FORCED; only a fitted Δh
    // reports the scene. Wada leaves the hue interval free (|Δh|
    // near-uniform on [0°,180°] over the dictionary's 1128 pairs,
    // scripts/wada/derive.py:11) and the family WITH the rotation is
    // a group (GH3), so this is the coordinate the family already
    // carried — filled from evidence, not from a ruling.

    /// A hue rotation, carried as a DIRECTION in the (a,b) plane and
    /// never as an angle: GH5 — the 0/360 seam resolves exactly on
    /// vectors, while the naive mean of angle representatives comes
    /// out 180° wrong. GH6 — no square root is needed to state the
    /// law, because the chroma power law re-normalises afterwards;
    /// the unit representative is stored only so `rotate` is a pure
    /// rotation and the radial law below keeps reading the figure's
    /// own chroma.
    struct HueRotation: Equatable, Sendable {
        var a: Double
        var b: Double

        /// GH7's answer to every degenerate case (no background mass,
        /// no chromatic background mass, an achromatic figure): the
        /// identity — byte for byte the v7 / Wada-prior path.
        static let identity = HueRotation(a: 1, b: 0)

        /// Complex multiplication — rotation-and-scale (GroundHue § 1).
        func rotate(_ v: (a: Double, b: Double)) -> (a: Double, b: Double) {
            (a: v.a * a - v.b * b, b: v.a * b + v.b * a)
        }

        /// The unit representative of a direction; the zero vector
        /// (no chromatic evidence) resolves to the identity (GH7).
        static func direction(_ v: (a: Double, b: Double)) -> HueRotation {
            let m2 = v.a * v.a + v.b * v.b
            guard m2 > 0 else { return .identity }
            let m = m2.squareRoot()
            return HueRotation(a: v.a / m, b: v.b / m)
        }

        /// ★ THE LAW (GroundHue § 3, `groundRotation`): Δh takes the
        /// FIGURE's mean hue to the BACKGROUND's own mean hue, as the
        /// unnormalised complex product b · conj(f). Total: either
        /// resultant vanishing gives the identity.
        static func taking(figure f: (a: Double, b: Double),
                           to bg: (a: Double, b: Double)) -> HueRotation {
            direction((a: bg.a * f.a + bg.b * f.b,
                       b: bg.b * f.a - bg.a * f.b))
        }
    }

    /// ★ GH4: the chroma-weighted circular mean of hue IS the argument
    /// of Σ mᵢ·(aᵢ, bᵢ), because C·(cos h, sin h) is (a, b) by
    /// definition — the chroma weight is already inside the
    /// coordinates. So a circular mean costs two accumulators and no
    /// trigonometry. Mass-free ensembles resolve to the zero vector.
    static func chromaResultant(_ labs: [OKLabColor],
                                weights: [Double]? = nil) -> (a: Double, b: Double) {
        var ra = 0.0, rb = 0.0
        if let weights {
            for (lab, w) in zip(labs, weights) where w > 0 {
                ra += w * lab.a; rb += w * lab.b
            }
        } else {
            for lab in labs { ra += lab.a; rb += lab.b }
        }
        return (ra, rb)
    }

    /// The four fitted parameters of the ground family (GH3: the
    /// family is a group — rigid L-shift × ln-chroma affine × hue
    /// rotation — and `rot` is its fourth coordinate).
    struct GroundMoments: Equatable, Sendable {
        var deltaL: Double   // rigid L-shift (background mean L − centroid L)
        var alphaC: Double   // ln-chroma intercept
        var betaC: Double    // ln-chroma slope
        var capped: Bool     // identity cap engaged (prior path only)
        /// ★ Δh — the background's own hue, as a direction. Defaults
        /// to the identity so every prior/legacy construction is the
        /// v7 path exactly (GH7/GH8). Recorded for provenance on the
        /// balanced path, where it cannot be applied (WB4).
        var rot: HueRotation = .identity
        /// ★ WHITE BALANCE (WhiteBalance.hs, 2026-08-14). true ⇒ the
        /// ground is the partner about NEUTRAL, so the table's net
        /// cast is exactly zero. Defaults FALSE so a legacy trace
        /// rebuilds under the law it was recorded with — every
        /// capture from before this date regenerates byte for byte.
        var balanced: Bool = false
    }

    /// Single-phase / thin-background fallback: the dictionary prior.
    /// The prior is hue-free by construction (Wada constrains the
    /// ROLE, not the interval), so it takes the identity rotation —
    /// the degenerate case keeps being covered by the same law that
    /// covers it today.
    static func priorMoments(centroidL cL: Double) -> GroundMoments {
        GroundMoments(deltaL: wadaGroundL - cL,
                      alphaC: wadaAlphaC, betaC: wadaBetaC, capped: true,
                      rot: .identity, balanced: false)
    }

    /// The background evidence the ground family reads: v5-W's three
    /// scalars plus ★ GH4's resultant. `hueA/hueB` is the background's
    /// own chroma-weighted circular mean hue, stored as a unit
    /// direction; (0, 0) means NO chromatic background evidence, which
    /// GH7 resolves to the identity rotation downstream. Smoothers may
    /// carry it unnormalised — GH6, only the direction is read.
    struct BackgroundMoments: Equatable, Sendable {
        var meanL: Double
        var meanLnC: Double
        var sdLnC: Double
        var hueA: Double
        var hueB: Double

        var hue: (a: Double, b: Double) { (hueA, hueB) }
    }

    /// Weighted background moments of an ensemble: (mean L, mean lnC,
    /// sd lnC) with the chroma moments over chromatic mass only, plus
    /// the chroma-weighted hue resultant (GH4 — two accumulators in
    /// the loop that was already running; the chroma weighting is
    /// free because it is already in (a, b)).
    /// nil when the weighted mass (or chromatic mass) vanishes —
    /// callers fall back to the prior (PP8's two-path law).
    static func backgroundMoments(
        labs: [OKLabColor], weights: [Double]
    ) -> BackgroundMoments? {
        var wTot = 0.0, lSum = 0.0
        var wC = 0.0, cSum = 0.0, c2Sum = 0.0
        var ra = 0.0, rb = 0.0
        for (lab, w) in zip(labs, weights) where w > 0 {
            wTot += w
            lSum += w * lab.l
            let c2 = lab.a * lab.a + lab.b * lab.b
            if c2 > 0 {
                let lnC = log(c2.squareRoot())
                wC += w
                cSum += w * lnC
                c2Sum += w * lnC * lnC
                ra += w * lab.a; rb += w * lab.b
            }
        }
        guard wTot > 0, wC > 0 else { return nil }
        let mean = cSum / wC
        let varC = max(0, c2Sum / wC - mean * mean)
        // The resultant's DIRECTION is the law (GH6); its magnitude
        // is mass × chroma and is deliberately dropped here so that
        // smoothing blends directions, not masses (GH13).
        let dir = HueRotation.direction((ra, rb))
        let chromatic = ra * ra + rb * rb > 0
        return BackgroundMoments(meanL: lSum / wTot, meanLnC: mean,
                                 sdLnC: varC.squareRoot(),
                                 hueA: chromatic ? dir.a : 0,
                                 hueB: chromatic ? dir.b : 0)
    }

    /// The scene fit (PP8): combine the primaries' own ln-chroma
    /// moments with the background's — βC = sd ratio, αC from means,
    /// ΔL from the background mean. Degenerate primary spread keeps
    /// the prior slope (pure function either way).
    /// ★ GH4/GH9: the fourth coordinate is fitted from the SAME two
    /// ensembles — Δh takes the primaries' own chroma-weighted mean
    /// hue to the background's, so the emitted σ half's mean hue IS
    /// the background's mean hue (and the primaries are exactly the
    /// figure evidence αC/βC already read; one source, four
    /// coordinates).
    static func groundMoments(
        centroidL cL: Double,
        primsLab: [OKLabColor],
        background: BackgroundMoments
    ) -> GroundMoments {
        var n = 0.0, sum = 0.0, sum2 = 0.0
        for lab in primsLab {
            let c2 = lab.a * lab.a + lab.b * lab.b
            guard c2 > 0 else { continue }
            let lnC = log(c2.squareRoot())
            n += 1; sum += lnC; sum2 += lnC * lnC
        }
        let sdP: Double = n > 0 ? max(0, sum2 / n - (sum / n) * (sum / n)).squareRoot() : 0
        let beta = sdP > 0 ? background.sdLnC / sdP : wadaBetaC
        let alpha = background.meanLnC - beta * (n > 0 ? sum / n : 0)
        return GroundMoments(deltaL: background.meanL - cL,
                             alphaC: alpha, betaC: beta, capped: false,
                             rot: HueRotation.taking(
                                figure: chromaResultant(primsLab),
                                to: background.hue),
                             balanced: true)
    }

    /// The ground law in OKLab under fitted (or prior) moments.
    /// Achromatic figures keep achromatic grounds exactly, at the
    /// shifted L; the cap applies on the prior path only.
    /// v7 (Daniel's ruling, 2026-08-12): the ground does not NEGATE
    /// its figure's hue — the old negation made the whole σ half the
    /// complement of the face's shells, painting every background
    /// blue-gray under a warm subject (the blue haze). Spec DY14.
    /// ★ THE FOURTH COORDINATE (GroundHue, 2026-08-13): it does not
    /// keep the figure's hue either — it rotates by the fitted Δh, so
    /// the wall is painted in the WALL's own hue. Δh = identity
    /// reproduces v7 byte for byte (GH8), which is what the prior
    /// path and every degenerate case take. Rotation commutes with
    /// the radial chroma law and |rot| = 1, so the emitted chroma is
    /// exactly the chroma the power law asked for (GH10).
    static func groundLab(_ gm: GroundMoments, _ lab: OKLabColor) -> OKLabColor {
        guard gm.balanced else { return groundLabV7(gm, lab) }
        // ★ WHITE BALANCE (Daniel's demand, 2026-08-14; spec
        // quantization/WhiteBalance.hs WB3/WB4/WB5).
        //
        // The partner about NEUTRAL, exactly: (a, b) -> (-a, -b).
        //
        // WB4 is why nothing else will do. For any table where every
        // entry has a partner x' = 2c - x, the mean of all 256 entries
        // is EXACTLY c — the free entries cancel out of the sum
        // identically, so they are irrelevant to the cast. The net
        // cast IS the mirror centre. The device measured this
        // directly: mirroring about c_F (the FIGURE centroid, i.e. a
        // face) gave |net cast| / mean chroma = 0.986. White balance
        // therefore has exactly ONE solution, c = 0, and any scaling
        // or rotation other than exact negation reopens the cast.
        //
        // So the chroma power law (alphaC/betaC) and the fitted Δh
        // rotation cannot apply on this path: both change |ab| or its
        // direction, and either breaks the cancellation. They remain
        // on the record in GroundMoments for provenance and for the
        // v7 rebuild path below.
        //
        // LIGHTNESS IS FREE (WB11): the mirror is a CHROMA involution,
        // so deltaL still separates ground from figure and costs the
        // balance nothing.
        return OKLabColor(l: lab.l + gm.deltaL, a: -lab.a, b: -lab.b)
    }

    /// The pre-2026-08-14 ground: L-shift, chroma power law, fitted Δh
    /// rotation. Kept verbatim so a legacy trace still rebuilds byte
    /// for byte — DYAD STATS provenance is a contract, and a capture
    /// recorded under v7 must not silently regenerate under a
    /// different law.
    static func groundLabV7(_ gm: GroundMoments, _ lab: OKLabColor) -> OKLabColor {
        let c2 = lab.a * lab.a + lab.b * lab.b
        let l = lab.l + gm.deltaL
        guard c2 > 0 else { return OKLabColor(l: l, a: 0, b: 0) }
        let c = c2.squareRoot()
        let cRaw = exp(gm.alphaC + gm.betaC * log(c))
        let cG = gm.capped ? min(c, cRaw) : cRaw
        let s = cG / c
        let r = gm.rot.rotate((a: lab.a, b: lab.b))
        return OKLabColor(l: l, a: r.a * s, b: r.b * s)
    }

    /// The generation law for the σ half, byte to byte.
    static func ground(_ gm: GroundMoments, of rgb: (UInt8, UInt8, UInt8)) -> (UInt8, UInt8, UInt8) {
        srgb8(from: chromaClamp(clampL(groundLab(gm, oklab(fromSRGB8: rgb)))))
    }

    /// Prior-path shim (v5-W law, byte-identical): the σ half from
    /// the dictionary constants anchored at the byte centroid T[0].
    static func ground(centroidL cL: Double, of rgb: (UInt8, UInt8, UInt8)) -> (UInt8, UInt8, UInt8) {
        ground(priorMoments(centroidL: cL), of: rgb)
    }

    /// Figure-centroid lightness of a primary list or full table:
    /// L of the first entry, which IS the centroid (level 0).
    static func centroidL(_ table: [(UInt8, UInt8, UInt8)]) -> Double {
        oklab(fromSRGB8: table[0]).l
    }

    // MARK: - § 4. Statistics — centroid, covariance, Jacobi PCA

    struct PrincipalComponent: Sendable {
        var direction: (Double, Double, Double)
        var variance: Double
    }

    struct Stats: Sendable {
        var centroid: OKLabColor
        var covariance: [[Double]]           // 3×3, OKLab
        var pcs: [PrincipalComponent]        // sorted by decreasing variance
    }

    /// Sign canonicalization (spec DY8, the deterministic flicker law):
    /// an eigenvector's sign is arbitrary, and a flip relocates the
    /// level-1 shell point and permutes ring indices — palette churn
    /// with no visual cause. Canonical form: the first component with
    /// magnitude above eps is POSITIVE.
    static func canonDir(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
        let eps = 1e-9
        let flip: Bool
        if abs(v.0) > eps { flip = v.0 < 0 }
        else if abs(v.1) > eps { flip = v.1 < 0 }
        else { flip = v.2 < 0 }
        return flip ? (-v.0, -v.1, -v.2) : v
    }

    static func makeStats(centroid: OKLabColor, covariance: [[Double]]) -> Stats {
        let (values, vectors) = jacobi3(covariance)
        let order = [0, 1, 2].sorted { values[$0] > values[$1] }
        let pcs = order.map {
            PrincipalComponent(direction: canonDir(vectors[$0]), variance: values[$0])
        }
        return Stats(centroid: centroid, covariance: covariance, pcs: pcs)
    }

    /// TOTAL: no mass yields the mid-gray distribution. Weights are the
    /// depth/face mask; uniform weights reproduce unweighted analyze.
    static func analyze(
        _ samples: [(UInt8, UInt8, UInt8)],
        weights: [Double]? = nil
    ) -> Stats {
        let zero = [[0.0, 0, 0], [0, 0, 0], [0, 0, 0]]
        let w = weights ?? [Double](repeating: 1, count: samples.count)
        precondition(w.count == samples.count, "weights must match samples")
        let labs = samples.map { oklab(fromSRGB8: $0) }
        var totalW = 0.0
        var cl = 0.0, ca = 0.0, cb = 0.0
        for (lab, wi) in zip(labs, w) where wi > 0 {
            totalW += wi
            cl += wi * lab.l; ca += wi * lab.a; cb += wi * lab.b
        }
        guard totalW > 0 else {
            return makeStats(centroid: OKLabColor(l: 0.5, a: 0, b: 0), covariance: zero)
        }
        let centroid = OKLabColor(l: cl / totalW, a: ca / totalW, b: cb / totalW)
        var cov = zero
        for (lab, wi) in zip(labs, w) where wi > 0 {
            let d = [lab.l - centroid.l, lab.a - centroid.a, lab.b - centroid.b]
            for i in 0..<3 {
                for j in 0..<3 {
                    cov[i][j] += wi * d[i] * d[j]
                }
            }
        }
        for i in 0..<3 { for j in 0..<3 { cov[i][j] /= totalW } }
        return makeStats(centroid: centroid, covariance: cov)
    }

    /// Warm start: EMA on the STATISTICS, not on colors. The blend
    /// re-derives its PCA, so the shell sampler stays a deterministic
    /// function of (centroid, covariance) — no cluster-permutation flicker.
    static func ema(alpha: Double, _ s1: Stats, _ s2: Stats) -> Stats {
        func lerp(_ x: Double, _ y: Double) -> Double { alpha * x + (1 - alpha) * y }
        let c = OKLabColor(
            l: lerp(s1.centroid.l, s2.centroid.l),
            a: lerp(s1.centroid.a, s2.centroid.a),
            b: lerp(s1.centroid.b, s2.centroid.b))
        let cov = (0..<3).map { i in
            (0..<3).map { j in lerp(s1.covariance[i][j], s2.covariance[i][j]) }
        }
        return makeStats(centroid: c, covariance: cov)
    }

    static func guardedStd(_ variance: Double) -> Double {
        max(1e-3, (max(0, variance)).squareRoot())
    }

    /// Jacobi eigendecomposition for symmetric 3×3.
    /// Returns (eigenvalues, eigenvectors), unsorted.
    static func jacobi3(_ mat: [[Double]]) -> ([Double], [(Double, Double, Double)]) {
        var a = mat
        var v = [[1.0, 0, 0], [0, 1, 0], [0, 0, 1]]
        for _ in 0..<50 {
            // Largest |off-diagonal|; ties pick the later pair (spec order).
            var mx = -1.0, p = 0, q = 1
            for i in 0..<3 {
                for j in (i + 1)..<3 where abs(a[i][j]) >= mx {
                    mx = abs(a[i][j]); p = i; q = j
                }
            }
            if mx < 1e-12 { break }
            let theta: Double = abs(a[p][p] - a[q][q]) < 1e-15
                ? .pi / 4
                : 0.5 * atan(2 * a[p][q] / (a[p][p] - a[q][q]))
            let sn = sin(theta), cs = cos(theta)
            let app = cs * cs * a[p][p] + 2 * sn * cs * a[p][q] + sn * sn * a[q][q]
            let aqq = sn * sn * a[p][p] - 2 * sn * cs * a[p][q] + cs * cs * a[q][q]
            var newA = a
            newA[p][p] = app
            newA[q][q] = aqq
            newA[p][q] = 0
            newA[q][p] = 0
            for r in 0..<3 where r != p && r != q {
                let arp = cs * a[r][p] + sn * a[r][q]
                let arq = -sn * a[r][p] + cs * a[r][q]
                newA[r][p] = arp; newA[p][r] = arp
                newA[r][q] = arq; newA[q][r] = arq
            }
            a = newA
            var newV = v
            for r in 0..<3 {
                newV[r][p] = cs * v[r][p] + sn * v[r][q]
                newV[r][q] = -sn * v[r][p] + cs * v[r][q]
            }
            v = newV
        }
        let values = [a[0][0], a[1][1], a[2][2]]
        let vectors = (0..<3).map { (v[0][$0], v[1][$0], v[2][$0]) }
        return (values, vectors)
    }

    // MARK: - § 5. The solver — polar binomial shells → 256-entry table

    /// Shell radius in standard deviations: 0, 2/7, 4/7, …, 2.
    static func rho(_ k: Int) -> Double {
        2 * Double(k) / Double(levelCount - 1)
    }

    /// Level k, BEFORE clamping: ladder[k] points on the ellipse of
    /// radius ρ_k in the PC1×PC2 plane, angles 2πj/n. One formula for
    /// every level — ρ_0 = 0 makes level 0 the centroid.
    static func shellRaw(stats: Stats, level k: Int) -> [OKLabColor] {
        let n = ladder[k]
        let c = stats.centroid
        let d1 = stats.pcs[0].direction
        let d2 = stats.pcs[1].direction
        let g1 = guardedStd(stats.pcs[0].variance)
        let g2 = guardedStd(stats.pcs[1].variance)
        let r = rho(k)
        return (0..<n).map { j in
            let th = 2 * .pi * Double(j) / Double(n)
            let u = r * cos(th) * g1
            let w = r * sin(th) * g2
            return OKLabColor(
                l: c.l + u * d1.0 + w * d2.0,
                a: c.a + u * d1.1 + w * d2.1,
                b: c.b + u * d1.2 + w * d2.2)
        }
    }

    /// 128 primaries in table order: level k occupies indices
    /// [offsets[k] ..< offsets[k] + ladder[k]].
    static func primaries(stats: Stats) -> [(UInt8, UInt8, UInt8)] {
        (0..<levelCount).flatMap { k in
            shellRaw(stats: stats, level: k).map { srgb8(from: chromaClamp(clampL($0))) }
        }
    }

    /// The full DYAD table under fitted moments:
    /// T[255−i] = ground(moments, of: T[i]).
    static func table(stats: Stats, moments: GroundMoments) -> [(UInt8, UInt8, UInt8)] {
        let prims = primaries(stats: stats)
        return prims + prims.reversed().map { ground(moments, of: $0) }
    }

    /// Prior-path table (single-phase fallback, fixtures, v1 traces):
    /// byte-identical to the v5-W law.
    static func table(stats: Stats) -> [(UInt8, UInt8, UInt8)] {
        let prims = primaries(stats: stats)
        return table(stats: stats, moments: priorMoments(centroidL: centroidL(prims)))
    }

    /// GIF color table bytes: 768 = 256 × RGB. Valid as a Local Color
    /// Table (size bits 7) or Global Color Table.
    static func gifColorTable(_ table: [(UInt8, UInt8, UInt8)]) -> Data {
        var data = Data(capacity: 768)
        for (r, g, b) in table { data.append(r); data.append(g); data.append(b) }
        return data
    }

    // MARK: - § 6. Roles — face → primaries only; background → 255

    static let backgroundIndex = 255

    static func dLab2(_ x: OKLabColor, _ y: OKLabColor) -> Double {
        let dl = x.l - y.l, da = x.a - y.a, db = x.b - y.b
        return dl * dl + da * da + db * db
    }

    /// Nearest primary in OKLab; tie rule: LOWEST index wins.
    static func nearestPrimary(
        table: [(UInt8, UInt8, UInt8)],
        to color: (UInt8, UInt8, UInt8)
    ) -> Int {
        let lc = oklab(fromSRGB8: color)
        var best = 0
        var bestD = Double.infinity
        for j in 0..<primaryCount {
            let d = dLab2(oklab(fromSRGB8: table[j]), lc)
            if d < bestD { bestD = d; best = j }
        }
        return best
    }

    static func quantize(
        table: [(UInt8, UInt8, UInt8)],
        isFace: Bool,
        color: (UInt8, UInt8, UInt8)
    ) -> Int {
        isFace ? nearestPrimary(table: table, to: color) : backgroundIndex
    }
}
