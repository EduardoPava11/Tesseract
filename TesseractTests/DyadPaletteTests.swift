// DyadPaletteTests.swift
// Tesseract
//
// Pure-logic tests for DYAD-256 — Swift mirrors of the authoritative
// Haskell axioms DY1–DY7 (spec/quantization/DyadPalette.hs), plus the
// Swift-only laws: weighted statistics with uniform weights reduce to
// the spec's unweighted analyze, and the GIF color table is 768 bytes.
// No camera, no Metal.

import XCTest
@testable import Tesseract

final class DyadPaletteTests: XCTestCase {

    // MARK: - Deterministic inputs (the spec's LCG, no randomness)

    private static func lcg(_ s: Int) -> Int {
        (1103515245 * s + 12345) % 2147483648
    }

    private static func uniforms(_ seed: Int, _ n: Int) -> [Double] {
        var s = seed
        return (0..<n).map { _ in
            s = lcg(s)
            return Double(s) / 2147483648.0
        }
    }

    /// Skin-tone-like samples (the spec's synthetic face distribution).
    private static func skinColors(seed: Int, count: Int) -> [(UInt8, UInt8, UInt8)] {
        let us = uniforms(seed, count * 3)
        func mk(_ mu: Double, _ range: Double, _ u: Double) -> UInt8 {
            UInt8(min(255, max(0, (mu + (u - 0.5) * range).rounded(.toNearestOrEven))))
        }
        return (0..<count).map { i in
            (mk(180, 80, us[3 * i]), mk(140, 60, us[3 * i + 1]), mk(110, 50, us[3 * i + 2]))
        }
    }

    private static func randColors(seed: Int, count: Int) -> [(UInt8, UInt8, UInt8)] {
        let us = uniforms(seed, count * 3)
        func to8(_ u: Double) -> UInt8 { UInt8(min(255, Int(u * 256))) }
        return (0..<count).map { i in
            (to8(us[3 * i]), to8(us[3 * i + 1]), to8(us[3 * i + 2]))
        }
    }

    /// The constructor must be lawful on ALL of these (spec §7).
    private static let sampleSets: [[(UInt8, UInt8, UInt8)]] = {
        var sets: [[(UInt8, UInt8, UInt8)]] = [
            [],                                                    // fully synthetic
            Array(repeating: (128, 128, 128), count: 40),          // collapsed gray
            Array(repeating: (0, 0, 0), count: 40),                // all black
            Array(repeating: (255, 255, 255), count: 40),          // all white
        ]
        sets += (1...8).map { skinColors(seed: $0, count: 324) }
        sets += (20...22).map { randColors(seed: $0, count: 324) }
        return sets
    }()

    private static let allTables: [[(UInt8, UInt8, UInt8)]] =
        sampleSets.map { DyadPalette.table(stats: DyadPalette.analyze($0)) }

    // MARK: - DY1: the ladder and the involution

    func testLadderConservation() {
        XCTAssertEqual(DyadPalette.ladder.reduce(0, +), DyadPalette.primaryCount)
        XCTAssertEqual(DyadPalette.ladder.count, DyadPalette.levelCount)
        XCTAssertEqual(Array(DyadPalette.ladder.prefix(2)), [1, 1])
        for k in 2..<DyadPalette.levelCount {
            XCTAssertEqual(DyadPalette.ladder[k], 2 * DyadPalette.ladder[k - 1],
                           "ladder must double from level 1 on")
        }
        XCTAssertEqual(DyadPalette.offsets.last, DyadPalette.primaryCount)
    }

    func testPartnerInvolution() {
        for i in 0...255 {
            XCTAssertEqual(DyadPalette.partner(DyadPalette.partner(i)), i)
        }
        for i in 0..<128 {
            XCTAssertTrue((128...255).contains(DyadPalette.partner(i)))
        }
    }

    // MARK: - DY2: the table law (Wada ground), byte-exact, on every table

    func testGroundLawByteExact() {
        for table in Self.allTables {
            XCTAssertEqual(table.count, 256)
            let cL = DyadPalette.centroidL(table)
            for i in 0..<128 {
                let generated = table[DyadPalette.partner(i)]
                let recomputed = DyadPalette.ground(centroidL: cL, of: table[i])
                XCTAssertTrue(generated == recomputed,
                              "T[\(DyadPalette.partner(i))] must equal ground(T[\(i)])")
            }
        }
    }

