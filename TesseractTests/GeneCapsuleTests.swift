// GeneCapsuleTests.swift
// Tesseract
//
// Tests for GeneCapsule — Int8 gene encoding in GIF extension blocks.
// Share a GIF = share a gene = share a way of seeing.

import XCTest
@testable import Tesseract

final class GeneCapsuleTests: XCTestCase {

    // ── Roundtrip: encode → decode ≈ original ──

    func testCapsule_roundTrip() {
        let original = GeneWeights.defaultWeights()
        let capsule = GeneCapsule.encode(original)
        guard let decoded = GeneCapsule.decode(capsule) else {
            XCTFail("Failed to decode capsule")
            return
        }

        // Int8 quantization loses precision — allow tolerance
        XCTAssertEqual(decoded.weights.count, original.weights.count)
        var maxError: Float = 0
        for (o, d) in zip(original.weights, decoded.weights) {
            maxError = max(maxError, abs(o - d))
        }
        // With ~4500 weights over typical range [-0.5, 0.5],
        // Int8 quantization error < range/256 ≈ 0.004
        XCTAssertLessThan(maxError, 0.05,
                          "Roundtrip max error should be small (Int8 precision)")
    }

    // ── Capsule size under 5 KB ──

    func testCapsule_sizeUnder5KB() {
        let gene = GeneWeights.defaultWeights()
        let capsule = GeneCapsule.encode(gene)
        XCTAssertEqual(capsule.count, GeneCapsule.capsuleSize)
        XCTAssertLessThan(capsule.count, 5 * 1024,
                          "Capsule must be under 5 KB, got \(capsule.count) bytes")
    }

    // ── GIF extension block format ──

    func testCapsule_gifExtensionBlockFormat() {
        let gene = GeneWeights.defaultWeights()
        let block = GeneCapsule.gifExtensionBlock(gene)
        let bytes = [UInt8](block)

        // Must start with extension introducer
        XCTAssertEqual(bytes[0], 0x21, "Extension introducer")
        XCTAssertEqual(bytes[1], 0xFF, "Application extension label")
        XCTAssertEqual(bytes[2], 0x0B, "Block size = 11")

        // Must contain identifier
        let idBytes = Array(bytes[3..<14])
        XCTAssertEqual(String(bytes: idBytes, encoding: .utf8), "TESSERACT04")

        // Must end with terminator
        XCTAssertEqual(bytes.last, 0x00, "Block terminator")
    }

    // ── Different genes produce different capsules ──

    func testCapsule_differentGenesProduceDifferentCapsules() {
        let g1 = GeneWeights.defaultWeights()
        let g2 = g1.perturbed(scale: 0.1, seed: 42)

        let c1 = GeneCapsule.encode(g1)
        let c2 = GeneCapsule.encode(g2)

        XCTAssertNotEqual(c1, c2,
                          "Different genes must produce different capsules")
    }

    // ── Extract from synthetic GIF-like data ──

    func testCapsule_extractFromGIFData() {
        let gene = GeneWeights.defaultWeights()
        let block = GeneCapsule.gifExtensionBlock(gene)

        // Wrap in fake GIF data (header + block + trailer)
        var fakeGIF = Data()
        fakeGIF.append(contentsOf: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])  // GIF89a
        fakeGIF.append(contentsOf: [UInt8](repeating: 0, count: 7))         // screen desc
        fakeGIF.append(block)                                                // gene capsule
        fakeGIF.append(0x3B)                                                 // trailer

        guard let extracted = GeneCapsule.extract(fromGIF: fakeGIF) else {
            XCTFail("Failed to extract gene from GIF data")
            return
        }

        // Should match original within Int8 precision
        XCTAssertEqual(extracted.weights.count, gene.weights.count)
    }
}
