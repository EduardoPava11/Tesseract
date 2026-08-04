// CentroidRefinerTests.swift
// Tesseract
//
// Swift-side mirror of spec/quantization/CentroidRefine.hs (WL1-WL5).
// The spec proves the laws in exact Rational arithmetic; these tests
// pin the Float implementation to the same trajectories (WL4 closed
// form) and exercise the two clamps the spec's synthetic cannot:
// out-of-cell empirical means (dither) and the byte-cell edge.

import XCTest
@testable import Tesseract

final class CentroidRefinerTests: XCTestCase {

    private let n = CameraConfig.pixelCount

    /// Build one frame where chosen entries receive `pixels` pixels of
    /// constant gray value v and face weight w; all remaining pixels
    /// belong to index 0 with zero weight (inert background).
    private func makeFrame(assignments: [(index: UInt8, v: Float, w: Float, pixels: Int)]) -> QuantizedFrame {
        var indices = [UInt8](repeating: 0, count: n)
        var rgb = [(Float, Float, Float)](repeating: (0, 0, 0), count: n)
        var depths = [Float](repeating: 0, count: n)
        var p = 0
        for a in assignments {
            for _ in 0..<a.pixels {
                indices[p] = a.index
                rgb[p] = (a.v, a.v, a.v)
                depths[p] = a.w
                p += 1
            }
        }
        return QuantizedFrame(
            index: 0, paletteIndices: indices, rawRGB: rgb, depths: depths,
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil, anchorTrace: nil, timestamp: 0)
    }

    /// WL4 closed form: r^K = r* + (c − r*)·ρ^K with
    /// r* = (a·m + b·c)/(a+b), ρ = 1 − η(a+b), b = μ(1−a).
    private func closedForm(c: Double, m: Double, a: Double,
                            eta: Double = 0.5, mu: Double = 0.5, K: Int = 8) -> Double {
        let b = mu * (1 - a)
        let rStar = (a * m + b * c) / (a + b)
        let rho = 1 - eta * (a + b)
        return rStar + (c - rStar) * pow(rho, Double(K))
    }

    // ── WL4: the Float trajectory matches the spec's exact law ──

    func testSpecParity_closedFormTrajectory() {
        // The spec's synthetic: display cell (2,2,2), c = 5/8, four
        // epoch siblings with distinct means and falling face mass.
        let cases: [(d: Int, m: Float, a: Float)] = [
            (0, 17.0 / 32, 1.0),
            (1, 9.0 / 16, 0.75),
            (2, 5.0 / 8, 0.5),
            (3, 11.0 / 16, 0.25),
        ]
        let frame = makeFrame(assignments: cases.map {
            (index: UInt8($0.d * 64 + 42), v: $0.m, w: $0.a, pixels: 100)
        })
        let refined = CentroidRefiner.refine(frames: [frame])

        for c8 in cases {
            let i = c8.d * 64 + 42
            let canonical = Double(TesseractCoord(index: UInt8(i)).sRGB.x)
            let expected = closedForm(c: canonical, m: Double(c8.m), a: Double(c8.a))
            // Reconstruct the continuous final from the trace (WL5).
            let total = refined.deltas[i].reduce(SIMD3<Float>.zero, +)
            let rFinal = Double(Float(canonical) + total.x)
            XCTAssertEqual(refined.deltas[i].count, 8, "K is fixed")
            XCTAssertEqual(rFinal, expected, accuracy: 1e-5,
                           "entry \(i): Float trajectory must match WL4 closed form")
        }
    }

    // ── WL3: zero face mass ⇒ the entry never moves ──

    func testZeroFaceMass_neverMoves() {
        // Entries 21 and 85 (levels (1,1,1), epochs 0/1) get pixels with
        // weight 0 — present in the capture, but pure background.
        let frame = makeFrame(assignments: [
            (index: 21, v: 0.4375, w: 0, pixels: 200),
            (index: 85, v: 0.3125, w: 0, pixels: 200),
        ])
        let refined = CentroidRefiner.refine(frames: [frame])
        for i in [21, 85] {
            XCTAssertTrue(refined.deltas[i].isEmpty, "background trace must be constant")
            let canonical = TesseractCoord(index: UInt8(i)).sRGB8
            XCTAssertTrue(refined.table[i] == canonical,
                          "background entry \(i) must stay canonical")
        }
    }

    // ── WL1 in production: out-of-cell means (dither) are contained ──

    func testOutOfCellMean_clampedInBothSpaces() {
        // Dither can assign a bright pixel to the darkest cell. The mean
        // (0.95) is far outside cell 0 = [0, 0.25); the iterate must be
        // clamped to the cell, and the BYTE must stay in [0, 63] — a
        // bare round() here would produce 64 and re-quantize wrongly.
        let frame = makeFrame(assignments: [
            (index: 0, v: 0.95, w: 1.0, pixels: 500),
        ])
        let refined = CentroidRefiner.refine(frames: [frame])
        let (r, g, b) = refined.table[0]
        for byte in [r, g, b] {
            XCTAssertLessThanOrEqual(byte, 63,
                "byte-cell clamp must hold at the cell edge (got \(byte))")
        }
        // Idempotence: the refined color still floor-quantizes to level 0.
        XCTAssertEqual(min(3, Int(Float(r) / 255 * 4)), 0)
    }

    // ── Identity cases ──

    func testNoRawRGB_returnsCanonical() {
        let indices = (0..<n).map { UInt8($0 % 256) }
        let preview = QuantizedFrame(
            index: 0, paletteIndices: indices, rawRGB: nil,
            depths: [Float](repeating: 1, count: n),
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil, anchorTrace: nil, timestamp: 0)
        let refined = CentroidRefiner.refine(frames: [preview])
        for i in 0..<256 {
            XCTAssertTrue(refined.table[i] == TesseractCoord(index: UInt8(i)).sRGB8)
            XCTAssertTrue(refined.deltas[i].isEmpty)
        }
    }

    // ── Encoder contract: refined GCT + trace provenance ──

    func testEncoder_writesRefinedTableAndTrace() throws {
        let frame = makeFrame(assignments: [
            (index: 42, v: 17.0 / 32, w: 1.0, pixels: 100),
        ])
        let frames = [frame, frame]
        let refined = CentroidRefiner.refine(frames: frames)

        // The encoder derives the trace from the palette itself — a
        // mismatched table/trace pair is unrepresentable.
        let gif = try XCTUnwrap(GIFEncoder.encode(frames: frames, refined: refined))

        // GCT occupies bytes 13..<781.
        XCTAssertEqual(gif.subdata(in: 13..<781), refined.gifColorTable)
        XCTAssertNotEqual(gif.subdata(in: 13..<781), TesseractPalette.gifColorTable,
                          "entry 42 moved — refined GCT must differ from canonical")
        XCTAssertTrue(String(decoding: gif, as: UTF8.self).contains("TRACE v1"),
                      "trace provenance must ship inside the GIF")

        // Every refined entry remains inside its byte cell (WL1).
        for i in 0..<256 {
            let level = Int(TesseractCoord(index: UInt8(i)).a)
            let byte = Int(refined.table[i].0)
            XCTAssertTrue(byte >= level * 64 && byte <= level * 64 + 63)
        }

        // nil refined ⇒ canonical GCT, byte-identical (the spine default).
        let canonical = try XCTUnwrap(GIFEncoder.encode(frames: frames))
        XCTAssertEqual(canonical.subdata(in: 13..<781), TesseractPalette.gifColorTable)
    }
}
