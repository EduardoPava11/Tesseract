// DyadEnergyTests.swift
// Tesseract
//
// Swift mirrors of the PhaseEnergy spec (PE1..PE12 selections) plus
// the trace laws: the Ising identity, ground states, the staggered
// detector, the closed-form/table agreement up to clamp loss, and
// the DYAD ENERGY v1 section riding the GIF comment. No camera.

import XCTest
@testable import Tesseract

final class DyadEnergyTests: XCTestCase {

    private let side = 64

    private var solidFrame: [UInt8] { [UInt8](repeating: 255, count: side * side) }

    private var neelFrame: [UInt8] {
        let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
        return (0..<side * side).map { p in
            let x = p % side, y = p / side
            return bayer[(y % 4) * 4 + (x % 4)] < 8 ? 255 : 0
        }
    }

    private func randomFace(seed: Int) -> [UInt8] {
        var s = seed
        return (0..<side * side).map { _ in
            s = (1103515245 * s + 12345) % 2147483648
            return UInt8(s % 128)
        }
    }

    // PE4: walls = (B − Σσσ)/2 exactly; σ-flip preserves walls.
    func testIsingIdentity() {
        for f in [solidFrame, neelFrame, randomFace(seed: 5)] {
            let e = DyadEnergy.frame(indices: f)
            var ising = 0
            for p in 0..<f.count {
                let x = p % side, y = p / side
                let s = f[p] >= 128 ? 1 : -1
                if x + 1 < side { ising += s * (f[p + 1] >= 128 ? 1 : -1) }
                if y + 1 < side { ising += s * (f[p + side] >= 128 ? 1 : -1) }
            }
            let bonds = 2 * side * (side - 1)
            XCTAssertEqual(e.walls, (bonds - ising) / 2, "PE4 Ising identity")
            let flipped = DyadEnergy.frame(indices: f.map { 255 - $0 })
            XCTAssertEqual(flipped.walls, e.walls, "PE4 σ-flip invariance")
            XCTAssertEqual(flipped.phi, 1 - e.phi, accuracy: 1e-12)
        }
    }

    // PE6 + PE8: the two ground states and the Néel detector.
    func testGroundStates() {
        let solid = DyadEnergy.frame(indices: solidFrame)
        XCTAssertEqual(solid.walls, 0)
        XCTAssertEqual(solid.phi, 1)
        XCTAssertEqual(solid.sOcc, 0)
        XCTAssertEqual(solid.mStag, 0, "no Néel order in the saturated phase")

        let neel = DyadEnergy.frame(indices: neelFrame)
        XCTAssertEqual(neel.walls, 2 * side * (side - 1), "Néel saturates every bond")
        XCTAssertEqual(neel.mStag, 1, "PE8: |m_st| = 1 at the k=8 checkerboard")
        XCTAssertEqual(neel.phi, 0.5, accuracy: 1e-12)

        let face = DyadEnergy.frame(indices: randomFace(seed: 9))
        XCTAssertGreaterThan(face.sOcc, 0.5, "PE11: face is high-entropy")
        XCTAssertLessThan(face.phi, 0.1, "face lives on the primary side")
        XCTAssertLessThan(face.mStag, 0.1, "no Néel order in disorder")
    }

    // PE1 + clamp: table energy agrees with the closed 9-number form
    // up to quantization + gamut clamp loss.
    func testClosedFormMatchesTableUpToClamp() {
        var s = 3
        let samples: [(UInt8, UInt8, UInt8)] = (0..<324).map { _ in
            s = (1103515245 * s + 12345) % 2147483648
            let u1 = UInt8(140 + s % 80)
            s = (1103515245 * s + 12345) % 2147483648
            let u2 = UInt8(110 + s % 60)
            s = (1103515245 * s + 12345) % 2147483648
            return (u1, u2, UInt8(90 + s % 50))
        }
        let stats = DyadPalette.analyze(samples)
        let closed = DyadEnergy.palette(stats: stats)
        // PE1's closed form models the PURE comp mirror. Since the
        // v5-W Wada ground law, `table(stats:)` mutes the σ half —
        // a third loss the old assertion never accounted for (latent
        // failure, repaired in the 2026-08-11 unification). Test the
        // closed form against the IDENTITY ground (ΔL=0, αC=0, βC=1
        // ⇒ ground = comp exactly), and assert the shipped ground
        // only REMOVES energy (muting is one-directional).
        let identity = DyadPalette.GroundMoments(deltaL: 0, alphaC: 0,
                                                 betaC: 1, capped: false)
        let mirror = DyadEnergy.palette(
            table: DyadPalette.table(stats: stats, moments: identity))
        XCTAssertGreaterThan(closed, 0)
        XCTAssertEqual(mirror, closed, accuracy: 0.25 * closed + 0.02,
                       "mirror-table energy tracks the closed form "
                       + "(quantization + clamp)")
        let grounded = DyadEnergy.palette(table: DyadPalette.table(stats: stats))
        XCTAssertLessThanOrEqual(grounded, mirror + 1e-9,
                                 "the Wada ground only removes palette energy")
    }

    // PE13: the trace section round-trips and is recomputable.
    func testEnergyTraceRoundTrip() throws {
        let out = try XCTUnwrap(DyadPipeline.process(frames: (0..<4).map(makeFrame)))
        let trace = DyadEnergy.trace(tables: out.tables, indexFrames: out.indexFrames)
        let lines = trace.split(separator: "\n")
        XCTAssertEqual(lines[0], "DYAD ENERGY v1 frames=4")
        XCTAssertEqual(lines.count, 5)
        for (f, line) in lines.dropFirst().enumerated() {
            let parts = line.split(separator: " ")
            XCTAssertEqual(parts.count, 6)
            let fe = DyadEnergy.frame(indices: out.indexFrames[f])
            XCTAssertEqual(Double(parts[2]), fe.phi, "phi round-trips exactly")
            XCTAssertEqual(Int(parts[4]), fe.walls, "walls round-trip exactly")
        }
    }

    // The section rides every DYAD export's comment.
    func testGIFCarriesEnergySection() throws {
        let gif = try XCTUnwrap(GIFMachine.makeGIF(
            frames: (0..<4).map(makeFrame),
            settings: ExportSettings(bleed: true, mirror: false))).data
        let ascii = String(decoding: gif, as: UTF8.self)
        XCTAssertTrue(ascii.contains("DYAD ENERGY v1"),
                      "every DYAD export reports its energies")
    }

    private func makeFrame(index: Int) -> QuantizedFrame {
        let n = side * side
        let c = Double(side - 1) / 2
        var rgb = [(Float, Float, Float)](repeating: (0.1, 0.7, 0.2), count: n)
        var depths = [Float](repeating: 0.1, count: n)
        for p in 0..<n {
            let x = Double(p % side), y = Double(p / side)
            let r2 = (x - c) * (x - c) + (y - c) * (y - c)
            if r2 <= 20 * 20 {
                rgb[p] = (0.6 + Float(p % 16) * 0.01, 0.45, 0.35)
                depths[p] = 0.9
            } else if r2 <= 27 * 27 {
                depths[p] = 0.53
            }
        }
        let indices = [UInt8](repeating: 0, count: n)
        return QuantizedFrame(
            index: index, paletteIndices: indices, rawRGB: rgb, depths: depths,
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil, anchorTrace: nil, timestamp: Double(index) / 20)
    }
}
