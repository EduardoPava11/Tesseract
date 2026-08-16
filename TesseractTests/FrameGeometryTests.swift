// FrameGeometryTests.swift
// Tesseract
//
// The middle leg of a three-port law. spec/output/FrameGeometry.hs is
// authoritative (G1-G7, G11-G13); this pins Signal/FrameGeometry.swift
// to it; MetalGeometryParityTests pins Solve/Quantize.metal to this.
//
// Before 2026-08-15 the middle leg did not exist: the spec was green
// and its only reader was a Metal kernel that computed the arithmetic
// inline, so "the Swift" was a comment in a shader.

import XCTest
@testable import Tesseract

final class FrameGeometryTests: XCTestCase {

    private let n = 64

    // MARK: - G1 to G4: the crop and its integer steps

    func testCropAndStepsMatchTheSpec() {
        XCTAssertEqual(FrameGeometry.rgbCrop, 768)
        XCTAssertEqual(FrameGeometry.depthCrop, 256)
        XCTAssertEqual(FrameGeometry.scaleFactor, 3)
        for size in [64, 128, 256] {
            // G2: integer division at every output size.
            XCTAssertEqual(FrameGeometry.rgbCrop % size, 0)
            XCTAssertEqual(FrameGeometry.depthCrop % size, 0)
            // G3: rgbStep = depthStep × 3.
            XCTAssertEqual(FrameGeometry.rgbStep(outputSize: size),
                           FrameGeometry.depthStep(outputSize: size)
                             * FrameGeometry.scaleFactor)
            // G4: exact tiling, step × outSize = crop.
            XCTAssertEqual(FrameGeometry.rgbStep(outputSize: size) * size,
                           FrameGeometry.rgbCrop)
            XCTAssertEqual(FrameGeometry.depthStep(outputSize: size) * size,
                           FrameGeometry.depthCrop)
        }
        XCTAssertEqual(FrameGeometry.rgbStep(outputSize: 64), 12)
        XCTAssertEqual(FrameGeometry.depthStep(outputSize: 64), 4)
    }

    func testCropIsCentredInWhateverTheSensorGives() {
        // The sensor dims are unknown at spec time; the crop centres.
        let a = FrameGeometry.rgbCropOffset(sensorW: 1080, sensorH: 1920)
        XCTAssertEqual(a.x, (1080 - 768) / 2)
        XCTAssertEqual(a.y, (1920 - 768) / 2)
        let b = FrameGeometry.depthCropOffset(sensorW: 360, sensorH: 640)
        XCTAssertEqual(b.x, (360 - 256) / 2)
        XCTAssertEqual(b.y, (640 - 256) / 2)
    }

    // MARK: - G7: block spacing is exactly step

    func testBlockSpacingIsExactlyStep() {
        let step = FrameGeometry.rgbStep(outputSize: n)
        let s0 = FrameGeometry.sourceRGBUnrotated(x: 0, y: 0, outputSize: n, crop: (0, 0))
        let s1 = FrameGeometry.sourceRGBUnrotated(x: 1, y: 0, outputSize: n, crop: (0, 0))
        XCTAssertEqual(s1.x - s0.x, step)
        // The half step puts the read at the block's centre, not corner.
        XCTAssertEqual(s0.x, step / 2)
        XCTAssertEqual(s0.y, step / 2)
    }

    // MARK: - ★ G11 to G13: the rotation, stated at last

    /// G12: four quarter turns are the identity, and one is not.
    func testTheTurnHasOrderExactlyFour() {
        for y in 0..<n {
            for x in 0..<n {
                var p = (x: x, y: y)
                for _ in 0..<4 { p = FrameGeometry.rotateCCW(x: p.x, y: p.y, outputSize: n) }
                XCTAssertEqual(p.x, x); XCTAssertEqual(p.y, y)
            }
        }
        // The corner moves. (0,0) goes to (0, n-1): x is FIXED and y
        // travels, which is what a quarter turn about the grid does to
        // that particular corner and is worth pinning as data rather
        // than asserting loosely.
        let once = FrameGeometry.rotateCCW(x: 0, y: 0, outputSize: n)
        XCTAssertEqual(once.x, 0)
        XCTAssertEqual(once.y, n - 1)
        XCTAssertFalse(once.x == 0 && once.y == 0, "one turn is not the identity")
        // Two turns is the point reflection.
        let twice = FrameGeometry.rotateCCW(x: once.x, y: once.y, outputSize: n)
        XCTAssertEqual(twice.x, n - 1 - 0)
        XCTAssertEqual(twice.y, n - 1 - 0)
    }

