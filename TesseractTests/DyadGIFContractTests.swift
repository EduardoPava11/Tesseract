// DyadGIFContractTests.swift
// Tesseract
//
// Byte-level contract for DYAD-256 GIF output — the per-frame Local
// Color Table mode. Forked from GIFOutputContractTests, which locks
// the lattice mode's single-GCT stream; this file locks the DYAD
// stream: LCT flag 0x87 on every frame, 768 LCT bytes per frame,
// GCT = frame 0's table, and the involution law T[255−i] = comp(T[i])
// holding byte-exactly inside EVERY embedded table.

import XCTest
@testable import Tesseract

final class DyadGIFContractTests: XCTestCase {

    private static let side = 64
    private static let upscale = 4
    private static let frameCount = 64

    /// 64 face-drift statistics: EMA between two skin distributions,
    /// as the wired mode will produce across a capture.
    private static let tables: [Data] = {
        func skin(_ seed: Int) -> [(UInt8, UInt8, UInt8)] {
            var s = seed
            func next() -> Double {
                s = (1103515245 * s + 12345) % 2147483648
                return Double(s) / 2147483648.0
            }
            return (0..<324).map { _ in
                (UInt8(140 + Int(next() * 80)), UInt8(110 + Int(next() * 60)),
                 UInt8(90 + Int(next() * 50)))
            }
        }
        let s1 = DyadPalette.analyze(skin(1))
        let s2 = DyadPalette.analyze(skin(9))
        return (0..<frameCount).map { f in
            let alpha = Double(f) / Double(frameCount - 1)
            let blend = DyadPalette.ema(alpha: alpha, s1, s2)
            return DyadPalette.gifColorTable(DyadPalette.table(stats: blend))
        }
    }()

    /// Synthetic DYAD index frames: a face disk of primaries 0..127 on
    /// a background of exactly index 255 — the role law's pixel shape.
    private static func makeIndexFrame(_ f: Int) -> [UInt8] {
        let c = Double(side - 1) / 2
        return (0..<side * side).map { p in
            let x = Double(p % side), y = Double(p / side)
            let inFace = (x - c) * (x - c) + (y - c) * (y - c) <= 24 * 24
            return inFace ? UInt8((p + f) % 128) : 255
        }
    }