    func testBackgroundIsGroundOfCentroid() {
        for table in Self.allTables {
            let cL = DyadPalette.centroidL(table)
            XCTAssertTrue(table[255] == DyadPalette.ground(centroidL: cL, of: table[0]))
            // DY15 (prior path): the centroid's ground lands at the
            // dictionary's ground lightness, whatever the face's key.
            let landed = DyadPalette.groundLab(DyadPalette.priorMoments(centroidL: cL),
                                               DyadPalette.oklab(fromSRGB8: table[0])).l
            XCTAssertEqual(landed, DyadPalette.wadaGroundL, accuracy: 1e-12)
        }
    }

    // MARK: - DY3: comp preserves L exactly, flips hue exactly

    func testCompPreservesLAndFlipsHue() {
        let probes = Self.sampleSets.flatMap { $0 } + Self.randColors(seed: 30, count: 200)
        for c in probes {
            let lab = DyadPalette.oklab(fromSRGB8: c)
            let flipped = DyadPalette.chromaClamp(DyadPalette.comp(lab))
            XCTAssertEqual(flipped.l, lab.l, "comp and clamp must never move L")
            let chroma2 = lab.a * lab.a + lab.b * lab.b
            if chroma2 < 1e-12 { continue }             // achromatic: comp = id
            let dot = flipped.a * lab.a + flipped.b * lab.b
            let cross = flipped.a * lab.b - flipped.b * lab.a
            let chroma2f = flipped.a * flipped.a + flipped.b * flipped.b
            XCTAssertLessThanOrEqual(dot, 0, "flipped chroma must oppose the original")
            XCTAssertLessThanOrEqual(abs(cross), 1e-9, "clamp must not rotate hue")
            XCTAssertLessThanOrEqual(chroma2f, chroma2 + 1e-12, "clamp must not grow chroma")
        }
    }

    func testDoubleCompIsIdentity() {
        for c in Self.skinColors(seed: 3, count: 50) {
            let lab = DyadPalette.oklab(fromSRGB8: c)
            XCTAssertEqual(DyadPalette.comp(DyadPalette.comp(lab)), lab)
        }
    }

    // MARK: - DY4: shell sizes and whitened residency

    func testShellSizesAndResidency() {
        for samples in Self.sampleSets {
            let stats = DyadPalette.analyze(samples)
            for k in 0..<DyadPalette.levelCount {
                let shell = DyadPalette.shellRaw(stats: stats, level: k)
                XCTAssertEqual(shell.count, DyadPalette.ladder[k])
                for p in shell {
                    let (u, v, w) = whiten(stats: stats, p)
                    XCTAssertEqual((u * u + v * v).squareRoot(), DyadPalette.rho(k),
                                   accuracy: 1e-6, "level \(k) point off its shell radius")
                    XCTAssertEqual(w, 0, accuracy: 1e-6, "shell points must have no PC3 part")
                }
            }
        }
    }

    private func whiten(stats: DyadPalette.Stats, _ p: OKLabColor) -> (Double, Double, Double) {
        let c = stats.centroid
        let d = (p.l - c.l, p.a - c.a, p.b - c.b)
        func proj(_ pc: DyadPalette.PrincipalComponent) -> Double {
            let dir = pc.direction
            let dot = dir.0 * d.0 + dir.1 * d.1 + dir.2 * d.2
            return dot / DyadPalette.guardedStd(pc.variance)
        }
        return (proj(stats.pcs[0]), proj(stats.pcs[1]), proj(stats.pcs[2]))
    }

    // MARK: - DY5: totality and determinism

    func testTotalityAndDeterminism() {
        for samples in Self.sampleSets {
            let a = DyadPalette.table(stats: DyadPalette.analyze(samples))
            let b = DyadPalette.table(stats: DyadPalette.analyze(samples))
            XCTAssertEqual(a.count, 256)
            XCTAssertTrue(zip(a, b).allSatisfy { $0 == $1 },
                          "same samples must build the same table")
        }
    }

