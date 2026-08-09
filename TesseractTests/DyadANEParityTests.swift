// DyadANEParityTests.swift
// Tesseract
//
// ANE ↔ CPU parity for the DYAD assignment stage, per the placement
// laws (spec/output/ExportMethods.hs XP1–XP2): role laws must hold
// exactly on both engines — face → primaries, bleed band → σ-half,
// fully pulled background → 255 — and every disagreement must be a
// near-tie (winning gap ≤ 2δ). Skips when DyadAssign.mlmodelc is not
// bundled. On simulator CoreML runs on CPU compute units —
// correctness is verified here; ANE placement and latency belong to
// the device pass.

import XCTest
@testable import Tesseract

final class DyadANEParityTests: XCTestCase {

    private static let delta = 1e-3   // fp16 perturbation bound (spec §5)

    func testANEMatchesCPUUpToNearTies() throws {
        try XCTSkipUnless(DyadANE.isAvailable, "DyadAssign.mlmodelc not bundled")

        let F = DyadANE.frameCount
        let P = DyadANE.pixelCount
        let side = Int(Double(P).squareRoot())

        // Synthetic capture with all three depth zones:
        // face disk (d=0.9), bleed ring (d=0.55), far field (d=0.2).
        var labs: [[OKLabColor]] = []
        var primaries: [[OKLabColor]] = []
        var masks: [[Bool]] = []
        var fars: [[Bool]] = []
        var seed = 7
        func next() -> Double {
            seed = (1103515245 * seed + 12345) % 2147483648
            return Double(seed) / 2147483648.0
        }
        let baseSamples: [(UInt8, UInt8, UInt8)] = (0..<324).map { _ in
            (UInt8(140 + Int(next() * 80)), UInt8(110 + Int(next() * 60)),
             UInt8(90 + Int(next() * 50)))
        }
        var stats = DyadPalette.analyze(baseSamples)

        for f in 0..<F {
            let drift: [(UInt8, UInt8, UInt8)] = (0..<324).map { _ in
                (UInt8(135 + f % 8 + Int(next() * 80)), UInt8(105 + Int(next() * 60)),
                 UInt8(85 + Int(next() * 50)))
            }
            stats = DyadPalette.ema(alpha: 0.3, DyadPalette.analyze(drift), stats)
            let table = DyadPalette.table(stats: stats)
            let prims = (0..<DyadPalette.primaryCount).map {
                DyadPalette.oklab(fromSRGB8: table[$0])
            }
            primaries.append(prims)
            let centroid = prims[0]

            let c = Double(side - 1) / 2
            var frameLabs: [OKLabColor] = []
            var frameMask: [Bool] = []
            var frameFar: [Bool] = []
            frameLabs.reserveCapacity(P)
            for p in 0..<P {
                let x = Double(p % side), y = Double(p / side)
                let r2 = (x - c) * (x - c) + (y - c) * (y - c)
                let depth: Float = r2 <= 24 * 24 ? 0.9 : (r2 <= 30 * 30 ? 0.55 : 0.2)
                let face = depth > DyadPipeline.faceThreshold
                let t = face ? 0 : DyadPipeline.pull(depth)
                frameMask.append(face)
                frameFar.append(!face && t >= 1)
                let rgb: (UInt8, UInt8, UInt8) = (
                    UInt8(120 + Int(next() * 120)),
                    UInt8(90 + Int(next() * 100)),
                    UInt8(70 + Int(next() * 90)))
                let lab = DyadPalette.oklab(fromSRGB8: rgb)
                let g = Double(1 - t)
                frameLabs.append(OKLabColor(
                    l: centroid.l + (lab.l - centroid.l) * g,
                    a: centroid.a + (lab.a - centroid.a) * g,
                    b: centroid.b + (lab.b - centroid.b) * g))
            }
            labs.append(frameLabs)
            masks.append(frameMask)
            fars.append(frameFar)
        }

        let ane = try XCTUnwrap(DyadANE.assign(
            labs: labs, primaries: primaries, masks: masks, fars: fars))

        var assignedPixels = 0
        var disagreements = 0
        var maxGap = 0.0
        for f in 0..<F {
            let cpu = DyadPipeline.assignRoles(
                labs: labs[f], mask: masks[f], far: fars[f],
                labPrimaries: primaries[f])
            for p in 0..<P {
                if !masks[f][p] && fars[f][p] {
                    XCTAssertEqual(ane[f][p], 255, "far bg must be 255 (XP1), frame \(f)")
                    continue
                }
                if masks[f][p] {
                    XCTAssertLessThan(ane[f][p], 128, "face pixels must be primaries")
                } else {
                    XCTAssertGreaterThanOrEqual(ane[f][p], 128,
                        "bleed band must stay in the σ-half (XP1)")
                }
                assignedPixels += 1
                if ane[f][p] != cpu[p] {
                    disagreements += 1
                    // Near-tie law on the shared primary search: mirror
                    // band indices back through σ before comparing.
                    var best = Double.infinity, second = Double.infinity
                    for j in 0..<DyadPalette.primaryCount {
                        let d = DyadPalette.dLab2(primaries[f][j], labs[f][p])
                        if d < best { second = best; best = d }
                        else if d < second { second = d }
                    }
                    let gap = second - best
                    maxGap = max(maxGap, gap)
                    XCTAssertLessThanOrEqual(gap, 2 * Self.delta,
                        "disagreement at frame \(f) pixel \(p) is not a near-tie (XP2)")
                }
            }
        }

        let agreement = 1 - Double(disagreements) / Double(max(1, assignedPixels))
        print("ANE parity: agreement \(String(format: "%.3f", agreement * 100))% " +
              "on \(assignedPixels) assigned pixels (face + bleed band), " +
              "\(disagreements) near-tie flips, max gap \(String(format: "%.2e", maxGap))")
        XCTAssertGreaterThanOrEqual(agreement, 0.98,
            "agreement below the measured floor")
    }
}