    func testDyadCapture_perFrameLCTs_involutionInEveryTable() throws {
        let frames = (0..<Self.frameCount).map { Self.makeIndexFrame($0) }
        let gif = try XCTUnwrap(GIFEncoder.encode(
            indexFrames: frames, side: Self.side,
            upscale: Self.upscale, perFrameTables: Self.tables
        ))
        let b = [UInt8](gif)

        // ── Header + Logical Screen Descriptor ──
        XCTAssertEqual(Array(b[0..<6]), [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], "GIF89a")
        let width  = Int(b[6]) | (Int(b[7]) << 8)
        let height = Int(b[8]) | (Int(b[9]) << 8)
        XCTAssertEqual(width, 256)
        XCTAssertEqual(height, 256)
        XCTAssertEqual(b[10], 0xF7, "GCT present, 2^8 = 256 entries")

        // ── GCT = frame 0's DYAD table (naive-decoder fallback) ──
        XCTAssertEqual(Data(b[13..<(13 + 768)]), Self.tables[0])

        // ── Walk every block to the trailer ──
        var pos = 13 + 768
        var frameIndex = 0
        var delays: [Int] = []
        var sawNetscapeLoop = false

        while pos < b.count {
            switch b[pos] {
            case 0x21:  // extension
                let label = b[pos + 1]
                if label == 0xF9 {  // Graphic Control Extension
                    XCTAssertEqual(b[pos + 2], 4)
                    XCTAssertEqual(b[pos + 3], 0x00, "disposal 0, no transparency")
                    delays.append(Int(b[pos + 4]) | (Int(b[pos + 5]) << 8))
                }
                if label == 0xFF {
                    let name = String(bytes: b[(pos + 3)..<(pos + 14)], encoding: .ascii)
                    if name == "NETSCAPE2.0" { sawNetscapeLoop = true }
                }
                pos += 2
                while b[pos] != 0x00 { pos += 1 + Int(b[pos]) }
                pos += 1
            case 0x2C:  // image descriptor + LCT + LZW
                let w = Int(b[pos + 5]) | (Int(b[pos + 6]) << 8)
                let h = Int(b[pos + 7]) | (Int(b[pos + 8]) << 8)
                XCTAssertEqual(w, 256); XCTAssertEqual(h, 256)
                XCTAssertEqual(b[pos + 9], 0x87, "LCT present, 256 entries, frame \(frameIndex)")

                // The embedded LCT is byte-identical to the table we passed…
                let lct = Data(b[(pos + 10)..<(pos + 10 + 768)])
                XCTAssertEqual(lct, Self.tables[frameIndex], "LCT bytes, frame \(frameIndex)")

                // …and satisfies the involution law internally.
                func entry(_ i: Int) -> (UInt8, UInt8, UInt8) {
                    (lct[lct.startIndex + 3 * i],
                     lct[lct.startIndex + 3 * i + 1],
                     lct[lct.startIndex + 3 * i + 2])
                }
                for i in 0..<128 {
                    XCTAssertTrue(entry(255 - i) == DyadPalette.complement(of: entry(i)),
                                  "involution broken at frame \(frameIndex), index \(i)")
                }

                frameIndex += 1
                pos += 10 + 768
                XCTAssertEqual(b[pos], 8, "LZW min code size stays 8 for 256-entry tables")
                pos += 1
                while b[pos] != 0x00 { pos += 1 + Int(b[pos]) }
                pos += 1
            case 0x3B:
                XCTAssertEqual(pos, b.count - 1, "trailer must be the final byte")
                pos = b.count
            default:
                XCTFail("unknown block 0x\(String(b[pos], radix: 16)) at \(pos)")
                pos = b.count
            }
        }

        // ── The contract ──
        XCTAssertEqual(frameIndex, 64, "64 frames, each with its own LCT")
        XCTAssertEqual(Set(delays), [5], "5 cs per frame = exactly 20 fps")
        XCTAssertTrue(sawNetscapeLoop, "infinite loop extension present")

        print("DYAD CONTRACT ✓ \(width)×\(height) px, \(frameIndex) frames, " +
              "64 local color tables, involution law verified in all, \(gif.count) bytes")
    }

    func testLatticeModeIsUntouched() throws {
        // No perFrameTables → the original single-GCT stream, no LCT flag.
        let frames = (0..<4).map { Self.makeIndexFrame($0) }
        let gif = try XCTUnwrap(GIFEncoder.encode(indexFrames: frames, side: Self.side))
        let b = [UInt8](gif)
        XCTAssertEqual(Data(b[13..<(13 + 768)]), TesseractPalette.gifColorTable)
        // First image descriptor follows the NETSCAPE block; find it.
        var pos = 13 + 768
        while b[pos] != 0x2C { // skip extensions
            pos += 2
            while b[pos] != 0x00 { pos += 1 + Int(b[pos]) }
            pos += 1
        }
        XCTAssertEqual(b[pos + 9], 0x00, "no local color table in lattice mode")
    }

    func testMalformedTablesAreRejected() {
        let frames = (0..<4).map { Self.makeIndexFrame($0) }
        // Wrong table count.
        XCTAssertNil(GIFEncoder.encode(
            indexFrames: frames, side: Self.side,
            perFrameTables: Array(Self.tables.prefix(3))))
        // Wrong table size.
        XCTAssertNil(GIFEncoder.encode(
            indexFrames: frames, side: Self.side,
            perFrameTables: (0..<4).map { _ in Data(repeating: 0, count: 767) }))
    }
}