    /// G11: the rotation is a bijection of the output grid, so the
    /// rotated read visits exactly the block centres the unrotated one
    /// would, each once. Whatever else it is, it loses nothing.
    func testTheTurnIsABijectionSoNoSignalIsLost() {
        var rotated = Set<String>()
        var plain = Set<String>()
        for y in 0..<n {
            for x in 0..<n {
                let r = FrameGeometry.sourceRGB(x: x, y: y, outputSize: n, crop: (0, 0))
                let u = FrameGeometry.sourceRGBUnrotated(x: x, y: y, outputSize: n,
                                                         crop: (0, 0))
                rotated.insert("\(r.x),\(r.y)")
                plain.insert("\(u.x),\(u.y)")
            }
        }
        XCTAssertEqual(rotated.count, n * n)
        XCTAssertEqual(rotated, plain)
    }

    /// G13: RGB and depth take the SAME turn, which is why G6's
    /// alignment survives it. A quarter turn applied to one stream and
    /// not the other would read every pixel's depth from the wrong
    /// place, silently.
    func testRGBAndDepthTakeTheSameTurn() {
        let rc = FrameGeometry.rgbCropOffset(sensorW: 1080, sensorH: 1920)
        let dc = FrameGeometry.depthCropOffset(sensorW: 360, sensorH: 640)
        let scale = FrameGeometry.scaleFactor
        for y in 0..<n {
            for x in 0..<n {
                let r = FrameGeometry.sourceRGB(x: x, y: y, outputSize: n, crop: rc)
                let d = FrameGeometry.sourceDepth(x: x, y: y, outputSize: n, crop: dc)
                XCTAssertLessThanOrEqual(abs((r.x - rc.x) - (d.x - dc.x) * scale), scale)
                XCTAssertLessThanOrEqual(abs((r.y - rc.y) - (d.y - dc.y) * scale), scale)
            }
        }
    }

    // MARK: - ★ The stratum's rate, and what KIND it is

    func testTheEntranceIsADiscardNotASummary() {
        XCTAssertEqual(FrameGeometry.rgbDecimation(outputSize: 64), 144)
        XCTAssertEqual(FrameGeometry.depthDecimation(outputSize: 64), 16)
        XCTAssertEqual(FrameGeometry.samplesDiscardedPerOutputPixel(outputSize: 64), 143)

        // The box mean is a function of all 144; the point sample is
        // one of them. On a field that varies inside a block they must
        // differ, or "summarize" would mean nothing.
        let side = 768
        var ramp = [(Float, Float, Float)]()
        ramp.reserveCapacity(side * side)
        for p in 0..<(side * side) {
            let v = Float(p % side) / Float(side)
            ramp.append((v, v, v))
        }
        let mean = FrameGeometry.boxMean(source: ramp, sourceSide: side,
                                         x: 0, y: 0, outputSize: 64, crop: (0, 0))
        let s = FrameGeometry.sourceRGB(x: 0, y: 0, outputSize: 64, crop: (0, 0))
        let point = ramp[s.y * side + s.x]
        XCTAssertNotEqual(mean.0, point.0, accuracy: 0)

        // On a constant field they agree exactly: the divergence is a
        // property of the SIGNAL, not an artifact of the arithmetic.
        let flat = [(Float, Float, Float)](repeating: (0.25, 0.5, 0.75),
                                           count: side * side)
        let fm = FrameGeometry.boxMean(source: flat, sourceSide: side,
                                       x: 7, y: 11, outputSize: 64, crop: (0, 0))
        XCTAssertEqual(fm.0, 0.25, accuracy: 1e-6)
        XCTAssertEqual(fm.1, 0.5, accuracy: 1e-6)
        XCTAssertEqual(fm.2, 0.75, accuracy: 1e-6)
    }
}
