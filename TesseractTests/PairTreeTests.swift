// PairTreeTests.swift
// Tesseract
//
// Swift mirrors of spec/quantization/PairTree.hs PT7–PT9: the
// analytic dyadic tree — closed-form Gaussian splits, deterministic
// leaf order, node/octet coherence, the v3 table law, and the
// provenance round-trip (13 numbers regenerate every byte through
// the TREE). Pure logic — runs on the simulator.

import XCTest
@testable import Tesseract

final class PairTreeTests: XCTestCase {

    /// A warm skin-like distribution (matches the spec fixtures).
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

    // MARK: - PT7/PT8: the analytic split, deterministic and lawful

    func testTreeIsDeterministicAndComplete() {
        let stats = skinStats()
        let a = PairTree.solveFigures(stats: stats)
        let b = PairTree.solveFigures(stats: stats)
        XCTAssertEqual(a.figures8.map { [$0.0, $0.1, $0.2] },
                       b.figures8.map { [$0.0, $0.1, $0.2] },
                       "same stats must build the same tree, byte for byte")
        XCTAssertEqual(a.figures8.count, 128)
        XCTAssertEqual(a.nodes16.count, 16)
        XCTAssertEqual(a.canonical16.count, 16)
    }

    func testDegenerateStatsCollapseLawfully() {
        // Zero variance: 128 coincident leaves — lawful, not special-cased.
        let stats = DyadPalette.analyze([(128, 128, 128)])
        let tree = PairTree.solveFigures(stats: stats)
        XCTAssertEqual(tree.figures8.count, 128)
        XCTAssertTrue(tree.figures8.allSatisfy { $0 == tree.figures8[0] })
    }

    // MARK: - PT9: node/octet coherence + canonical leaves in-node

    func testCanonicalLeavesLiveInTheirOctet() {
        let tree = PairTree.solveFigures(stats: skinStats())
        for c in 0..<16 {
            let leaf = tree.canonical16[c]
            XCTAssertTrue((c * 8..<(c * 8 + 8)).contains(leaf),
                          "node \(c)'s canonical leaf must be one of its 8 leaves")
        }
    }

    // MARK: - The v3 table law

    func testTableCarriesTheGroundLawByteExact() {
        let stats = skinStats()
        let gm = DyadPalette.priorMoments(centroidL: stats.centroid.l)
        let table = PairTree.table(stats: stats, moments: gm)
        XCTAssertEqual(table.count, 256)
        for i in 0..<128 {
            XCTAssertTrue(table[255 - i] == DyadPalette.ground(gm, of: table[i]),
                          "T[255−\(i)] must be the ground of T[\(i)]")
        }
    }

    func testTreeTableDiffersFromRingTable() {
        // The bold switch is real: tree ≠ rings on a live distribution.
        let stats = skinStats()
        let gm = DyadPalette.priorMoments(centroidL: stats.centroid.l)
        let tree = PairTree.table(stats: stats, moments: gm)
        let rings = DyadPalette.table(stats: stats, moments: gm)
        XCTAssertNotEqual(tree.map { [$0.0, $0.1, $0.2] },
                          rings.map { [$0.0, $0.1, $0.2] })
    }

    // MARK: - Provenance: v3 rebuild through the tree

    func testV3TraceRebuildsTreeTablesByteExact() throws {
        let n = QuantizedFrame.pixelCount
        let side = QuantizedFrame.size
        let c = Double(side - 1) / 2
        var rgb = [(Float, Float, Float)](repeating: (0.6, 0.45, 0.35), count: n)
        var depths = [Float](repeating: 0, count: n)
        for p in 0..<n {
            let x = Double(p % side), y = Double(p / side)
            if (x - c) * (x - c) + (y - c) * (y - c) <= 24 * 24 {
                depths[p] = 1
                rgb[p].0 += Float(p % 16) * 0.01
            }
        }
        let indices = (0..<n).map { UInt8($0 % 256) }
        let frames = (0..<4).map { i in
            QuantizedFrame(index: i, paletteIndices: indices,
                           rawRGB: rgb, depths: depths,
                           measure: BirkhoffMeasure(paletteIndices: indices),
                           subjectAnalysis: nil, anchorTrace: nil,
                           timestamp: Double(i) / 20.0)
        }
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames))
        let trace = GIFMachine.dyadTrace(
            out, settings: ExportSettings(bleed: true, mirror: false))
        XCTAssertTrue(trace.contains("DYAD STATS v3"),
                      "pair-tree exports must be tagged v3")
        let rebuilt = try XCTUnwrap(GIFMachine.rebuildTables(fromTrace: trace))
        XCTAssertEqual(rebuilt, out.tables,
                       "13 numbers per frame must regenerate every tree byte")
    }

    // MARK: - P2: the σ side lands on canonical grounds (32-level)

    func testFarBackgroundUsesTheThirtyTwoLevel() throws {
        // Uniform far field → every σ-stay pixel must display one of
        // the 16 canonical grounds (the prefix law's palette-rate 8:1).
        let n = QuantizedFrame.pixelCount
        let rgb = [(Float, Float, Float)](repeating: (0.2, 0.3, 0.5), count: n)
        var depths = [Float](repeating: 0.05, count: n)   // far everywhere...
        let side = QuantizedFrame.size
        let c = Double(side - 1) / 2
        for p in 0..<n {                                   // ...except a face disk
            let x = Double(p % side), y = Double(p / side)
            if (x - c) * (x - c) + (y - c) * (y - c) <= 20 * 20 { depths[p] = 0.95 }
        }
        let indices = (0..<n).map { UInt8($0 % 256) }
        let frames = (0..<4).map { i in
            QuantizedFrame(index: i, paletteIndices: indices,
                           rawRGB: rgb, depths: depths,
                           measure: BirkhoffMeasure(paletteIndices: indices),
                           subjectAnalysis: nil, anchorTrace: nil,
                           timestamp: Double(i) / 20.0)
        }
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames))
        guard out.twoPhase else { return }   // single-phase: no σ side to test
        for (f, frame) in out.indexFrames.enumerated() {
            let tree = PairTree.solveFigures(stats: out.stats[f])
            let lawful = Set(tree.canonical16.map { UInt8(255 - $0) })
            for idx in frame where idx >= 128 {
                XCTAssertTrue(lawful.contains(idx),
                              "σ-side index \(idx) must be a canonical ground (frame \(f))")
            }
        }
    }
}
