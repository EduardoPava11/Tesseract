// GIFOutputContractTests.swift
// Tesseract
//
// End-to-end contract check on the REAL encoder output: encode a full
// 64-frame capture exactly as the app does (upscale = exportUpscale) and
// parse the resulting GIF89a byte stream back out — dimensions, global
// color table, loop extension, frame count, and per-frame delay.

import XCTest
@testable import Tesseract

final class GIFOutputContractTests: XCTestCase {

    private var savedMode: CubeMode!

    override func setUp() {
        super.setUp()
        savedMode = CameraConfig.mode
        CameraConfig.mode = .training   // 64² × 64 frames, the default capture
    }

    override func tearDown() {
        CameraConfig.mode = savedMode
        super.tearDown()
    }

    private func makeFrame(index: Int) -> QuantizedFrame {
        // Deterministic non-trivial content: every palette index appears.
        let n = CameraConfig.pixelCount
        let indices = (0..<n).map { UInt8(($0 + index) % 256) }
        return QuantizedFrame(
            index: index,
            paletteIndices: indices,
            rawRGB: nil,
            depths: [Float](repeating: 0.5, count: n),
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil,
            anchorTrace: nil,
            timestamp: Double(index) / 20.0
        )
    }

    func testFullCapture_outputIs256x256x64Frames_at20fps() throws {
        let frames = (0..<CameraConfig.totalFrames).map { makeFrame(index: $0) }
        let gif = try XCTUnwrap(GIFEncoder.encode(
            frames: frames, upscale: CameraConfig.exportUpscale
        ))
        let b = [UInt8](gif)

        // ── Header + Logical Screen Descriptor ──
        XCTAssertEqual(Array(b[0..<6]), [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], "GIF89a")
        let width  = Int(b[6]) | (Int(b[7]) << 8)
        let height = Int(b[8]) | (Int(b[9]) << 8)
        XCTAssertEqual(width, 256)
        XCTAssertEqual(height, 256)
        XCTAssertEqual(b[10], 0xF7, "GCT present, 2^8 = 256 entries")

        // ── Global Color Table: 256 × 3 bytes, the tesseract palette ──
        XCTAssertEqual(Data(b[13..<(13 + 768)]), TesseractPalette.gifColorTable)

        // ── Walk every block to the trailer ──
        var pos = 13 + 768
        var frameCount = 0
        var delays: [Int] = []
        var sawNetscapeLoop = false
        var imageDims: Set<String> = []

        while pos < b.count {
            switch b[pos] {
            case 0x21:  // extension
                let label = b[pos + 1]
                if label == 0xF9 {  // Graphic Control Extension
                    XCTAssertEqual(b[pos + 2], 4)
                    delays.append(Int(b[pos + 4]) | (Int(b[pos + 5]) << 8))
                }
                if label == 0xFF {  // application extension
                    let name = String(bytes: b[(pos + 3)..<(pos + 14)], encoding: .ascii)
                    if name == "NETSCAPE2.0" { sawNetscapeLoop = true }
                }
                pos += 2
                while b[pos] != 0x00 { pos += 1 + Int(b[pos]) }  // sub-blocks
                pos += 1
            case 0x2C:  // image descriptor
                let left = Int(b[pos + 1]) | (Int(b[pos + 2]) << 8)
                let top  = Int(b[pos + 3]) | (Int(b[pos + 4]) << 8)
                let w    = Int(b[pos + 5]) | (Int(b[pos + 6]) << 8)
                let h    = Int(b[pos + 7]) | (Int(b[pos + 8]) << 8)
                XCTAssertEqual(left, 0); XCTAssertEqual(top, 0)
                imageDims.insert("\(w)×\(h)")
                XCTAssertEqual(b[pos + 9], 0x00, "no local color table")
                frameCount += 1
                pos += 10
                pos += 1  // LZW min code size
                while b[pos] != 0x00 { pos += 1 + Int(b[pos]) }  // data sub-blocks
                pos += 1
            case 0x3B:  // trailer
                XCTAssertEqual(pos, b.count - 1, "trailer must be the final byte")
                pos = b.count
            default:
                XCTFail("unknown block 0x\(String(b[pos], radix: 16)) at \(pos)")
                pos = b.count
            }
        }

        // ── The contract ──
        XCTAssertEqual(frameCount, 64, "64 frames (the temporal side of the cube)")
        XCTAssertEqual(imageDims, ["256×256"], "every frame is 256×256")
        XCTAssertEqual(delays.count, 64, "one GCE per frame")
        XCTAssertEqual(Set(delays), [5], "5 cs per frame = exactly 20 fps")
        XCTAssertTrue(sawNetscapeLoop, "infinite loop extension present")

        let seconds = Double(delays.reduce(0, +)) / 100.0
        XCTAssertEqual(seconds, 3.2, accuracy: 0.0001, "64 frames / 20 fps loop")

        print("CONTRACT ✓ \(width)×\(height) px, \(frameCount) frames, " +
              "256-color GCT, \(delays[0]) cs/frame (20 fps), \(seconds) s loop, " +
              "\(gif.count) bytes")
    }
}
