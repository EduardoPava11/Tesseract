// DNGPipelineTests.swift
// Tesseract
//
// Pure-logic tests for the DNG streaming pipeline core: rung math,
// palette quantization, histogram conservation, binomial null-model
// formulas, and the box-reduce boundary math mirrored from the Metal
// kernel. No camera, no Metal.

import XCTest
@testable import Tesseract

final class DNGPipelineTests: XCTestCase {

    // MARK: - Rung ladder math

    func testRungSides() {
        XCTAssertEqual(DNGRung.allCases.map(\.side), [64, 256, 1024])
    }

    func testRungIndexByteBudget() {
        // index bytes per burst = S² × 64 — the memory-budget table.
        XCTAssertEqual(DNGRung.r64.indexBytesPerBurst, 262_144)          // 0.25 MB
        XCTAssertEqual(DNGRung.r256.indexBytesPerBurst, 4_194_304)       // 4 MB
        XCTAssertEqual(DNGRung.r1024.indexBytesPerBurst, 67_108_864)     // 64 MiB ceiling
        // The next rung up would be 4096² × 64 = 1 GiB — archival-only,
        // deliberately NOT in the ladder.
        XCTAssertEqual(4096 * 4096 * 64, 1 << 30)
        XCTAssertFalse(DNGRung.allCases.map(\.rawValue).contains(4096))
    }

    func testRungGIFUpscaleHonors256Floor() {
        XCTAssertEqual(DNGRung.r64.gifUpscale, 4)     // 64 × 4 = 256² floor
        XCTAssertEqual(DNGRung.r256.gifUpscale, 1)    // rung IS the output
        XCTAssertEqual(DNGRung.r1024.gifUpscale, 1)
        for rung in DNGRung.allCases {
            XCTAssertGreaterThanOrEqual(rung.side * rung.gifUpscale, 256)
        }
    }

    // MARK: - Box-reduce boundary math (mirrors boxReduceRGB in Metal)

    func testBoxBoundsPartitionExactly() {
        // Every source pixel lands in exactly one box, for the real
        // geometries: native 3022 (binned 3024 minus parity slack) → rungs.
        for (n, s) in [(3022, 64), (3022, 256), (3022, 1024), (256, 64), (64, 64)] {
            var covered = 0
            var prevHi = 0
            for o in 0..<s {
                let (lo, hi) = DNGPipeline.boxBounds(o, from: n, to: s)
                XCTAssertEqual(lo, prevHi, "boxes must tile with no gap/overlap (N=\(n) S=\(s) o=\(o))")
                XCTAssertGreaterThan(hi, lo, "every box needs ≥ 1 px")
                covered += hi - lo
                prevHi = hi
            }
            XCTAssertEqual(prevHi, n, "last box must end at N")
            XCTAssertEqual(covered, n, "boxes must cover all N rows/cols")
        }
    }

    func testBoxBoundsFractionalRatioWidths() {
        // 3024/1024 = 2.95: boxes are 2 or 3 px wide, never anything else.
        let n = 3022, s = 1024
        for o in 0..<s {
            let (lo, hi) = DNGPipeline.boxBounds(o, from: n, to: s)
            XCTAssertTrue((2...3).contains(hi - lo), "width \(hi - lo) at o=\(o)")
        }
    }

    // MARK: - Palette quantization