    // MARK: - DY6: the role law

    func testFaceQuantizesToPrimariesOnly() {
        let table = DyadPalette.table(stats: DyadPalette.analyze(Self.skinColors(seed: 1, count: 324)))
        for c in Self.skinColors(seed: 2, count: 100) {
            let idx = DyadPalette.quantize(table: table, isFace: true, color: c)
            XCTAssertLessThan(idx, DyadPalette.primaryCount)
        }
        for c in Self.randColors(seed: 31, count: 100) {
            XCTAssertEqual(DyadPalette.quantize(table: table, isFace: false, color: c),
                           DyadPalette.backgroundIndex)
        }
    }

    // MARK: - DY7: EMA warm start

    func testEMAConvexityAndPSD() {
        let s1 = DyadPalette.analyze(Self.skinColors(seed: 1, count: 324))
        let s2 = DyadPalette.analyze(Self.skinColors(seed: 5, count: 324))
        for alpha in [0.0, 0.25, 0.5, 0.9, 1.0] {
            let blend = DyadPalette.ema(alpha: alpha, s1, s2)
            XCTAssertEqual(blend.centroid.l,
                           alpha * s1.centroid.l + (1 - alpha) * s2.centroid.l)
            XCTAssertEqual(blend.centroid.a,
                           alpha * s1.centroid.a + (1 - alpha) * s2.centroid.a)
            XCTAssertEqual(blend.centroid.b,
                           alpha * s1.centroid.b + (1 - alpha) * s2.centroid.b)
            let (values, _) = DyadPalette.jacobi3(blend.covariance)
            for v in values {
                XCTAssertGreaterThanOrEqual(v, -1e-9, "blended covariance must stay PSD")
            }
            // A blended distribution must still build a lawful table.
            let table = DyadPalette.table(stats: blend)
            XCTAssertEqual(table.count, 256)
            let cL = DyadPalette.centroidL(table)
            for i in 0..<128 {
                XCTAssertTrue(table[255 - i] == DyadPalette.ground(centroidL: cL, of: table[i]))
            }
        }
    }

    // MARK: - DY8: canonical PCA signs (the deterministic flicker law)

    func testCanonicalPCASigns() {
        func firstSignificantIsPositive(_ v: (Double, Double, Double)) -> Bool {
            if abs(v.0) > 1e-9 { return v.0 > 0 }
            if abs(v.1) > 1e-9 { return v.1 > 0 }
            return v.2 >= 0
        }
        for samples in Self.sampleSets {
            let stats = DyadPalette.analyze(samples)
            for pc in stats.pcs {
                XCTAssertTrue(firstSignificantIsPositive(pc.direction),
                              "principal directions must be sign-canonical (DY8)")
            }
        }
        // canonDir is flip-invariant and idempotent.
        let v = (-0.3, 0.5, -0.8)
        let c = DyadPalette.canonDir(v)
        XCTAssertTrue(DyadPalette.canonDir((-v.0, -v.1, -v.2)) == c)
        XCTAssertTrue(DyadPalette.canonDir(c) == c)
    }

    // MARK: - GroundHue: the fourth coordinate (spec GH1–GH11)

    /// A synthetic scene: a warm FIGURE (the face's hue wedge) and a
    /// wall at a genuinely different hue. Both are built in OKLab and
    /// round-tripped through sRGB8, so the test sees the same bytes
    /// the pipeline does.
    private static func labs(hue: Double, chroma: Double,
                             l: Double, count: Int, spread: Double) -> [OKLabColor] {
        (0..<count).map { i in
            // A wedge, not a point: hue ± spread, so the resultant is
            // a real circular mean and not a single sample.
            let h = hue + spread * (Double(i % 3) - 1)
            let c = chroma * (0.7 + 0.3 * Double((i % 5)) / 4)
            return OKLabColor(l: l, a: c * cos(h), b: c * sin(h))
        }
    }

    private static func hueOf(_ v: (a: Double, b: Double)) -> Double {
        atan2(v.b, v.a)
    }

