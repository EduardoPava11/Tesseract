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
