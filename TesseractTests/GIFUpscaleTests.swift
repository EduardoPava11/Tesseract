// GIFUpscaleTests.swift
// Tesseract
//
// Tests for the GIFEncoder index-domain replicate/decimate + upscale header
// math (the 256×256 fat-voxel export path).

import XCTest
@testable import Tesseract

final class GIFUpscaleTests: XCTestCase {

    // CameraConfig.mode is pinned to .training (64² frames) — no per-test
    // save/restore needed.

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

    // ── Encoder header math (per-frame tables — the only scheme) ──

    private func makeIndexFrame(fill: UInt8) -> [UInt8] {
        [UInt8](repeating: fill, count: 64 * 64)
    }

    /// A lawful 768-byte table per frame (a DYAD table solved from
    /// the synthetic mid-gray distribution — content is irrelevant
    /// to the header math, only the byte count is).
    private func makeTables(count: Int) -> [Data] {
        let table = DyadPalette.gifColorTable(
            DyadPalette.table(stats: DyadPalette.analyze([])))
        return (0..<count).map { _ in table }
    }

    func testEncode_upscale4_headerIs256() throws {
        let frames = (0..<4).map { makeIndexFrame(fill: UInt8($0)) }
        let tables = makeTables(count: 4)
        let data = try XCTUnwrap(GIFEncoder.encode(
            indexFrames: frames, side: 64, upscale: 4, perFrameTables: tables))

        // GIF89a magic
        XCTAssertEqual([UInt8](data.prefix(6)), [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        // Logical Screen Descriptor: 256 little-endian in width AND height
        XCTAssertEqual(data[6], 0x00); XCTAssertEqual(data[7], 0x01)
        XCTAssertEqual(data[8], 0x00); XCTAssertEqual(data[9], 0x01)
        // GCT = frame 0's table, 768 bytes starting at offset 13
        XCTAssertEqual(data.subdata(in: 13..<(13 + 768)), tables[0])
    }

    func testEncode_defaultUpscale_headerIs64() throws {
        let data = try XCTUnwrap(GIFEncoder.encode(
            indexFrames: [makeIndexFrame(fill: 7)], side: 64,
            perFrameTables: makeTables(count: 1)))
        XCTAssertEqual(data[6], 0x40); XCTAssertEqual(data[7], 0x00)
        XCTAssertEqual(data[8], 0x40); XCTAssertEqual(data[9], 0x00)
    }

    func testEncode_defaultParameterMatchesExplicitUpscale1() throws {
        let frames = (0..<3).map { makeIndexFrame(fill: UInt8(40 + $0)) }
        let tables = makeTables(count: 3)
        let a = try XCTUnwrap(GIFEncoder.encode(
            indexFrames: frames, side: 64, perFrameTables: tables))
        let b = try XCTUnwrap(GIFEncoder.encode(
            indexFrames: frames, side: 64, upscale: 1, perFrameTables: tables))
        XCTAssertEqual(a, b, "default parameter must preserve byte-identical output")
    }
}