    /// Angular difference in (−π, π] — for ASSERTIONS only; the law
    /// itself never represents a hue as a number (GH5).
    private static func angleGap(_ x: Double, _ y: Double) -> Double {
        atan2(sin(x - y), cos(x - y))
    }

    /// The σ half's own chroma-weighted mean hue, read off the table
    /// bytes — the quantity the shipped GIF was measured with.
    private static func sigmaHalfHue(_ table: [(UInt8, UInt8, UInt8)]) -> Double {
        var ra = 0.0, rb = 0.0
        for i in 128..<256 {
            let lab = DyadPalette.oklab(fromSRGB8: table[i])
            ra += lab.a; rb += lab.b
        }
        return hueOf((ra, rb))
    }

    /// ★ GH9 — THE POINT: the ground's hue is the BACKGROUND's own,
    /// not the figure's. Under v7 (identity rotation) the σ half
    /// carried the figure's mean hue for every background whatsoever
    /// (GH1, the diagnosis); with the fourth coordinate fitted, the
    /// emitted σ half lands on the wall's mean hue instead.
    func testGroundHueTracksTheBackgroundNotTheFigure() {
        let wallHue = 2.4                       // rad — a cool wall
        let figure = Self.labs(hue: 0.55, chroma: 0.06, l: 0.62,
                               count: 128, spread: 0.12)
        let wall = Self.labs(hue: wallHue, chroma: 0.05, l: 0.55,
                             count: 300, spread: 0.15)
        let bg = try! XCTUnwrap(DyadPalette.backgroundMoments(
            labs: wall, weights: [Double](repeating: 1, count: wall.count)))

        // GH4: the fitted direction IS the wall's chroma-weighted
        // circular mean hue.
        let wallMean = Self.hueOf(DyadPalette.chromaResultant(wall))
        XCTAssertEqual(abs(Self.angleGap(Self.hueOf(bg.hue), wallMean)), 0,
                       accuracy: 1e-12, "GH4: the resultant IS the circular mean")

        let figureMean = Self.hueOf(DyadPalette.chromaResultant(figure))
        let gm = DyadPalette.groundMoments(centroidL: 0.62, primsLab: figure,
                                           background: bg)
        XCTAssertNotEqual(gm.rot, .identity)

        // The ground of every figure entry lands on the WALL's hue…
        for lab in figure {
            let g = DyadPalette.groundLab(gm, lab)
            let gap = Self.angleGap(Self.hueOf((g.a, g.b)),
                                    Self.hueOf((lab.a, lab.b)) - figureMean + wallMean)
            XCTAssertEqual(abs(gap), 0, accuracy: 1e-12,
                           "the ground is the figure hue rotated by exactly Δh")
        }
        // …so the σ half's own mean hue is the wall's mean hue, and
        // the rotation is a rigid one (GH2's premise).
        let prims = figure.map { DyadPalette.srgb8(from: DyadPalette.chromaClamp($0)) }
        let table = prims + prims.reversed().map { DyadPalette.ground(gm, of: $0) }
        XCTAssertEqual(abs(Self.angleGap(Self.sigmaHalfHue(table), wallMean)), 0,
                       accuracy: 0.05, "GH9: σ mean hue = the wall's mean hue")
        XCTAssertGreaterThan(abs(Self.angleGap(wallMean, figureMean)), 1.0,
                             "fixture check: the scene really has two hues")

        // …where v7 (the shipped law) put the FIGURE's hue there, for
        // this and for every other background (GH1).
        let v7 = DyadPalette.GroundMoments(deltaL: gm.deltaL, alphaC: gm.alphaC,
                                           betaC: gm.betaC, capped: gm.capped)
        let v7Table = prims + prims.reversed().map { DyadPalette.ground(v7, of: $0) }
        XCTAssertEqual(abs(Self.angleGap(Self.sigmaHalfHue(v7Table), figureMean)), 0,
                       accuracy: 0.05, "v7 painted the wall in the FACE's hue")
    }

