// DyadPipelineTests.swift
// Tesseract
//
// Pure-logic tests for the DYAD-256 export path: synthetic captures
// (skin disk on background, depth mask in the QuantizedFrame slot)
// through DyadPipeline.process. No camera, no Metal.

import XCTest
@testable import Tesseract

final class DyadPipelineTests: XCTestCase {

    private let side = QuantizedFrame.size
    private let frameCount = 8   // enough to exercise the EMA chain

    /// A frame whose rawRGB is a warm skin disk on a cool background,
    /// with depths 1 inside the disk and 0 outside — the mask decides
    /// roles, so the background color content should not matter.
    private func makeFrame(index: Int, withRGB: Bool = true) -> QuantizedFrame {
        let n = side * side
        let c = Double(side - 1) / 2
        var rgb = [(Float, Float, Float)](repeating: (0, 0, 0), count: n)
        var depths = [Float](repeating: 0, count: n)
        for p in 0..<n {
            let x = Double(p % side), y = Double(p / side)
            let inFace = (x - c) * (x - c) + (y - c) * (y - c) <= 24 * 24
            if inFace {
                let t = Float(p % 32) / 31          // shading ramp across the face
                rgb[p] = (0.55 + 0.25 * t, 0.42 + 0.18 * t, 0.33 + 0.12 * t)
                depths[p] = 1
            } else {
                rgb[p] = (0.1, 0.9, 0.1)            // loud background, masked out
                depths[p] = 0
            }
        }
        let indices = [UInt8](repeating: 0, count: n)
        return QuantizedFrame(
            index: index,
            paletteIndices: indices,
            rawRGB: withRGB ? rgb : nil,
            depths: depths,
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil,
            anchorTrace: nil,
            timestamp: Double(index) / 20.0
        )
    }

