// StrataDescentTests.swift
// Tesseract
//
// S8's gate: the rungs actually write the index (spec/output/
// AdditiveLadder.hs AD1-AD12). The meter is AdditiveCensus.conformance,
// which is the SAME function the spec defines, so these tests measure
// the port against the law rather than against themselves.
//
// The headline is the before/after: today's free fine-rung assignment
// scores ~0 at rungs 16 and 32 (AD11 predicts < 0.01), and the descent
// scores 1.0 on a role-pure cube. That is the gap Daniel's ruling
// "all rungs require a meaningful additive" names, closed and measured.
//
// Pure logic. Runs on the simulator.

import XCTest
@testable import Tesseract

final class StrataDescentTests: XCTestCase {

    // A small but lawful cube: 8 frames of 8², so both the 4×4×4
    // rung-16 block and the 2×2×2 rung-32 block divide it.
    private let frames = 8
    private let side = 8

    /// A warm skin-like distribution, the PairTreeTests fixture.
    private func skinStats(seed: Int = 1) -> DyadPalette.Stats {
        var s = seed
        func next() -> Double {
            s = (1103515245 * s + 12345) % 2147483648
            return Double(s) / 2147483648.0
        }
        let samples = (0..<324).map { _ -> (UInt8, UInt8, UInt8) in
            (UInt8(140 + Int(next() * 80)), UInt8(110 + Int(next() * 60)),
             UInt8(90 + Int(next() * 50)))
        }
        return DyadPalette.analyze(samples)
    }

    /// A deterministic staged field with real spatial structure, so
    /// the coarse rungs have something to actually decide.
    private func fixture() -> (labs: [[OKLabColor]], masks: [[Bool]],
                               fars: [[Bool]], prims: [[OKLabColor]],
                               nodes: [[OKLabColor]]) {
        let tree = PairTree.solveFigures(stats: skinStats())
        let prims = Array(repeating: tree.figures, count: frames)
        let nodes = Array(repeating: tree.nodes16, count: frames)
        var labs: [[OKLabColor]] = []
        var s = 7
        func next() -> Double {
            s = (1103515245 * s + 12345) % 2147483648
            return Double(s) / 2147483648.0
        }
        for f in 0..<frames {
            var frame: [OKLabColor] = []
            for y in 0..<side {
                for x in 0..<side {
                    // A smooth ramp plus noise: neighbouring voxels
                    // agree, which is what gives the coarse rungs a
                    // meaningful call to make.
                    let u = Double(x + y + f) / Double(side * 2 + frames)
                    frame.append(OKLabColor(l: 0.45 + 0.25 * u + 0.02 * next(),
                                            a: 0.06 * u + 0.01 * next(),
                                            b: 0.10 - 0.05 * u + 0.01 * next()))
                }
            }
            labs.append(frame)
        }
        let masks = Array(repeating: [Bool](repeating: true, count: side * side),
                          count: frames)
        let fars = Array(repeating: [Bool](repeating: false, count: side * side),
                         count: frames)
        return (labs, masks, fars, prims, nodes)
    }

    /// Census strata rescaled to this cube: AdditiveCensus.blockSide
    /// is stated for a fine side of 64, so on an 8-cube the rung-16
    /// block is 4 and the rung-32 block is 2 by the same ratio.
    private func conformance(_ stratum: AdditiveCensus.Stratum,
                             _ frames: [[UInt8]]) -> Double {
        AdditiveCensus.conformance(stratum, indexFrames: frames, side: side)
    }

    // MARK: - AD11: the strata are constant across their own blocks

    func testDescentConformsAtEveryRung() {
        let f = fixture()
        let out = StrataDescent.assign(labs: f.labs, masks: f.masks,
                                       fars: f.fars, primaries: f.prims,
                                       nodes16: f.nodes, side: side)
        XCTAssertEqual(out.count, frames)
        XCTAssertTrue(out.allSatisfy { $0.count == side * side })

        for st in AdditiveCensus.strata {
            let c = conformance(st, out)
            XCTAssertEqual(c, 1.0, accuracy: 1e-12,
                           "stratum \(st.name) must be constant across its "
                           + "own rung's block: that IS the additive law")
        }
    }

    // MARK: - The before/after AD11 exists to measure

