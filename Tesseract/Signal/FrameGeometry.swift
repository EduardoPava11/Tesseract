// FrameGeometry.swift
// Tesseract
//
// ★ THE FUNNEL'S ENTRANCE, AND UNTIL NOW ITS ONLY UNPORTED LAW.
//
// Port of spec/output/FrameGeometry.hs (G1-G7, G11-G13). The Haskell
// is authoritative; FrameGeometryTests pins this to it and
// MetalGeometryParityTests pins Solve/Quantize.metal to this, so one
// law finally has three agreeing ports instead of two ports and a
// comment.
//
// ★ WHY IT EXISTS NOW. The spec has been green since it was written
// and had NO Swift port at all: the only reader of this arithmetic was
// the Metal kernel, which computed it inline. That kernel's header
// says "Verified by Haskell axioms G5-G10 for all 4096 output pixels",
// and that verification was VACUOUS in a specific way worth
// remembering: G5 is about bounds, G6 about alignment, G7 about
// spacing, and every one of them is invariant under any relabelling of
// the output grid. The kernel applies a 90 degree rotation that the
// spec's own `rgbSource` does not, and no axiom could have noticed,
// because none of them discriminate a rotation. G11-G13 were added to
// close that, and this file is what makes them checkable against
// running code.
//
// ★ WHAT IT MEASURES, FOR THE LEDGER. This is stratum S0 and it is the
// steepest step in the whole pipeline: 768x768 RGB to 64x64 is 144:1,
// 256x256 depth to 64x64 is 16:1. But read `sourceRGB` and notice what
// KIND of 144:1 it is. It returns ONE coordinate, and the kernel does
// one `texture.read` there. 143 of every 144 photons the sensor
// reported are not averaged into the answer, they are DISCARDED. That
// is a decimation, not a summarization, and the difference is
// measurable: FunnelLedger reports both, and a point sample and a box
// mean of the same frame carry visibly different energy.

import Foundation

enum FrameGeometry {

    // MARK: - The universal crop (G1)

    static let rgbCrop = 768
    static let depthCrop = 256
    static let scaleFactor = 3

    static func rgbStep(outputSize: Int) -> Int { rgbCrop / outputSize }
    static func depthStep(outputSize: Int) -> Int { depthCrop / outputSize }

    /// The crop is centred in whatever the sensor buffer turns out to
    /// be, which is not known until the device runs.
    static func rgbCropOffset(sensorW: Int, sensorH: Int) -> (x: Int, y: Int) {
        ((sensorW - rgbCrop) / 2, (sensorH - rgbCrop) / 2)
    }

    static func depthCropOffset(sensorW: Int, sensorH: Int) -> (x: Int, y: Int) {
        ((sensorW - depthCrop) / 2, (sensorH - depthCrop) / 2)
    }

    // MARK: - The unrotated law (G4, G7)

    /// The spec's `rgbSource`: output (x, y) to the centre of its
    /// source block. No rotation.
    static func sourceRGBUnrotated(x: Int, y: Int, outputSize: Int,
                                   crop: (x: Int, y: Int)) -> (x: Int, y: Int) {
        let step = rgbStep(outputSize: outputSize)
        return (crop.x + x * step + step / 2, crop.y + y * step + step / 2)
    }

    static func sourceDepthUnrotated(x: Int, y: Int, outputSize: Int,
                                     crop: (x: Int, y: Int)) -> (x: Int, y: Int) {
        let step = depthStep(outputSize: outputSize)
        return (crop.x + x * step + step / 2, crop.y + y * step + step / 2)
    }

    // MARK: - ★ The rotation (G11, G12, G13)

    /// The 90 degree counter-clockwise relabelling of the OUTPUT grid.
    /// It exists because `videoRotationAngle = 90` reports portrait
    /// dimensions while the pixel memory may still be landscape, so
    /// the turn is taken in the read rather than in a copy.
    ///
    /// G11: it is a bijection of the grid, so it moves no information.
    /// G12: it has order exactly four.
    static func rotateCCW(x: Int, y: Int, outputSize: Int) -> (x: Int, y: Int) {
        (y, outputSize - 1 - x)
    }

    /// ★ WHAT THE SHIPPED KERNEL ACTUALLY COMPUTES. Both streams take
    /// the same turn (G13); if only one did, the role law would read
    /// depth from a place a quarter turn away from its colour, and it
    /// would do it silently.
    static func sourceRGB(x: Int, y: Int, outputSize: Int,
                          crop: (x: Int, y: Int)) -> (x: Int, y: Int) {
        let r = rotateCCW(x: x, y: y, outputSize: outputSize)
        return sourceRGBUnrotated(x: r.x, y: r.y, outputSize: outputSize, crop: crop)
    }

    static func sourceDepth(x: Int, y: Int, outputSize: Int,
                            crop: (x: Int, y: Int)) -> (x: Int, y: Int) {
        let r = rotateCCW(x: x, y: y, outputSize: outputSize)
        return sourceDepthUnrotated(x: r.x, y: r.y, outputSize: outputSize, crop: crop)
    }

    // MARK: - The rate this stratum declares (RateLadder S0)

    /// Source samples per output sample. 144 for RGB at 64², which is
    /// RL2's audit factor, and 16 for depth.
    static func rgbDecimation(outputSize: Int) -> Int {
        let s = rgbStep(outputSize: outputSize)
        return s * s
    }

    static func depthDecimation(outputSize: Int) -> Int {
        let s = depthStep(outputSize: outputSize)
        return s * s
    }

    /// ★ THE HONEST NAME FOR WHAT S0 DOES. `sourceRGB` reads one texel
    /// per output pixel, so the stratum passes 1 sample and drops
    /// `rgbDecimation - 1`. A box mean over the same block would pass
    /// one sample too, but it would be a FUNCTION of all 144 rather
    /// than one of them. Both are 144:1 by the rate ladder's
    /// bookkeeping; only one of them is a summary.
    static func samplesDiscardedPerOutputPixel(outputSize: Int) -> Int {
        rgbDecimation(outputSize: outputSize) - 1
    }

    /// The box mean the point sample is not. Offered as the MEASURING
    /// STICK the ledger compares against, not as a second capture
    /// path: nothing here writes a byte the app exports.
    static func boxMean(source: [(Float, Float, Float)], sourceSide: Int,
                        x: Int, y: Int, outputSize: Int,
                        crop: (x: Int, y: Int)) -> (Float, Float, Float) {
        let step = rgbStep(outputSize: outputSize)
        let r = rotateCCW(x: x, y: y, outputSize: outputSize)
        let x0 = crop.x + r.x * step, y0 = crop.y + r.y * step
        var acc = (Float(0), Float(0), Float(0))
        var n: Float = 0
        for dy in 0..<step {
            for dx in 0..<step {
                let sx = x0 + dx, sy = y0 + dy
                guard sx >= 0, sx < sourceSide, sy >= 0, sy < sourceSide else { continue }
                let p = source[sy * sourceSide + sx]
                acc = (acc.0 + p.0, acc.1 + p.1, acc.2 + p.2)
                n += 1
            }
        }
        guard n > 0 else { return (0, 0, 0) }
        return (acc.0 / n, acc.1 / n, acc.2 / n)
    }
}
