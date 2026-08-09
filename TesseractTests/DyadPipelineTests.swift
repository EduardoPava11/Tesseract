// DyadPipelineTests.swift
// Tesseract
//
// Pure-logic tests for the DYAD-256 export path: synthetic captures
// (skin disk on background, depth mask in the QuantizedFrame slot)
// through DyadPipeline.process. No camera, no Metal.

import XCTest
@testable import Tesseract

final class DyadPipelineTests: XCTestCase {

    private let side = QuantizedFrame.size
    private let frameCount = 8   // enough to exercise the EMA chain

    /// A frame whose rawRGB is a warm skin disk on a cool background,
    /// with depths 1 inside the disk and 0 outside — the mask decides
    /// roles, so the background color content should not matter.
    private func makeFrame(index: Int, withRGB: Bool = true) -> QuantizedFrame {
        let n = side * side
        let c = Double(side - 1) / 2
        var rgb = [(Float, Float, Float)](repeating: (0, 0, 0), count: n)
        var depths = [Float](repeating: 0, count: n)
        for p in 0..<n {
            let x = Double(p % side), y = Double(p / side)
            let inFace = (x - c) * (x - c) + (y - c) * (y - c) <= 24 * 24
            if inFace {
                let t = Float(p % 32) / 31          // shading ramp across the face
                rgb[p] = (0.55 + 0.25 * t, 0.42 + 0.18 * t, 0.33 + 0.12 * t)
                depths[p] = 1
            } else {
                rgb[p] = (0.1, 0.9, 0.1)            // loud background, masked out
                depths[p] = 0
            }
        }
        let indices = [UInt8](repeating: 0, count: n)
        return QuantizedFrame(
            index: index,
            paletteIndices: indices,
            rawRGB: withRGB ? rgb : nil,
            depths: depths,
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil,
            anchorTrace: nil,
            timestamp: Double(index) / 20.0
        )
    }

    func testRoleLawOnPixels() throws {
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames))
        XCTAssertEqual(out.indexFrames.count, frameCount)
        XCTAssertEqual(out.tables.count, frameCount)

        let c = Double(side - 1) / 2
        for indices in out.indexFrames {
            for p in 0..<indices.count {
                let x = Double(p % side), y = Double(p / side)
                let inFace = (x - c) * (x - c) + (y - c) * (y - c) <= 24 * 24
                if inFace {
                    XCTAssertLessThan(indices[p], 128, "face pixels use primaries only")
                } else {
                    XCTAssertEqual(indices[p], 255, "background collapses to index 255")
                }
            }
        }
    }

    func testEveryTableSatisfiesTheInvolution() throws {
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames))
        for table in out.tables {
            XCTAssertEqual(table.count, 768)
            func entry(_ i: Int) -> (UInt8, UInt8, UInt8) {
                (table[3 * i], table[3 * i + 1], table[3 * i + 2])
            }
            for i in 0..<128 {
                XCTAssertTrue(entry(255 - i) == DyadPalette.complement(of: entry(i)))
            }
        }
    }

    func testMaskedBackgroundDoesNotSteerThePalette() throws {
        // The loud green background is weight-0: the face centroid T[0]
        // must be warm (a > 0 in OKLab), not dragged green.
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames))
        let t = out.tables[0]
        let centroid = DyadPalette.oklab(fromSRGB8: (t[0], t[1], t[2]))
        XCTAssertGreaterThan(centroid.a, 0, "face centroid must stay warm")
    }

    func testHarshBleedBand() throws {
        // Three depth zones: face disk (0.9), bleed ring (0.55 — pull
        // t ≈ 0.58, inside the band), far field (0.1 — fully pulled).
        let n = side * side
        let c = Double(side - 1) / 2
        var rgb = [(Float, Float, Float)](repeating: (0.1, 0.9, 0.1), count: n)
        var depths = [Float](repeating: 0.1, count: n)
        for p in 0..<n {
            let x = Double(p % side), y = Double(p / side)
            let r2 = (x - c) * (x - c) + (y - c) * (y - c)
            if r2 <= 20 * 20 {
                rgb[p] = (0.65, 0.5, 0.4); depths[p] = 0.9
            } else if r2 <= 27 * 27 {
                depths[p] = 0.55
            }
        }
        let indices = [UInt8](repeating: 0, count: n)
        let frame = QuantizedFrame(
            index: 0, paletteIndices: indices, rawRGB: rgb, depths: depths,
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil, anchorTrace: nil, timestamp: 0)
        let out = try XCTUnwrap(DyadPipeline.process(frames: [frame]))

        // v3 pair dither: a band pixel shows the σ side of its pair
        // exactly when its Bayer threshold is below the coverage t;
        // otherwise the primary side. Flipping with 255 − i is the
        // other side of the same pair by the involution.
        let tBand = DyadPipeline.pull(0.55)
        XCTAssertTrue(tBand > 0 && tBand < 1, "ring depth must sit in the band")
        var sawSigma = false, sawPrimary = false
        for p in 0..<n {
            let idx = Int(out.indexFrames[0][p])
            switch depths[p] {
            case let d where d > 0.6:
                XCTAssertLessThan(idx, 128, "face pixels use primaries")
            case 0.55:
                let sigmaSide = DyadPipeline.bayer4[(p / side) % 4][(p % side) % 4] < tBand
                if sigmaSide {
                    XCTAssertGreaterThanOrEqual(idx, 128, "below threshold = σ side")
                    XCTAssertLessThan(255 - idx, 128, "partner is the primary side")
                    sawSigma = true
                } else {
                    XCTAssertLessThan(idx, 128, "at/above threshold = primary side")
                    XCTAssertGreaterThanOrEqual(255 - idx, 128, "partner is the σ side")
                    sawPrimary = true
                }
            default:
                XCTAssertEqual(idx, 255, "fully pulled background is the solid")
            }
        }
        XCTAssertTrue(sawSigma && sawPrimary,
            "the band must dither: both sides of the pair appear")

        // BLEED OFF: role law v1 — every background pixel is the solid.
        let flat = try XCTUnwrap(DyadPipeline.process(frames: [frame], bleed: false))
        for p in 0..<n where depths[p] <= DyadPipeline.faceThreshold {
            XCTAssertEqual(flat.indexFrames[0][p], 255,
                           "bleed off collapses ALL background to 255")
        }
    }

    func testMissingRawRGBDeclinesTheCapture() {
        var frames = (0..<frameCount).map { makeFrame(index: $0) }
        frames[3] = makeFrame(index: 3, withRGB: false)
        XCTAssertNil(DyadPipeline.process(frames: frames),
                     "any frame without rawRGB must fall back to the lattice path")
        XCTAssertNil(DyadPipeline.process(frames: []))
    }

    func testDeterminism() throws {
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        let a = try XCTUnwrap(DyadPipeline.process(frames: frames))
        let b = try XCTUnwrap(DyadPipeline.process(frames: frames))
        XCTAssertEqual(a.tables, b.tables)
        XCTAssertEqual(a.indexFrames, b.indexFrames)
    }

    func testEndToEndThroughEncoder() throws {
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames))
        let gif = try XCTUnwrap(GIFEncoder.encode(
            indexFrames: out.indexFrames, side: side,
            upscale: CameraConfig.exportUpscale, perFrameTables: out.tables))
        let b = [UInt8](gif)
        XCTAssertEqual(Array(b[0..<6]), [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        XCTAssertEqual(Data(b[13..<(13 + 768)]), out.tables[0], "GCT = frame 0's table")
    }
}