    /// ★ GH2/GH11: the table's circular hue concentration R is
    /// R_figure·cos(|Δh|/2) — strictly decreasing in |Δh| on [0, π].
    /// This is the measurement Daniel's 0.9913 reading lives on.
    func testConcentrationFallsWithTheFittedRotation() {
        let figure = Self.labs(hue: 0.55, chroma: 0.06, l: 0.62,
                               count: 128, spread: 0.12)
        func concentration(_ dh: Double) -> Double {
            let gm = DyadPalette.GroundMoments(
                deltaL: 0, alphaC: 0, betaC: 1, capped: false,
                rot: DyadPalette.HueRotation(a: cos(dh), b: sin(dh)))
            var ra = 0.0, rb = 0.0, n = 0.0
            for lab in figure {
                for v in [lab, DyadPalette.groundLab(gm, lab)] {
                    let c = (v.a * v.a + v.b * v.b).squareRoot()
                    guard c > 0 else { continue }
                    ra += v.a / c; rb += v.b / c; n += 1
                }
            }
            return (ra * ra + rb * rb).squareRoot() / n
        }
        let ladder = [0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8, .pi]
        let rs = ladder.map(concentration)
        for (r, next) in zip(rs, rs.dropFirst()) {
            XCTAssertGreaterThan(r, next, "GH11: R strictly decreases in |Δh|")
        }
        // GH2 in closed form, against the figure's own concentration.
        let rFigure = rs[0]
        for (dh, r) in zip(ladder, rs) {
            XCTAssertEqual(r, rFigure * cos(dh / 2), accuracy: 1e-9,
                           "GH2: R_table = R_figure·cos(|Δh|/2)")
        }
        XCTAssertEqual(rs.last!, 0, accuracy: 1e-9, "Δh = π is v5-W: R = 0")
    }

    /// ★ GH7/GH8 — TOTALITY AND GRACEFUL DEGRADATION. Every
    /// degenerate case resolves to the identity rotation, which is
    /// the v7 / Wada-prior path byte for byte: an achromatic wall, a
    /// wall that genuinely IS the face's hue, an achromatic figure,
    /// and a background with no mass at all (which never reaches the
    /// fit — the prior covers it, exactly as it does today).
    func testDegenerateScenesKeepTheWadaPriorPath() {
        let figure = Self.labs(hue: 0.55, chroma: 0.06, l: 0.62,
                               count: 128, spread: 0.12)
        let ones = { (n: Int) in [Double](repeating: 1, count: n) }

        // (1) no background mass at all ⇒ no fit ⇒ the prior rules.
        XCTAssertNil(DyadPalette.backgroundMoments(
            labs: figure, weights: [Double](repeating: 0, count: figure.count)))
        XCTAssertEqual(DyadPalette.priorMoments(centroidL: 0.62).rot, .identity)

        // (2) a true gray card: mass, but no chromatic mass ⇒ the
        //     three scalars still fit, the rotation is the identity.
        let gray = (0..<64).map { OKLabColor(l: 0.5 + Double($0) / 512, a: 0, b: 0) }
        let grayBg = DyadPalette.backgroundMoments(labs: gray, weights: ones(gray.count))
        XCTAssertNil(grayBg, "no chromatic mass ⇒ no ground fit (PP8's two-path law)")

        // (2b) a mostly-gray wall with a few chromatic pixels still
        //      fits, and the hue it reports is those pixels' own.
        let tinted = gray + Self.labs(hue: -2.9, chroma: 0.04, l: 0.5,
                                      count: 6, spread: 0.05)
        let tintBg = try! XCTUnwrap(DyadPalette.backgroundMoments(
            labs: tinted, weights: ones(tinted.count)))
        XCTAssertEqual(abs(Self.angleGap(Self.hueOf(tintBg.hue), -2.9)), 0,
                       accuracy: 0.06, "GH4: gray pixels carry no hue weight")

        // (3) a wall that genuinely IS the face's hue ⇒ Δh = 0 ⇒ the
        //     emitted bytes are v7's, exactly (GH8).
        // (same wedge, same shape — only the chroma and the lightness
        // differ, exactly the GH8 fixture: a wall that genuinely IS
        // the face's hue.)
        let sameHueWall = Self.labs(hue: 0.55, chroma: 0.02, l: 0.5,
                                    count: 128, spread: 0.12)
        let sameBg = try! XCTUnwrap(DyadPalette.backgroundMoments(
            labs: sameHueWall, weights: ones(sameHueWall.count)))
        let sameGm = DyadPalette.groundMoments(centroidL: 0.62, primsLab: figure,
                                               background: sameBg)
        XCTAssertEqual(sameGm.rot.a, 1, accuracy: 1e-9)
        XCTAssertEqual(sameGm.rot.b, 0, accuracy: 1e-9)
        let v7 = DyadPalette.GroundMoments(deltaL: sameGm.deltaL, alphaC: sameGm.alphaC,
                                           betaC: sameGm.betaC, capped: sameGm.capped)
        for c in Self.skinColors(seed: 7, count: 128) {
            XCTAssertTrue(DyadPalette.ground(sameGm, of: c) == DyadPalette.ground(v7, of: c),
                          "a same-hue wall must emit today's bytes")
        }

        // (4) an achromatic FIGURE: nothing to rotate ⇒ identity, and
        //     an achromatic figure keeps an achromatic ground.
        let wall = Self.labs(hue: 2.4, chroma: 0.05, l: 0.55, count: 90, spread: 0.15)
        let wallBg = try! XCTUnwrap(DyadPalette.backgroundMoments(
            labs: wall, weights: ones(wall.count)))
        let grayFigure = (0..<128).map { OKLabColor(l: 0.4 + Double($0) / 640, a: 0, b: 0) }
        let grayGm = DyadPalette.groundMoments(centroidL: 0.5, primsLab: grayFigure,
                                               background: wallBg)
        XCTAssertEqual(grayGm.rot, .identity, "GH7: an achromatic figure cannot be rotated")
        for lab in grayFigure {
            let g = DyadPalette.groundLab(grayGm, lab)
            XCTAssertEqual(g.a, 0)
            XCTAssertEqual(g.b, 0)
        }
    }

