// ReweaveTests.swift
// Tesseract
//
// The edit entry point (Reweave.swift). Two claims are worth pinning:
// the identity edit reproduces the artifact through the PUBLIC entry
// point (not just through `process`, which is what CubeStoreTests
// checks), and every other edit REFUSES rather than quietly returning
// the identity result — a dial that silently does nothing is worse
// than one that says "not yet".

import XCTest
@testable import Tesseract

final class ReweaveTests: XCTestCase {

    private let side = QuantizedFrame.size
    private let frames = 8

    private func syntheticCube(seed: UInt64) -> CubeStore.Cube {
        var state = seed
        func rnd() -> Float {
            state = state &* 6364136223846793005 &+ 1
            return Float((state >> 33) % 10_000) / 10_000
        }
        var rgb = [[(Float, Float, Float)]](), depths = [[Float]]()
        for f in 0..<frames {
            var frame = [(Float, Float, Float)](), ds = [Float]()
            for p in 0..<(side * side) {
                let x = Float(p % side) / Float(side)
                let y = Float(p / side) / Float(side)
                let t = Float(f) / Float(frames)
                let disc = (x - 0.5 - 0.1 * t) * (x - 0.5 - 0.1 * t)
                         + (y - 0.5) * (y - 0.5) < 0.05
                frame.append((disc ? 0.2 + 0.6 * rnd() : 0.05 * rnd(),
                              disc ? 0.5 * rnd() : 0.4 + 0.1 * rnd(),
                              disc ? 0.3 * rnd() : 0.7 + 0.2 * rnd()))
                ds.append(disc ? 0.85 + 0.1 * rnd() : 0.15 * rnd())
            }
            rgb.append(frame); depths.append(ds)
        }
        return CubeStore.Cube(side: side, rgb: rgb, depths: depths)
    }

    // MARK: - the edit space

    func testIdentityIsTheSpecsShippingPoint() {
        // spec RoleAllocation: identityEdit = Edit 7 4 0 0 7 —
        // shippingAlloc plus the fine read alone.
        let e = Reweave.Edit.identity
        XCTAssertEqual([e.fig, e.gnd, e.coarse, e.mid, e.fine], [7, 4, 0, 0, 7])
        XCTAssertTrue(e.isIdentity)
        XCTAssertTrue(e.isRepresentable)
        XCTAssertNil(Reweave.unsupported(e))
    }

    func testOutOfSpaceEditsAreRejected() {
        for bad in [Reweave.Edit(fig: 8, gnd: 4, coarse: 0, mid: 0, fine: 7),
                    Reweave.Edit(fig: 7, gnd: -1, coarse: 0, mid: 0, fine: 7)] {
            XCTAssertFalse(bad.isRepresentable)
            let r = Reweave.reweave(cube: syntheticCube(seed: 1), edit: bad)
            XCTAssertEqual(try? r.get().data.count, nil)
            if case .failure(let why) = r {
                XCTAssertEqual(why, .outOfSpace)
            } else { XCTFail("must refuse") }
        }
    }

    func testEveryNonIdentityEditRefusesWithAReason() {
        // The whole 8^5 minus identity is representable and not yet
        // executable; sample the axes rather than enumerate 32768.
        let axes: [Reweave.Edit] = [
            Reweave.Edit(fig: 6, gnd: 4, coarse: 0, mid: 0, fine: 7),
            Reweave.Edit(fig: 7, gnd: 7, coarse: 0, mid: 0, fine: 7),
            Reweave.Edit(fig: 7, gnd: 4, coarse: 3, mid: 0, fine: 7),
            Reweave.Edit(fig: 7, gnd: 4, coarse: 0, mid: 2, fine: 7),
            Reweave.Edit(fig: 7, gnd: 4, coarse: 0, mid: 0, fine: 5),
        ]
        for e in axes {
            XCTAssertTrue(e.isRepresentable, "still a point of the space")
            let why = Reweave.unsupported(e)
            XCTAssertNotNil(why, "an unimplemented axis must say so")
            XCTAssertFalse(why!.isEmpty)
            if case .failure(.notYetLawful) = Reweave.reweave(
                cube: syntheticCube(seed: 2), edit: e) {} else {
                XCTFail("must refuse, not approximate: \(e)")
            }
        }
    }

    func testEmptyCubeRefuses() {
        let empty = CubeStore.Cube(side: side, rgb: [], depths: [])
        if case .failure(.emptyCube) = Reweave.reweave(cube: empty,
                                                       edit: .identity) {} else {
            XCTFail("an empty cube is not a capture")
        }
    }

    // MARK: - ★ the identity path, through the public entry point

    func testIdentityReweaveMatchesTheDirectExport() throws {
        let cube = syntheticCube(seed: 7)
        let settings = ExportSettings(bleed: true, mirror: false)

        guard let direct = GIFMachine.makeGIF(rgb: cube.rgb, depths: cube.depths,
                                              settings: settings) else {
            return XCTFail("the synthetic capture must be exportable")
        }
        guard let viaEntry = try? Reweave.reweave(cube: cube, edit: .identity,
                                                  settings: settings).get() else {
            return XCTFail("identity must reweave")
        }
        XCTAssertEqual(viaEntry.data, direct.data,
                       "the entry point adds no law of its own — one encoder")
    }

    func testReweaveSurvivesTheStoreRoundTrip() throws {
        // CR1 + the entry point together: retain, reload, re-weave.
        let cube = syntheticCube(seed: 7)
        let data = CubeStore.encode(rgb: cube.rgb, depths: cube.depths, side: side)!
        let reloaded = CubeStore.decode(data)!
        let settings = ExportSettings(bleed: true, mirror: false)

        guard let before = try? Reweave.reweave(cube: cube, edit: .identity,
                                                settings: settings).get(),
              let after = try? Reweave.reweave(cube: reloaded, edit: .identity,
                                               settings: settings).get()
        else { return XCTFail("both must reweave") }

        XCTAssertEqual(after.data, before.data,
                       "CR3 through the entry point: retention is lossless "
                       + "where the artifact is concerned")
    }

    func testMirrorSettingStillReachesTheReweavePath() throws {
        // Guard against the new entry point ignoring settings — a
        // silent divergence between the two makeGIF paths.
        let cube = syntheticCube(seed: 9)
        let plain = try Reweave.reweave(cube: cube, edit: .identity,
                                        settings: ExportSettings(bleed: true,
                                                                 mirror: false)).get()
        let mirrored = try Reweave.reweave(cube: cube, edit: .identity,
                                           settings: ExportSettings(bleed: true,
                                                                    mirror: true)).get()
        XCTAssertNotEqual(plain.data, mirrored.data,
                          "settings must reach the encoder on this path too")
    }
}
