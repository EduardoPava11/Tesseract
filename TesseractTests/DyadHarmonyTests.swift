// DyadHarmonyTests.swift
// Tesseract
//
// Laws of the Ou & Luo two-colour harmony score (DyadHarmony) and its
// place in the GIF provenance trace: symmetry, determinism, ordering
// sanity against the model's published behaviour (light similar pairs
// harmonize, dark saturated clashing pairs do not), finiteness over a
// real DYAD table, and the wire-level DYAD HARMONY comment.

import XCTest
@testable import Tesseract

final class DyadHarmonyTests: XCTestCase {

    // MARK: - Pair law: symmetry

    func testPairHarmonyIsSymmetric() {
        let colors: [(UInt8, UInt8, UInt8)] = [
            (0, 0, 0), (255, 255, 255), (255, 0, 0), (0, 255, 0),
            (0, 0, 255), (200, 150, 120), (17, 91, 231), (128, 128, 128)
        ]
        for a in colors {
            for b in colors {
                XCTAssertEqual(DyadHarmony.pairHarmony(a, b),
                               DyadHarmony.pairHarmony(b, a),
                               "CH(a,b) == CH(b,a) exactly")
            }
        }
    }

    // MARK: - Pair law: determinism

    func testPairHarmonyIsDeterministic() {
        let a: (UInt8, UInt8, UInt8) = (200, 150, 120)
        let b: (UInt8, UInt8, UInt8) = (40, 80, 160)
        let first = DyadHarmony.pairHarmony(a, b)
        for _ in 0..<8 {
            XCTAssertEqual(DyadHarmony.pairHarmony(a, b), first)
        }
    }

    // MARK: - Ordering sanity (model's published behaviour, not values)

    func testSamePairBeatsClashingPair() {
        // Identical light pair: DeltaC = 0 maximizes HC, high Lsum
        // raises HLsum. Saturated red vs green: large DeltaC collapses
        // HC to its floor and both HS terms are negative.
        let light: (UInt8, UInt8, UInt8) = (240, 240, 240)
        let same = DyadHarmony.pairHarmony(light, light)
        let clash = DyadHarmony.pairHarmony((255, 0, 0), (0, 255, 0))
        XCTAssertGreaterThan(same, clash,
                             "a same-colour light pair outscores a saturated clash")
        // The published CH scale spans roughly -1.24 to 1.39.
        XCTAssertLessThan(abs(same), 2.5)
        XCTAssertLessThan(abs(clash), 2.5)
    }

    func testCIELABReferencePoints() {
        // White (255,255,255) is L* = 100, a* = b* = 0 by construction.
        let white = DyadHarmony.srgb8ToCIELAB((255, 255, 255))
        XCTAssertEqual(white.L, 100, accuracy: 0.01)
        XCTAssertEqual(white.a, 0, accuracy: 0.01)
        XCTAssertEqual(white.b, 0, accuracy: 0.01)
        // Black is the origin.
        let black = DyadHarmony.srgb8ToCIELAB((0, 0, 0))
        XCTAssertEqual(black.L, 0, accuracy: 0.01)
    }

    // MARK: - Table law: a real DYAD table scores finitely

    func testTableHarmonyOverRealDyadTable() {
        // Skin-toned sample cloud, as DyadGIFContractTests builds.
        var s = 1
        func next() -> Double {
            s = (1103515245 * s + 12345) % 2147483648
            return Double(s) / 2147483648.0
        }
        let samples = (0..<324).map { _ in
            (UInt8(140 + Int(next() * 80)), UInt8(110 + Int(next() * 60)),
             UInt8(90 + Int(next() * 50)))
        }
        let table = DyadPalette.table(stats: DyadPalette.analyze(samples))
        XCTAssertEqual(table.count, 256)
        let h = DyadHarmony.tableHarmony(table)
        XCTAssertTrue(h.mean.isFinite)
        XCTAssertTrue(h.min.isFinite)
        XCTAssertLessThanOrEqual(h.min, h.mean, "min bounds the mean below")
    }

    // MARK: - Wire law: the trace comment rides the dyad stream only

    private func makeFrame(index: Int, withRGB: Bool) -> QuantizedFrame {
        let n = QuantizedFrame.pixelCount
        let side = QuantizedFrame.size
        let c = Double(side - 1) / 2
        var rgb = [(Float, Float, Float)](repeating: (0.6, 0.45, 0.35), count: n)
        var depths = [Float](repeating: 0, count: n)
        for p in 0..<n {
            let x = Double(p % side), y = Double(p / side)
            if (x - c) * (x - c) + (y - c) * (y - c) <= 24 * 24 {
                depths[p] = 1
                rgb[p].0 += Float(p % 16) * 0.01
            }
        }
        let indices = (0..<n).map { UInt8($0 % 256) }
        return QuantizedFrame(
            index: index, paletteIndices: indices,
            rawRGB: withRGB ? rgb : nil, depths: depths,
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil, anchorTrace: nil,
            timestamp: Double(index) / 20.0)
    }

    private func frames(withRGB: Bool, count: Int = 4) -> [QuantizedFrame] {
        (0..<count).map { makeFrame(index: $0, withRGB: withRGB) }
    }

    func testDyadExportCarriesHarmonyComment() throws {
        let gif = try XCTUnwrap(GIFMachine.makeGIF(frames: frames(withRGB: true),
                                                   measure: nil, method: .dyad))
        XCTAssertNotNil(gif.range(of: Data("DYAD HARMONY".utf8)),
                        "dyad stream carries the harmony trace comment")
    }

    func testTesseractExportHasNoHarmonyComment() throws {
        let gif = try XCTUnwrap(GIFMachine.makeGIF(frames: frames(withRGB: true),
                                                   measure: nil, method: .tesseract))
        XCTAssertNil(gif.range(of: Data("DYAD HARMONY".utf8)),
                     "lattice stream carries no harmony trace")
    }
}
