// RGBTEncodeTests.swift
// Tesseract
//
// Tests for the RGBT additions with runtime surface off-device:
//   • GIFEncoder index-domain replicate/decimate + upscale header math
//   • RGBTPipeline.normalizeT orientation and clamping
//   • BayerCellReducer on synthetic CVPixelBuffers (all 4 CFA variants)

import AVFoundation
import CoreVideo
import XCTest
@testable import Tesseract

final class RGBTEncodeTests: XCTestCase {

    private var savedMode: CubeMode!

    override func setUp() {
        super.setUp()
        savedMode = CameraConfig.mode
        CameraConfig.mode = .training   // 64² frames, like the RGBT pipeline
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

    // ── T normalization ──

    func testNormalizeT_orientationAndRange() {
        // Bright pixel = many photons = SMALL T → tHat ≈ 1 (near/sharp).
        let t: [Double] = (0..<1000).map { 1e-6 + Double($0) * 1e-8 }
        let (tHat, p1, p99) = RGBTPipeline.normalizeT(t)
        XCTAssertEqual(tHat.count, t.count)
        for v in tHat {
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
        XCTAssertLessThan(p1, p99)
        // Smallest T (most photons) → tHat == 1
        XCTAssertEqual(tHat.first!, 1.0, accuracy: 1e-9)
        // Largest T → tHat == 0
        XCTAssertEqual(tHat.last!, 0.0, accuracy: 1e-9)
    }

    func testNormalizeT_outlierClamping() {
        // One enormous T (near-zero-photon cell) must not stretch the axis:
        // p99 is robust to it, and its tHat clamps to 0.
        var t = [Double](repeating: 1e-6, count: 999)
        for i in 0..<999 { t[i] += Double(i) * 1e-9 }
        t.append(1e3)   // pathological cell
        let (tHat, _, p99) = RGBTPipeline.normalizeT(t)
        XCTAssertLessThan(p99, 1.0, "p99 must ignore the outlier")
        XCTAssertEqual(tHat.last!, 0.0, accuracy: 1e-12)
    }

    // ── sRGB OETF ──

    func testSRGBOETF_anchorsAndMonotone() {
        XCTAssertEqual(RGBTPipeline.srgbOETF(0), 0, accuracy: 1e-12)
        XCTAssertEqual(RGBTPipeline.srgbOETF(1), 1, accuracy: 1e-12)
        // Linear toe: 12.92 · x
        XCTAssertEqual(RGBTPipeline.srgbOETF(0.001), 0.01292, accuracy: 1e-9)
        var prev = -1.0
        for i in 0...100 {
            let v = RGBTPipeline.srgbOETF(Double(i) / 100.0)
            XCTAssertGreaterThan(v, prev)
            prev = v
        }
    }

    // ── BayerCellReducer on synthetic buffers ──

    /// Per-channel constant DNs: R=1000, Gr=800, Gb=600, B=400.
    private let channelDN: [UInt16] = [1000, 800, 600, 400]

    /// Position layouts (index = (y&1)*2 + (x&1)) per CFA fourCC, matching
    /// BayerCellReducer.cfaLUT.
    private let cfaCases: [(format: OSType, name: String)] = [
        (kCVPixelFormatType_14Bayer_RGGB, "rgg4"),
        (kCVPixelFormatType_14Bayer_BGGR, "bgg4"),
        (kCVPixelFormatType_14Bayer_GRBG, "grb4"),
        (kCVPixelFormatType_14Bayer_GBRG, "gbr4")
    ]

    private func makeBayerBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else { return nil }

        guard let lut = BayerCellReducer.cfaLUT(format) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let ptr = base.assumingMemoryBound(to: UInt16.self)
        let rowStride = CVPixelBufferGetBytesPerRow(buffer) / 2
        for y in 0..<height {
            for x in 0..<width {
                let ch = lut[(y & 1) << 1 | (x & 1)]
                ptr[y * rowStride + x] = channelDN[ch]
            }
        }
        return buffer
    }

    private func makeMeta(cfa: OSType, width: Int, height: Int, bytesPerRow: Int) -> FrameMeta {
        FrameMeta(
            blackLevel: [528, 528, 528, 528],
            whiteLevel: 4095,
            wbNeutral: [1, 1, 1],
            noise: Array(repeating: (s: 0.001, o: 0.0), count: 4),
            exposureSec: 1.0 / 60.0,
            iso: 100,
            cfa: cfa,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            noiseIsFallback: false
        )
    }

    func testReducer_recoversPerChannelDN_allCFAVariants() throws {
        // 128×128 → side=128, block=(128/64)&~1=2, count per channel = 1.
        let w = 128, h = 128
        for c in cfaCases {
            guard let buffer = makeBayerBuffer(width: w, height: h, format: c.format) else {
                throw XCTSkip("CVPixelBufferCreate does not support \(c.name) on this host")
            }
            let payload = RawFramePayload(
                slot: 0,
                buffer: buffer,
                meta: makeMeta(cfa: c.format, width: w, height: h,
                               bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)),
                hwTimestampNs: 0
            )
            let stats = try XCTUnwrap(BayerCellReducer.reduce(payload), "\(c.name): reduce failed")
            XCTAssertEqual(stats.blockSize, 2, c.name)
            XCTAssertEqual(stats.countPerChannel, 1, c.name)
            XCTAssertEqual(stats.cropX % 2, 0, c.name)
            XCTAssertEqual(stats.cropY % 2, 0, c.name)
            for cell in 0..<(64 * 64) {
                for ch in 0..<4 {
                    XCTAssertEqual(stats.sum[cell * 4 + ch], UInt64(channelDN[ch]),
                                   "\(c.name): cell \(cell) channel \(ch)")
                    XCTAssertEqual(stats.sumSq[cell * 4 + ch],
                                   UInt64(channelDN[ch]) * UInt64(channelDN[ch]),
                                   "\(c.name): sumSq cell \(cell) channel \(ch)")
                }
            }
        }
    }

    func testReducer_rejectsFormatMismatch() throws {
        let w = 128, h = 128
        guard let buffer = makeBayerBuffer(width: w, height: h,
                                           format: kCVPixelFormatType_14Bayer_BGGR) else {
            throw XCTSkip("CVPixelBufferCreate does not support bgg4 on this host")
        }
        // Metadata claims RGGB, buffer is BGGR → mid-burst CFA change guard.
        let payload = RawFramePayload(
            slot: 3,
            buffer: buffer,
            meta: makeMeta(cfa: kCVPixelFormatType_14Bayer_RGGB, width: w, height: h,
                           bytesPerRow: CVPixelBufferGetBytesPerRow(buffer)),
            hwTimestampNs: 0
        )
        XCTAssertNil(BayerCellReducer.reduce(payload))
    }
}