    /// ★ GH5 — WRAPAROUND: two hues straddling the 0/360 seam resolve
    /// to the seam itself. The vector law gets it exactly right where
    /// a mean of angle representatives would be 180° wrong.
    func testHueResultantCrossesTheSeamExactly() {
        let up = Self.labs(hue: 0.2, chroma: 0.05, l: 0.5, count: 20, spread: 0)
        let down = Self.labs(hue: -0.2, chroma: 0.05, l: 0.5, count: 20, spread: 0)
        let bg = try! XCTUnwrap(DyadPalette.backgroundMoments(
            labs: up + down, weights: [Double](repeating: 1, count: 40)))
        XCTAssertEqual(Self.hueOf(bg.hue), 0, accuracy: 1e-12,
                       "GH5: the seam resolves to 0°, not 180°")
        // The naive mean of [0,2π) representatives is the failure the
        // vector law avoids: (0.2 + (2π − 0.2))/2 = π.
        let naive = (0.2 + (2 * Double.pi - 0.2)) / 2
        XCTAssertEqual(naive, .pi, accuracy: 1e-12)
    }

    /// ★ GH10 — THE GAMUT CANNOT DEFEAT IT: the chroma power law and
    /// `chromaClamp` are both positive RADIAL scalings, so the hue
    /// the law computes is the hue that reaches the table bytes.
    func testChromaLawAndClampAreHueInvariant() {
        let rot = DyadPalette.HueRotation(a: cos(1.1), b: sin(1.1))
        let probes = Self.labs(hue: 0.55, chroma: 0.09, l: 0.62,
                               count: 60, spread: 0.4)
        for alphaC in [-2.0, -1.0, 0.0] {
            for betaC in [0.5, 0.75, 1.0, 1.5] {
                let gm = DyadPalette.GroundMoments(deltaL: 0.05, alphaC: alphaC,
                                                   betaC: betaC, capped: false, rot: rot)
                for lab in probes {
                    let want = rot.rotate((a: lab.a, b: lab.b))
                    let got = DyadPalette.groundLab(gm, lab)
                    // Parallel and same-signed: hue identical, exactly.
                    XCTAssertEqual(got.a * want.b - got.b * want.a, 0, accuracy: 1e-15)
                    XCTAssertGreaterThan(got.a * want.a + got.b * want.b, 0)
                    // The clamp may only shorten, never rotate.
                    let clamped = DyadPalette.chromaClamp(DyadPalette.clampL(got))
                    XCTAssertEqual(clamped.a * got.b - clamped.b * got.a, 0, accuracy: 1e-15)
                    XCTAssertGreaterThanOrEqual(got.a * got.a + got.b * got.b,
                                                clamped.a * clamped.a + clamped.b * clamped.b
                                                    - 1e-15)
                    // …and the emitted chroma is the power law's own.
                    let c = (lab.a * lab.a + lab.b * lab.b).squareRoot()
                    XCTAssertEqual((got.a * got.a + got.b * got.b).squareRoot(),
                                   exp(alphaC + betaC * log(c)), accuracy: 1e-12)
                }
            }
        }
    }