    func testPaletteIndexLevelBucketing() {
        // level = floor(v·4) IS nearest-of-{32, 96, 159, 223} bucketing:
        // boundaries at 0.25 / 0.5 / 0.75.
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 0.0, g: 0.0, b: 0.0, frame: 0), 0)
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 0.24, g: 0.0, b: 0.0, frame: 0), 0)
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 0.26, g: 0.0, b: 0.0, frame: 0), 16)   // a=1
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 0.0, g: 0.51, b: 0.0, frame: 0), 8)    // b=2
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 0.0, g: 0.0, b: 0.76, frame: 0), 3)    // c=3
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 1.0, g: 1.0, b: 1.0, frame: 0), 63)    // white, epoch 0
        // Out-of-range inputs clamp.
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 2.0, g: -1.0, b: 0.0, frame: 0), 48)
    }

    func testPaletteIndexEpochAxis() {
        // d = frame / 16: index = d·64 + a·16 + b·4 + c.
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 0, g: 0, b: 0, frame: 0), 0)
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 0, g: 0, b: 0, frame: 15), 0)
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 0, g: 0, b: 0, frame: 16), 64)
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 0, g: 0, b: 0, frame: 32), 128)
        XCTAssertEqual(DNGPipeline.paletteIndex(r: 0, g: 0, b: 0, frame: 63), 192)
        // Round-trip through TesseractCoord.
        let idx = DNGPipeline.paletteIndex(r: 0.9, g: 0.4, b: 0.1, frame: 40)
        let coord = TesseractCoord(index: idx)
        XCTAssertEqual(coord.d, 2)
        XCTAssertEqual(coord.a, 3)
        XCTAssertEqual(coord.b, 1)
        XCTAssertEqual(coord.c, 0)
    }

    // MARK: - Histogram conservation

    func testHistogramSumsToPixelCount() {
        let side = 64   // S² = 4096, small enough for a fast test
        var rgb = [Float](repeating: 0, count: side * side * 3)
        // Deterministic pseudo-content spanning many palette cells.
        for i in 0..<(side * side) {
            rgb[i * 3]     = Float(i % 17) / 16.0
            rgb[i * 3 + 1] = Float(i % 5) / 4.0
            rgb[i * 3 + 2] = Float(i % 3) / 2.0
        }
        let (indices, counts, _) = DNGPipeline.processFrame(rgb: rgb, side: side, frame: 7)
        XCTAssertEqual(indices.count, side * side)
        XCTAssertEqual(counts.count, 256)
        XCTAssertEqual(counts.reduce(0, +), side * side, "histogram must sum to S²")
        // Frame 7 → epoch 0: all indices < 64.
        XCTAssertTrue(indices.allSatisfy { $0 < 64 })
    }

    // MARK: - Binomial null model

    func testBinomialFormulas() {
        // B(S², 1/256): mean = S²/256, variance = S² · (1/256) · (255/256).
        for side in [64, 256, 1024] {
            let pixels = side * side
            let stats = DNGPipeline.binomialStats(
                counts: [Int](repeating: pixels / 256, count: 256),
                pixels: pixels,
                frame: 0
            )
            XCTAssertEqual(stats.expectedMean, Double(pixels) / 256.0, accuracy: 1e-9)
            XCTAssertEqual(
                stats.expectedVariance,
                Double(pixels) * (1.0 / 256.0) * (255.0 / 256.0),
                accuracy: 1e-9
            )
            // Perfectly uniform counts: zero observed variance and deviation.
            XCTAssertEqual(stats.observedVariance, 0, accuracy: 1e-9)
            XCTAssertEqual(stats.deviation, 0, accuracy: 1e-9)
            XCTAssertEqual(stats.varianceRatio, 0, accuracy: 1e-9)
        }
    }

    func testBinomialDeviationForConcentratedHistogram() {
        // All S² pixels in one bin — maximal structure, huge deviation.
        let pixels = 4096
        var counts = [Int](repeating: 0, count: 256)
        counts[42] = pixels
        let stats = DNGPipeline.binomialStats(counts: counts, pixels: pixels, frame: 3)
        let mu = Double(pixels) / 256.0
        // Σ(c−μ)² = (pixels−μ)² + 255·μ²
        let expectedSumSq = (Double(pixels) - mu) * (Double(pixels) - mu) + 255.0 * mu * mu
        XCTAssertEqual(stats.deviation, expectedSumSq.squareRoot(), accuracy: 1e-6)
        XCTAssertEqual(stats.observedVariance, expectedSumSq / 256.0, accuracy: 1e-6)
        XCTAssertGreaterThan(stats.varianceRatio, 100, "concentration must dwarf binomial noise")
        XCTAssertEqual(stats.frame, 3)
    }

    // MARK: - Finish (GIF contract at rung size)

    func testFinishEncodesRungSizedGIF() throws {
        // 4 tiny frames at S=64 → upscale 4 → 256² GIF, 5 cs delay.
        let side = 64
        let frames = (0..<4).map { f in
            (0..<(side * side)).map { UInt8(($0 + f) % 256) }
        }
        let histograms = frames.map { DNGPipeline.histogram($0) }
        let binomial = histograms.map {
            DNGPipeline.binomialStats(counts: $0, pixels: side * side, frame: 0)
        }
        let result = DNGPipeline.finish(
            indexFrames: frames,
            histograms: histograms,
            binomial: binomial,
            rung: .r64,
            nativeSide: 3022,
            hwTimestampsNs: [0, 90_000_000, 180_000_000, 270_000_000],
            skippedSlots: 0,
            iso: 100,
            exposureSec: 1.0 / 120.0,
            cfaFourCC: 0,
            sensorWidth: 4224,
            sensorHeight: 3024,
            progress: { _, _ in }
        )
        let r = try result.get()
        let b = [UInt8](r.gifData)
        XCTAssertEqual(Array(b[0..<6]), [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], "GIF89a")
        XCTAssertEqual(Int(b[6]) | (Int(b[7]) << 8), 256, "width = rung × upscale")
        XCTAssertEqual(Int(b[8]) | (Int(b[9]) << 8), 256, "height = rung × upscale")
        XCTAssertEqual(Data(b[13..<(13 + 768)]), TesseractPalette.gifColorTable)
        // λ trajectory: one triple per frame, partition of unity.
        XCTAssertEqual(r.stats.lambdas.count, 4)
        for l in r.stats.lambdas {
            XCTAssertEqual(l.x + l.y + l.z, 1.0, accuracy: 1e-9)
        }
        XCTAssertEqual(r.stats.rung, .r64)
        XCTAssertEqual(r.stats.binomial.count, 4)
        XCTAssertEqual(r.stats.burstDurationSec, 0.27, accuracy: 1e-9)
    }
}