    func testFreeAssignmentViolatesTheCoarseStrata() {
        let f = fixture()
        // Today's law: a free argmin over all 128 leaves per voxel.
        let free = (0..<frames).map { fr in
            DyadPipeline.assignRoles(labs: f.labs[fr], mask: f.masks[fr],
                                     far: f.fars[fr],
                                     labPrimaries: f.prims[fr])
        }
        let descent = StrataDescent.assign(labs: f.labs, masks: f.masks,
                                           fars: f.fars, primaries: f.prims,
                                           nodes16: f.nodes, side: side)

        // The fine stratum conforms either way: its block is one voxel.
        XCTAssertEqual(conformance(AdditiveCensus.r64, free), 1.0, accuracy: 1e-12)
        XCTAssertEqual(conformance(AdditiveCensus.r64, descent), 1.0, accuracy: 1e-12)

        // The coarse strata are where the law bites. The descent must
        // be strictly better at BOTH, which is the whole point of S8.
        XCTAssertGreaterThan(conformance(AdditiveCensus.r16, descent),
                             conformance(AdditiveCensus.r16, free),
                             "rung 16 must gain from writing its own bit")
        XCTAssertGreaterThan(conformance(AdditiveCensus.r32, descent),
                             conformance(AdditiveCensus.r32, free),
                             "rung 32 must gain from writing its own triple")
        XCTAssertEqual(conformance(AdditiveCensus.r16, descent), 1.0, accuracy: 1e-12)
        XCTAssertEqual(conformance(AdditiveCensus.r32, descent), 1.0, accuracy: 1e-12)
    }

    // MARK: - AD2: the index really is the sum of its strata

    func testIndexDecomposesIntoItsStrata() {
        let f = fixture()
        let out = StrataDescent.assign(labs: f.labs, masks: f.masks,
                                       fars: f.fars, primaries: f.prims,
                                       nodes16: f.nodes, side: side)
        for frame in out {
            for i in frame {
                let r = AdditiveCensus.field(AdditiveCensus.role, i)
                let a = AdditiveCensus.field(AdditiveCensus.r16, i)
                let b = AdditiveCensus.field(AdditiveCensus.r32, i)
                let c = AdditiveCensus.field(AdditiveCensus.r64, i)
                XCTAssertEqual(AdditiveCensus.compose(role: r, r16: a, r32: b, r64: c), i,
                               "compose ∘ decompose must be the identity (AD2)")
            }
        }
    }

    // MARK: - The descent is a function, not a search with state

    func testDescentIsDeterministic() {
        let f = fixture()
        let a = StrataDescent.assign(labs: f.labs, masks: f.masks, fars: f.fars,
                                     primaries: f.prims, nodes16: f.nodes, side: side)
        let b = StrataDescent.assign(labs: f.labs, masks: f.masks, fars: f.fars,
                                     primaries: f.prims, nodes16: f.nodes, side: side)
        XCTAssertEqual(a, b, "same cube, same tree, same bytes")
    }

    // MARK: - The far law survives the descent

    func testFullyPulledPixelsAreExactly255() {
        var f = fixture()
        f.masks = Array(repeating: [Bool](repeating: false, count: side * side),
                        count: frames)
        f.fars = Array(repeating: [Bool](repeating: true, count: side * side),
                       count: frames)
        let out = StrataDescent.assign(labs: f.labs, masks: f.masks, fars: f.fars,
                                       primaries: f.prims, nodes16: f.nodes, side: side)
        XCTAssertTrue(out.allSatisfy { $0.allSatisfy { $0 == 255 } },
                      "a fully-pulled background is exactly 255, unchanged")
    }

    // MARK: - The leaf really is chosen inside the committed node

    func testLeafLivesInsideItsCommittedNode() {
        let f = fixture()
        let out = StrataDescent.assign(labs: f.labs, masks: f.masks, fars: f.fars,
                                       primaries: f.prims, nodes16: f.nodes, side: side)
        // Every figure index's node (bits 6-3) must be constant across
        // its 2×2×2 block, which is exactly what stage B committed.
        for bt in 0..<(frames / 2) {
            for by in 0..<(side / 2) {
                for bx in 0..<(side / 2) {
                    var seen = -1
                    for dt in 0..<2 {
                        for dy in 0..<2 {
                            for dx in 0..<2 {
                                let i = out[bt * 2 + dt][(by * 2 + dy) * side + bx * 2 + dx]
                                let node = Int(i) >> 3
                                if seen < 0 { seen = node }
                                else { XCTAssertEqual(node, seen,
                                                      "the node is written once per 2×2×2 block") }
                            }
                        }
                    }
                }
            }
        }
    }
}