    /// GH3: the ground family is a GROUP and Δh is its fourth
    /// coordinate — the rotation composes and inverts inside it, so
    /// v5-W (Δh = π) and v7 (Δh = 0) are two points of one subgroup.
    func testHueRotationComposesAndInverts() {
        let a = DyadPalette.HueRotation(a: cos(0.7), b: sin(0.7))
        let b = DyadPalette.HueRotation(a: cos(1.9), b: sin(1.9))
        let v = (a: 0.04, b: -0.02)
        let composed = a.rotate(b.rotate(v))
        let direct = DyadPalette.HueRotation
            .direction(a.rotate((a: b.a, b: b.b))).rotate(v)
        XCTAssertEqual(composed.a, direct.a, accuracy: 1e-12)
        XCTAssertEqual(composed.b, direct.b, accuracy: 1e-12)
        // Inverse = the conjugate direction.
        let inverse = DyadPalette.HueRotation(a: a.a, b: -a.b)
        let round = inverse.rotate(a.rotate(v))
        XCTAssertEqual(round.a, v.a, accuracy: 1e-12)
        XCTAssertEqual(round.b, v.b, accuracy: 1e-12)
        XCTAssertEqual(DyadPalette.HueRotation.identity.rotate(v).a, v.a)
        XCTAssertEqual(DyadPalette.HueRotation.identity.rotate(v).b, v.b)
    }

    // MARK: - Swift-only laws

    func testUniformWeightsReduceToUnweighted() {
        let samples = Self.skinColors(seed: 4, count: 324)
        let unweighted = DyadPalette.analyze(samples)
        let weighted = DyadPalette.analyze(samples,
                                           weights: [Double](repeating: 1, count: samples.count))
        XCTAssertEqual(weighted.centroid.l, unweighted.centroid.l, accuracy: 1e-14)
        XCTAssertEqual(weighted.centroid.a, unweighted.centroid.a, accuracy: 1e-14)
        XCTAssertEqual(weighted.centroid.b, unweighted.centroid.b, accuracy: 1e-14)
        for i in 0..<3 {
            for j in 0..<3 {
                XCTAssertEqual(weighted.covariance[i][j], unweighted.covariance[i][j],
                               accuracy: 1e-14)
            }
        }
    }

    func testZeroWeightPixelsAreIgnored() {
        let face = Self.skinColors(seed: 6, count: 100)
        let noise = Self.randColors(seed: 32, count: 100)
        let masked = DyadPalette.analyze(face + noise,
                                         weights: [Double](repeating: 1, count: 100)
                                                + [Double](repeating: 0, count: 100))
        let faceOnly = DyadPalette.analyze(face)
        XCTAssertEqual(masked.centroid.l, faceOnly.centroid.l, accuracy: 1e-14)
        XCTAssertEqual(masked.centroid.a, faceOnly.centroid.a, accuracy: 1e-14)
        XCTAssertEqual(masked.centroid.b, faceOnly.centroid.b, accuracy: 1e-14)
    }

    func testGIFColorTableIs768Bytes() {
        for table in Self.allTables {
            let data = DyadPalette.gifColorTable(table)
            XCTAssertEqual(data.count, 768)
            // Spot-check the layout: entry i at bytes 3i..3i+2.
            XCTAssertEqual(data[0], table[0].0)
            XCTAssertEqual(data[765], table[255].0)
            XCTAssertEqual(data[767], table[255].2)
        }
    }
}
