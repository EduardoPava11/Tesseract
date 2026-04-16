// LevelTests.swift
// Tesseract
//
// Tests for CubeMode + BinomialCadence scaling.
// Matches Block.hs axioms C1, C3, C14.

import XCTest
@testable import Tesseract

final class LevelTests: XCTestCase {

    // ── C1: S = K (cube invariant) ──

    func testCube_SEqualsK() {
        for mode in CubeMode.allCases {
            XCTAssertEqual(mode.spatialSide, mode.frameCount,
                           "\(mode): S must equal K (cube)")
        }
    }

    // ── C3: 4 divides K (epochs work) ──

    func testFrameCount_divisibleBy4() {
        for mode in CubeMode.allCases {
            XCTAssertEqual(mode.frameCount % 4, 0,
                           "\(mode): frame count \(mode.frameCount) must be divisible by 4")
        }
    }

    // ── C12: frames per epoch ──

    func testFramesPerEpoch_matchesMode() {
        XCTAssertEqual(CubeMode.training.framesPerEpoch, 16)
        XCTAssertEqual(CubeMode.inference.framesPerEpoch, 32)
    }

    // ── σ_base scales with K ──

    func testSigmaBase_scalesWithK() {
        // Save current level, test each, restore
        let saved = CameraConfig.mode

        for level in CubeMode.allCases {
            CameraConfig.mode = level
            let expected = Float(level.frameCount - 1) / 8.0
            XCTAssertEqual(BinomialCadence.sigmaBase, expected, accuracy: 1e-6,
                           "\(level): σ_base should be (K-1)/8 = \(expected)")
        }

        CameraConfig.mode = saved
    }

    // ── Epoch centers scale proportionally ──

    func testEpochCenters_scaleWithK() {
        let saved = CameraConfig.mode

        for level in CubeMode.allCases {
            CameraConfig.mode = level
            let sb = BinomialCadence.sigmaBase
            let centers = BinomialCadence.centers

            // Centers should be at (2d+1) × σ_base
            XCTAssertEqual(centers[0], 1 * sb, accuracy: 1e-6)
            XCTAssertEqual(centers[1], 3 * sb, accuracy: 1e-6)
            XCTAssertEqual(centers[2], 5 * sb, accuracy: 1e-6)
            XCTAssertEqual(centers[3], 7 * sb, accuracy: 1e-6)

            // Last center should be < K (within the frame range)
            XCTAssertLessThan(centers[3], Float(level.frameCount),
                              "\(level): last epoch center must be < K")
        }

        CameraConfig.mode = saved
    }

    // ── Epoch probabilities sum to 1 at all levels ──

    func testEpochProbs_sumToOne() {
        let saved = CameraConfig.mode

        for level in CubeMode.allCases {
            CameraConfig.mode = level
            let k = level.frameCount
            for z in [0, k/4, k/2, k-1] {
                for depth: Float in [0.0, 0.5, 1.0] {
                    let probs = BinomialCadence.epochProbabilities(frame: z, depth: depth)
                    let sum = probs[0] + probs[1] + probs[2] + probs[3]
                    XCTAssertEqual(sum, 1.0, accuracy: 1e-5,
                                   "\(level) z=\(z) d=\(depth): probs must sum to 1, got \(sum)")
                }
            }
        }

        CameraConfig.mode = saved
    }
}
