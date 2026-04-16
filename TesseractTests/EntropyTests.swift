// EntropyTests.swift
// Tesseract
//
// Tests for EntropyMeasure — feedback from palette distribution.
// Matches Gene.hs axioms G12, G13.

import XCTest
@testable import Tesseract

final class EntropyTests: XCTestCase {

    // ── G13: uniform distribution → entropy = 1.0 ──

    func testEntropy_uniformIsOne() {
        // 4096 pixels, each palette entry used exactly 16 times
        var indices = [UInt8]()
        for i in 0..<256 {
            indices.append(contentsOf: [UInt8](repeating: UInt8(i), count: 16))
        }
        let ef = EntropyMeasure.compute(paletteIndices: indices)
        XCTAssertEqual(ef.epoch, 1.0, accuracy: 0.01, "Uniform epoch entropy should be ~1.0")
        XCTAssertEqual(ef.r, 1.0, accuracy: 0.01, "Uniform R entropy should be ~1.0")
        XCTAssertEqual(ef.g, 1.0, accuracy: 0.01, "Uniform G entropy should be ~1.0")
        XCTAssertEqual(ef.b, 1.0, accuracy: 0.01, "Uniform B entropy should be ~1.0")
        XCTAssertEqual(ef.joint, 1.0, accuracy: 0.01, "Uniform joint entropy should be ~1.0")
    }

    // ── Single color → entropy near 0 ──

    func testEntropy_singleColorIsZero() {
        // All pixels mapped to palette index 0 (d=0, a=0, b=0, c=0)
        let indices = [UInt8](repeating: 0, count: 4096)
        let ef = EntropyMeasure.compute(paletteIndices: indices)
        XCTAssertEqual(ef.epoch, 0.0, accuracy: 1e-6, "Single epoch → H=0")
        XCTAssertEqual(ef.r, 0.0, accuracy: 1e-6, "Single R level → H=0")
        XCTAssertEqual(ef.g, 0.0, accuracy: 1e-6, "Single G level → H=0")
        XCTAssertEqual(ef.b, 0.0, accuracy: 1e-6, "Single B level → H=0")
        XCTAssertEqual(ef.joint, 0.0, accuracy: 1e-6, "Single index → H=0")
    }

    // ── G12: all values ∈ [0,1] ──

    func testEntropy_inRange() {
        // Random-ish distribution
        var indices = [UInt8]()
        for i in 0..<4096 {
            indices.append(UInt8(i % 256))
        }
        let ef = EntropyMeasure.compute(paletteIndices: indices)
        for (name, val) in [("epoch", ef.epoch), ("r", ef.r), ("g", ef.g),
                             ("b", ef.b), ("joint", ef.joint)] {
            XCTAssertGreaterThanOrEqual(val, 0.0, "\(name) must be ≥ 0")
            XCTAssertLessThanOrEqual(val, 1.0, "\(name) must be ≤ 1")
        }
    }

    // ── Marginals sum correctly ──

    func testEntropy_marginalsSumCorrectly() {
        // 1024 pixels split: 256 per epoch
        var indices = [UInt8]()
        for d in 0..<4 {
            for _ in 0..<256 {
                // Vary color within each epoch
                let a = Int.random(in: 0...3)
                let b = Int.random(in: 0...3)
                let c = Int.random(in: 0...3)
                indices.append(UInt8(d * 64 + a * 16 + b * 4 + c))
            }
        }
        let ef = EntropyMeasure.compute(paletteIndices: indices)
        // Epochs are uniform (256 each) → epoch entropy should be near 1.0
        XCTAssertEqual(ef.epoch, 1.0, accuracy: 0.01,
                       "Equal epoch counts → entropy ~1.0")
    }

    // ── EntropyFeedback.uniform is all 1.0 ──

    func testEntropyFeedback_uniform() {
        let ef = EntropyFeedback.uniform
        XCTAssertEqual(ef.epoch, 1.0)
        XCTAssertEqual(ef.r, 1.0)
        XCTAssertEqual(ef.g, 1.0)
        XCTAssertEqual(ef.b, 1.0)
        XCTAssertEqual(ef.joint, 1.0)
        XCTAssertEqual(ef.asArray.count, 5)
    }
}
