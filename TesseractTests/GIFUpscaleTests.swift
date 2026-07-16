// GIFUpscaleTests.swift
// Tesseract
//
// Tests for the GIFEncoder index-domain replicate/decimate + upscale header
// math (the 256×256 fat-voxel export path).

import XCTest
@testable import Tesseract

final class GIFUpscaleTests: XCTestCase {

    private var savedMode: CubeMode!

    override func setUp() {
        super.setUp()
        savedMode = CameraConfig.mode
        CameraConfig.mode = .training   // 64² frames
    }

    override func tearDown() {
        CameraConfig.mode = savedMode
        super.tearDown()
    }

    // ── replicate / decimate ──

    func testReplicate_decimateRoundTrip() {
        var rng = SystemRandomNumberGenerator()
        let x = (0..<64 * 64).map { _ in UInt8.random(in: 0...255, using: &rng) }
        let big = GIFEncoder.replicate(x, side: 64, factor: 4)
        XCTAssertEqual(big.count, 256 * 256)
        XCTAssertEqual(GIFEncoder.decimate(big, side: 64, factor: 4), x)
    }

    func testReplicate_fatVoxelBlocks() {
        // 2×2 source, factor 3 → each index fills a 3×3 block.
        let x: [UInt8] = [1, 2, 3, 4]
        let out = GIFEncoder.replicate(x, side: 2, factor: 3)
        XCTAssertEqual(out.count, 36)
        for oy in 0..<6 {
            for ox in 0..<6 {
                XCTAssertEqual(out[oy * 6 + ox], x[(oy / 3) * 2 + (ox / 3)])
            }
        }
    }

    // ── Encoder header math ──

    private func makeFrame(index: Int, fill: UInt8) -> QuantizedFrame {
        let indices = [UInt8](repeating: fill, count: 64 * 64)
        return QuantizedFrame(
            index: index,
            paletteIndices: indices,
            rawRGB: nil,
            depths: [Float](repeating: 0.5, count: 64 * 64),
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil,
            anchorTrace: nil,
            timestamp: 0
        )
    }

    func testEncode_upscale4_headerIs256() throws {
        let frames = (0..<4).map { makeFrame(index: $0, fill: UInt8($0)) }
        let data = try XCTUnwrap(GIFEncoder.encode(frames: frames, upscale: 4))

        // GIF89a magic
        XCTAssertEqual([UInt8](data.prefix(6)), [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        // Logical Screen Descriptor: 256 little-endian in width AND height
        XCTAssertEqual(data[6], 0x00); XCTAssertEqual(data[7], 0x01)
        XCTAssertEqual(data[8], 0x00); XCTAssertEqual(data[9], 0x01)
        // GCT still 768 bytes starting at offset 13
        XCTAssertEqual(data.subdata(in: 13..<(13 + 768)), TesseractPalette.gifColorTable)
    }

    func testEncode_defaultUpscale_headerIs64() throws {
        let frames = [makeFrame(index: 0, fill: 7)]
        let data = try XCTUnwrap(GIFEncoder.encode(frames: frames))
        XCTAssertEqual(data[6], 0x40); XCTAssertEqual(data[7], 0x00)
        XCTAssertEqual(data[8], 0x40); XCTAssertEqual(data[9], 0x00)
    }

    func testEncode_defaultParameterMatchesExplicitUpscale1() throws {
        let frames = (0..<3).map { makeFrame(index: $0, fill: UInt8(40 + $0)) }
        let a = try XCTUnwrap(GIFEncoder.encode(frames: frames))
        let b = try XCTUnwrap(GIFEncoder.encode(frames: frames, upscale: 1))
        XCTAssertEqual(a, b, "default parameter must preserve byte-identical output")
    }
}