    func testRoleLawOnPixels() throws {
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames))
        XCTAssertEqual(out.indexFrames.count, frameCount)
        XCTAssertEqual(out.tables.count, frameCount)

        let c = Double(side - 1) / 2
        for indices in out.indexFrames {
            for p in 0..<indices.count {
                let x = Double(p % side), y = Double(p / side)
                let inFace = (x - c) * (x - c) + (y - c) * (y - c) <= 24 * 24
                if inFace {
                    XCTAssertLessThan(indices[p], 128, "face pixels use primaries only")
                } else {
                    XCTAssertGreaterThanOrEqual(indices[p], 128,
                        "background lives in the σ-mirror half (v4 binomial background)")
                }
            }
        }
    }

    func testEveryTableSatisfiesTheGroundLaw() throws {
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames))
        XCTAssertEqual(out.groundMoments.count, out.tables.count)
        for (f, table) in out.tables.enumerated() {
            XCTAssertEqual(table.count, 768)
            func entry(_ i: Int) -> (UInt8, UInt8, UInt8) {
                (table[3 * i], table[3 * i + 1], table[3 * i + 2])
            }
            // Ruling R2: the σ half regenerates from the frame's own
            // fitted moments (scene fit on two-phase captures; the
            // Wada prior only when no background evidence exists).
            let gm = out.groundMoments[f]
            if out.twoPhase {
                XCTAssertFalse(gm.capped, "scene-fit moments are uncapped")
            }
            for i in 0..<128 {
                XCTAssertTrue(entry(255 - i) == DyadPalette.ground(gm, of: entry(i)))
            }
        }
    }

    func testMaskedBackgroundDoesNotSteerThePalette() throws {
        // The loud green background is weight-0: the FITTED face
        // centroid must be warm (a > 0 in OKLab), not dragged green.
        // (Since the pair tree, T[0] is a corner leaf, not the
        // centroid — the stats carry the centroid directly.)
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames))
        XCTAssertGreaterThan(out.stats[0].centroid.a, 0,
                             "face centroid must stay warm")
    }

    func testHarshBleedBand() throws {
        // Three depth zones: face disk (0.9), ring (0.5 — the cluster
        // midpoint, so the FITTED mixture must put it in the band),
        // far field (0.1 — solid mirror).
        let n = side * side
        let c = Double(side - 1) / 2
        var rgb = [(Float, Float, Float)](repeating: (0.1, 0.9, 0.1), count: n)
        var depths = [Float](repeating: 0.1, count: n)
        for p in 0..<n {
            let x = Double(p % side), y = Double(p / side)
            let r2 = (x - c) * (x - c) + (y - c) * (y - c)
            if r2 <= 20 * 20 {
                rgb[p] = (0.65, 0.5, 0.4); depths[p] = 0.9
            } else if r2 <= 27 * 27 {
                depths[p] = 0.5
            }
        }
        let indices = [UInt8](repeating: 0, count: n)
        let frame = QuantizedFrame(
            index: 0, paletteIndices: indices, rawRGB: rgb, depths: depths,
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil, anchorTrace: nil, timestamp: 0)
        let out = try XCTUnwrap(DyadPipeline.process(frames: [frame]))

        // The fitted role law: face zone solid-face, ring in the band,
        // far zone solid-mirror — boundaries are the Bayer extrema.
        XCTAssertTrue(out.twoPhase, "three-zone field must read as two phases")
        XCTAssertLessThan(out.mixture.pull(0.9), DyadPipeline.coverageFloor)
        let tBand = out.mixture.pull(0.5)
        XCTAssertTrue(tBand > DyadPipeline.coverageFloor && tBand < DyadPipeline.coverageCeil,
                      "midpoint ring must sit in the band")
        XCTAssertGreaterThan(out.mixture.pull(0.1), DyadPipeline.coverageCeil)

        // v3 pair dither: a band pixel shows the σ side of its pair
        // exactly when its Bayer threshold is below the coverage t;
        // otherwise the primary side. Flipping with 255 − i is the
        // other side of the same pair by the involution.
        var sawSigma = false, sawPrimary = false
        for p in 0..<n {
            let idx = Int(out.indexFrames[0][p])
            switch depths[p] {
            case 0.9:
                XCTAssertLessThan(idx, 128, "face pixels use primaries")
            case 0.5:
                let sigmaSide = DyadPipeline.bayer4[(p / side) % 4][(p % side) % 4] < Float(tBand)
                if sigmaSide {
                    XCTAssertGreaterThanOrEqual(idx, 128, "below threshold = σ side")
                    XCTAssertLessThan(255 - idx, 128, "partner is the primary side")
                    sawSigma = true
                } else {
                    XCTAssertLessThan(idx, 128, "at/above threshold = primary side")
                    XCTAssertGreaterThanOrEqual(255 - idx, 128, "partner is the σ side")
                    sawPrimary = true
                }
            default:
                XCTAssertGreaterThanOrEqual(idx, 128,
                    "far background is the σ-mirror of its own primary (v4)")
            }
        }
        XCTAssertTrue(sawSigma && sawPrimary,
            "the band must dither: both sides of the pair appear")

        // v4: the far field must NOT be one solid — the loud green far
        // pixels and the (differently colored) uniform region still map
        // through their OWN nearest primary; at minimum the σ half is
        // occupied, and a uniform far field maps consistently.
        let farIdx = Set((0..<n).filter { depths[$0] == 0.1 }.map { out.indexFrames[0][$0] })
        XCTAssertTrue(farIdx.allSatisfy { $0 >= 128 }, "far occupies the mirrored shells")

        // BLEED OFF: MAP classes, no band; background = hard σ-mirror.
        let flat = try XCTUnwrap(DyadPipeline.process(frames: [frame], bleed: false))
        for p in 0..<n where depths[p] == 0.1 {
            XCTAssertGreaterThanOrEqual(flat.indexFrames[0][p], 128,
                           "bleed off: far field is the hard σ-mirror, no band")
        }
    }

    func testMissingRawRGBDeclinesTheCapture() {
        var frames = (0..<frameCount).map { makeFrame(index: $0) }
        frames[3] = makeFrame(index: 3, withRGB: false)
        XCTAssertNil(DyadPipeline.process(frames: frames),
                     "any frame without rawRGB must fall back to the lattice path")
        XCTAssertNil(DyadPipeline.process(frames: []))
    }

    func testDeterminism() throws {
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        let a = try XCTUnwrap(DyadPipeline.process(frames: frames))
        let b = try XCTUnwrap(DyadPipeline.process(frames: frames))
        XCTAssertEqual(a.tables, b.tables)
        XCTAssertEqual(a.indexFrames, b.indexFrames)
    }

    func testEndToEndThroughEncoder() throws {
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames))
        let gif = try XCTUnwrap(GIFEncoder.encode(
            indexFrames: out.indexFrames, side: side,
            upscale: CameraConfig.exportUpscale, perFrameTables: out.tables))
        let b = [UInt8](gif)
        XCTAssertEqual(Array(b[0..<6]), [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        XCTAssertEqual(Data(b[13..<(13 + 768)]), out.tables[0], "GCT = frame 0's table")
    }

    // MARK: - ★ WATCHING (spec/ui/EditMachine.hs EM12/EM13)
    //
    // The laws the deleted DyadPreview used to carry, restated on the
    // path that replaced it: weave = watch + keep, so the live driver
    // must obey the export's role law, at the export's cadence, as a
    // pure function of the feed.

    /// EM13: the surface runs the export's role law, not a second one
    /// — face pixels take primaries, background takes the σ-mirror
    /// half, exactly as `testRoleLawOnPixels` demands of the export.
    func testEM13LiveSurfaceObeysTheExportRoleLaw() throws {
        let live = DyadPipeline.Live()
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        var indices: [UInt8] = []
        for frame in frames {
            live.read(rgb: frame.rawRGB!, depths: frame.depths)
            indices = try XCTUnwrap(live.assign(rgb: frame.rawRGB!, depths: frame.depths))
        }
        XCTAssertEqual(indices.count, side * side)
        XCTAssertEqual(live.table.count, 256, "the surface draws with a solved table")

        let c = Double(side - 1) / 2
        for p in 0..<indices.count {
            let x = Double(p % side), y = Double(p / side)
            let inFace = (x - c) * (x - c) + (y - c) * (y - c) <= 24 * 24
            if inFace {
                XCTAssertLessThan(indices[p], 128, "face pixels use primaries only")
            } else {
                XCTAssertGreaterThanOrEqual(indices[p], 128,
                    "background lives in the σ-mirror half (v4 binomial background)")
            }
        }
    }

    /// EM8 + EM11: what the surface shows is render(capture, edit) —
    /// a pure function of the feed, never of how the read was entered.
    /// Two drivers fed the same frames must agree bit for bit.
    func testEM11LiveReadIsAPureFunctionOfTheFeed() throws {
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        func drive() throws -> ([UInt8], [(UInt8, UInt8, UInt8)]) {
            let live = DyadPipeline.Live()
            var out: [UInt8] = []
            for frame in frames {
                out = try XCTUnwrap(live.process(rgb: frame.rawRGB!, depths: frame.depths))
            }
            return (out, live.table)
        }
        let (a, ta) = try drive()
        let (b, tb) = try drive()
        XCTAssertEqual(a, b)
        XCTAssertTrue(zip(ta, tb).allSatisfy { $0 == $1 }, "same feed, same table")
    }

    /// TL8/TL9: the solve rides the coarse rung's rate. The table may
    /// change only on a stride boundary — the cadence the deleted
    /// preview's `refreshStride` used to assert by construction.
    func testEM13SolveRidesTheCoarseRungCadence() throws {
        let live = DyadPipeline.Live()
        let stride = DyadPipeline.Live.refreshStride
        // A moving field: every frame differs, so any table that CAN
        // change on an off-stride frame will.
        var previous: [(UInt8, UInt8, UInt8)] = []
        for i in 0..<(3 * stride) {
            let n = side * side
            let shade = Float(i) / Float(3 * stride)
            var rgb = [(Float, Float, Float)](repeating: (0.1, 0.9, 0.1), count: n)
            var depths = [Float](repeating: 0, count: n)
            let c = Double(side - 1) / 2
            for p in 0..<n {
                let x = Double(p % side), y = Double(p / side)
                if (x - c) * (x - c) + (y - c) * (y - c) <= 24 * 24 {
                    rgb[p] = (0.4 + 0.4 * shade, 0.35 + 0.2 * shade, 0.3 + 0.1 * shade)
                    depths[p] = 1
                }
            }
            live.read(rgb: rgb, depths: depths)
            let table = live.table
            // Frame 0 opens the first (short, lawful-degenerate) coarse
            // frame; after that only stride boundaries may move it.
            if i > 0 && i % stride != 0 {
                XCTAssertTrue(zip(table, previous).allSatisfy { $0 == $1 },
                              "the table held at frame \(i): off-cadence solve")
            }
            previous = table
        }
    }

    /// EM12 — ONE ENCODER, TWO DISPOSITIONS. `.generatingState` is a
    /// stopping point at the stage boundary, never a second code path:
    /// every law above it runs identically, so the two runs' solves are
    /// bit-equal and only the artifact carries index frames.
    ///
    /// This is the gate that keeps the optimisation honest. Without it
    /// `Live` could drift from the export and the preview would quietly
    /// stop being the GIF (EM13) with nothing to catch it.
    func testEM12GeneratingStateMatchesArtifactSolves() throws {
        let frames = (0..<frameCount).map { makeFrame(index: $0) }
        let rgb = frames.map { $0.rawRGB! }
        let depths = frames.map { $0.depths }

        let artifact = try XCTUnwrap(
            DyadPipeline.process(rgb: rgb, depths: depths, keeping: .artifact))
        let state = try XCTUnwrap(
            DyadPipeline.process(rgb: rgb, depths: depths, keeping: .generatingState))

        // Stage 2 is the ONLY difference.
        XCTAssertEqual(artifact.indexFrames.count, frameCount)
        XCTAssertTrue(state.indexFrames.isEmpty,
                      "generatingState assigned a cube it would discard")

        // Everything the state carries is bit-equal — no tolerance.
        XCTAssertEqual(state.tables, artifact.tables)
        XCTAssertEqual(state.twoPhase, artifact.twoPhase)
        XCTAssertEqual(state.alpha, artifact.alpha)
        XCTAssertEqual(state.msGain, artifact.msGain)
        XCTAssertEqual(state.jepaH, artifact.jepaH)
        XCTAssertEqual(state.mixture.crossover, artifact.mixture.crossover)
        XCTAssertEqual(state.mixture.temperature, artifact.mixture.temperature)
        XCTAssertEqual(state.solves.count, artifact.solves.count)
        for (f, (s, a)) in zip(state.solves, artifact.solves).enumerated() {
            XCTAssertTrue(zip(s.table, a.table).allSatisfy { $0 == $1 },
                          "frame \(f): table diverged")
            XCTAssertEqual(s.twoPhase, a.twoPhase, "frame \(f)")
            XCTAssertEqual(s.bleed, a.bleed, "frame \(f)")
            XCTAssertEqual(s.centroid.l, a.centroid.l, "frame \(f)")
            XCTAssertEqual(s.centroid.a, a.centroid.a, "frame \(f)")
            XCTAssertEqual(s.centroid.b, a.centroid.b, "frame \(f)")
            XCTAssertEqual(s.mixture.crossover, a.mixture.crossover, "frame \(f)")
            XCTAssertEqual(s.primaries.count, a.primaries.count, "frame \(f)")
            XCTAssertTrue(zip(s.primaries, a.primaries)
                            .allSatisfy { $0.l == $1.l && $0.a == $1.a && $0.b == $1.b },
                          "frame \(f): primaries diverged")
        }
    }

    /// ★ GH4 END TO END — the fitted Δh must track the scene's REAL
    /// hue separation, through the whole pipeline including γ-staging.
    ///
    /// This is the test whose absence let a dead fix ship. Every other
    /// ground-hue test hands `backgroundMoments` a raw ensemble
    /// directly; none composed staging with the hue fit. Staging is
    /// `ŷ_ab = c_F,ab + γ(s)(y_ab − c_F,ab)`, so reading the resultant
    /// off the STAGED field adds a bias pointing at the FIGURE's hue —
    /// and the failure is not a shrink but a non-monotonicity: the
    /// fitted angle peaks near 90° of true separation and returns to
    /// ZERO at 180°, so a blue wall behind a warm face — the exact
    /// case the law exists for — reproduced v7 byte for byte.
    ///
    /// 180° is therefore the case this asserts.
    func testGH4FittedHueTracksAWallOpposedToTheFace() throws {
        // A warm face disc on a wall of the OPPOSITE hue.
        func scene(wallHueDegrees: Double) -> [([(Float, Float, Float)], [Float])] {
            let n = side * side
            let c = Double(side - 1) / 2
            // Face: lit skin. Wall: same L and chroma, rotated hue.
            let faceRGB: (Float, Float, Float) = (0.878, 0.675, 0.557)
            let th = wallHueDegrees * .pi / 180
            // Build the wall in OKLab then round-trip, so the hue is exact.
            let faceLab = DyadPalette.oklab(fromSRGB8: DyadPipeline.srgb8(from: faceRGB))
            let C = (faceLab.a * faceLab.a + faceLab.b * faceLab.b).squareRoot()
            let h0 = atan2(faceLab.b, faceLab.a)
            let wallLab = OKLabColor(l: faceLab.l,
                                     a: C * cos(h0 + th),
                                     b: C * sin(h0 + th))
            let w8 = DyadPalette.srgb8(from: wallLab)
            let wallRGB: (Float, Float, Float) = (Float(w8.0) / 255,
                                                  Float(w8.1) / 255,
                                                  Float(w8.2) / 255)
            return (0..<frameCount).map { _ in
                var rgb = [(Float, Float, Float)](repeating: wallRGB, count: n)
                var depths = [Float](repeating: 0, count: n)
                for p in 0..<n {
                    let x = Double(p % side), y = Double(p / side)
                    if (x - c) * (x - c) + (y - c) * (y - c) <= 24 * 24 {
                        rgb[p] = faceRGB
                        depths[p] = 1
                    }
                }
                return (rgb, depths)
            }
        }

        let frames = scene(wallHueDegrees: 180)
        let out = try XCTUnwrap(
            DyadPipeline.process(rgb: frames.map { $0.0 }, depths: frames.map { $0.1 }))
        let solve = try XCTUnwrap(out.solves.last)
        let rot = solve.moments.rot

        // The fitted rotation, as an angle.
        let fitted = abs(atan2(rot.b, rot.a) * 180 / .pi)
        XCTAssertGreaterThan(
            fitted, 90,
            "GH4: a wall opposed to the face fitted only \(fitted)° of rotation — "
            + "the hue resultant is being read on the γ-staged field, whose bias "
            + "points at the figure's own hue and cancels the separation")
        // And it must not be the identity, which is what v7 emitted.
        XCTAssertNotEqual(rot, DyadPalette.HueRotation.identity,
                          "GH4: fell back to v7's forced same-hue ground")
    }

    /// D1 — the BLEED setting must REACH the GPU. `MetalState` is the
    /// only channel to the aerialPreview kernel; before the fix it had
    /// no bleed slot and the kernel computed the soft coverage band
    /// unconditionally, so with BLEED off the CPU path and the export
    /// dropped the band while LIVE+Metal — the default shipping path —
    /// still showed it. One setting, two answers on one screen.
    func testBleedAndPhaseReachTheMetalState() throws {
        let live = DyadPipeline.Live()
        for frame in (0..<frameCount).map({ makeFrame(index: $0) }) {
            live.read(rgb: frame.rawRGB!, depths: frame.depths)
        }
        let solve = try XCTUnwrap(live.solve, "the ring never solved")
        let metal = try XCTUnwrap(live.metalState, "no state for the kernel")

        // The GPU must ride the SAME coverage law the CPU does — both
        // flags, or the two surfaces answer different settings.
        XCTAssertEqual(metal.bleed, solve.bleed,
                       "the kernel would ignore BLEED")
        XCTAssertEqual(metal.twoPhase, solve.twoPhase)
        XCTAssertEqual(metal.sStar, Float(solve.mixture.crossover))
        XCTAssertEqual(metal.tau, Float(solve.mixture.temperature))
        XCTAssertEqual(metal.primaries.count, DyadPalette.primaryCount)
    }
}
