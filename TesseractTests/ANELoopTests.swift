// ANELoopTests.swift
// Tesseract
//
// Swift gate for the L3 loop (ANELoop), mirroring
// spec/neural/ANELoop.hs on the CPU twin (the law — the engine
// path is gated by the prototype harness and the on-device pass):
// AL4 monotone descent + stable fixed point, AL5 null laws, AL6
// determinism, and the consumer's contracts: fully-far blocks
// only, σ-half indices, face/band bytes untouched, F never worse.

import XCTest
@testable import Tesseract

final class ANELoopTests: XCTestCase {

    private func lcg(_ seed: Int) -> AnyIterator<Double> {
        var s = seed
        return AnyIterator {
            s = (1103515245 &* s &+ 12345) % 2147483648
            return Double(s) / 2147483648.0
        }
    }

    private func blockF(_ q: [Int], _ y: [(Double, Double, Double)],
                        _ cand: [(Double, Double, Double)]) -> Double {
        // F_block = ‖e‖² + Σ_2cells 8‖mean‖² + 64‖blockmean‖².
        let e = (0..<64).map { v -> (Double, Double, Double) in
            let c = cand[q[v]]
            return (c.0 - y[v].0, c.1 - y[v].1, c.2 - y[v].2)
        }
        var f = e.reduce(0) { $0 + $1.0 * $1.0 + $1.1 * $1.1 + $1.2 * $1.2 }
        var seen = Set<Int>()
        for v in 0..<64 where !seen.contains(v) {
            let cell = ANELoop.cell2Members[v]
            seen.formUnion(cell)
            var m = (0.0, 0.0, 0.0)
            for w in cell { m.0 += e[w].0; m.1 += e[w].1; m.2 += e[w].2 }
            m = (m.0 / 8, m.1 / 8, m.2 / 8)
            f += 8 * (m.0 * m.0 + m.1 * m.1 + m.2 * m.2)
        }
        var mb = (0.0, 0.0, 0.0)
        for w in 0..<64 { mb.0 += e[w].0; mb.1 += e[w].1; mb.2 += e[w].2 }
        mb = (mb.0 / 64, mb.1 / 64, mb.2 / 64)
        f += 64 * (mb.0 * mb.0 + mb.1 * mb.1 + mb.2 * mb.2)
        return f
    }

    // MARK: - AL4/AL5/AL6 on the CPU twin

    func testSweepMonotoneStableAndDeterministic() {
        let u = lcg(11)
        let y = (0..<64).map { _ in (u.next()!, u.next()!, u.next()!) }
        let cand = (0..<8).map { _ in (u.next()!, u.next()!, u.next()!) }
        let q0 = (0..<64).map { _ in Int(u.next()! * 8) % 8 }

        var fs: [Double] = [blockF(q0, y, cand)]
        var q = q0
        for _ in 0..<6 {
            q = ANELoop.sweepBlockCPU(q0: q, y: y, cand: cand, k: 1)
            fs.append(blockF(q, y, cand))
        }
        // AL4: monotone descent, sweep after sweep.
        for i in 1..<fs.count {
            XCTAssertLessThanOrEqual(fs[i], fs[i - 1] + 1e-12)
        }
        // AL4: a deep fixed point is stable — one more sweep is identity.
        let deep = ANELoop.sweepBlockCPU(q0: q0, y: y, cand: cand, k: 12)
        XCTAssertEqual(ANELoop.sweepBlockCPU(q0: deep, y: y, cand: cand, k: 1), deep)
        // AL5: K = 0 is the identity.
        XCTAssertEqual(ANELoop.sweepBlockCPU(q0: q0, y: y, cand: cand, k: 0), q0)
        // AL6: pure function; sweeps compose.
        XCTAssertEqual(ANELoop.sweepBlockCPU(q0: q0, y: y, cand: cand, k: 3),
                       ANELoop.sweepBlockCPU(q0: q0, y: y, cand: cand, k: 3))
        let two = ANELoop.sweepBlockCPU(
            q0: ANELoop.sweepBlockCPU(q0: q0, y: y, cand: cand, k: 2),
            y: y, cand: cand, k: 2)
        XCTAssertEqual(two, ANELoop.sweepBlockCPU(q0: q0, y: y, cand: cand, k: 4))
    }

    // MARK: - The consumer's contracts (CPU path; ANE gated on device)

    /// A synthetic 8-frame 8×8 capture: left half face (t = 0),
    /// right half far ground (t = 1) — the right half is exactly the
    /// bx = 1 column of 4³ blocks, fully far.
    private func syntheticCube() -> (idx: [[UInt8]], labs: [[OKLabColor]],
                                     pulls: [[Float]], tables: [Data]) {
        let side = 8, frames = 8
        let stats = DyadPalette.analyze([(180, 140, 110), (150, 110, 90),
                                         (120, 90, 70), (200, 160, 130)])
        let table = DyadPalette.table(stats: stats)
        let tableData = DyadPalette.gifColorTable(table)
        let u = lcg(21)
        var idx = [[UInt8]](), labs = [[OKLabColor]](), pulls = [[Float]]()
        for _ in 0..<frames {
            var fi = [UInt8](), fl = [OKLabColor](), fp = [Float]()
            for p in 0..<(side * side) {
                let x = p % side
                if x < side / 2 {
                    fi.append(UInt8(p % 128)); fp.append(0)
                } else {
                    fi.append(UInt8(200 + (p % 8))); fp.append(1)
                }
                fl.append(OKLabColor(l: 0.4 + 0.3 * u.next()!,
                                     a: 0.1 * (u.next()! - 0.5),
                                     b: 0.1 * (u.next()! - 0.5)))
            }
            idx.append(fi); labs.append(fl); pulls.append(fp)
        }
        return (idx, labs, pulls, [Data](repeating: tableData, count: frames))
    }

    func testRefineTouchesOnlyFullyFarBlocksAndStaysSigma() {
        let (idx, labs, pulls, tables) = syntheticCube()
        let out = ANELoop.refineFarBlocks(indexFrames: idx, labs: labs,
                                          pulls: pulls, tables: tables,
                                          coverageCeil: 31.0 / 32.0,
                                          useANE: false)
        XCTAssertEqual(out.count, idx.count)
        var changed = 0
        for f in 0..<idx.count {
            for p in 0..<idx[f].count {
                let x = p % 8
                if x < 4 {
                    // Face half: byte-untouched.
                    XCTAssertEqual(out[f][p], idx[f][p], "face byte moved")
                } else {
                    // Far half: σ indices only.
                    XCTAssertGreaterThanOrEqual(out[f][p], 128)
                    if out[f][p] != idx[f][p] { changed += 1 }
                }
            }
        }
        XCTAssertGreaterThan(changed, 0, "the loop should rearrange the far field")
    }

    func testRefineNeverIncreasesF() throws {
        let (idx, labs, pulls, tables) = syntheticCube()
        let out = ANELoop.refineFarBlocks(indexFrames: idx, labs: labs,
                                          pulls: pulls, tables: tables,
                                          coverageCeil: 31.0 / 32.0,
                                          useANE: false)
        // F via the step-2 telemetry (PP1's kernel) on displayed vs ŷ.
        func fOf(_ frames: [[UInt8]]) throws -> Double {
            var e = [(Double, Double, Double)]()
            for f in 0..<frames.count {
                let t = tables[f]
                for p in 0..<frames[f].count {
                    let s = t.startIndex + 3 * Int(frames[f][p])
                    let rgb: (UInt8, UInt8, UInt8) = (t[s], t[s + 1], t[s + 2])
                    let shown = DyadPalette.oklab(fromSRGB8: rgb)
                    let y = labs[f][p]
                    e.append((shown.l - y.l, shown.a - y.a, shown.b - y.b))
                }
            }
            let b = try XCTUnwrap(PhaseTelemetry.bands(errorField: e,
                                                       side: 8, frameCount: 8))
            return b.d16 + b.d32 + b.d64
        }
        let f0 = try fOf(idx), f1 = try fOf(out)
        XCTAssertLessThanOrEqual(f1, f0 + 1e-12,
                                 "descent on F must never lose to v4")
    }

    func testRefineDeterministic() {
        let (idx, labs, pulls, tables) = syntheticCube()
        let a = ANELoop.refineFarBlocks(indexFrames: idx, labs: labs,
                                        pulls: pulls, tables: tables,
                                        coverageCeil: 31.0 / 32.0, useANE: false)
        let b = ANELoop.refineFarBlocks(indexFrames: idx, labs: labs,
                                        pulls: pulls, tables: tables,
                                        coverageCeil: 31.0 / 32.0, useANE: false)
        XCTAssertEqual(a, b)
    }

    func testFlagOffIsByteIdentical() throws {
        // The shipped path: chaosLoop defaulting off must leave the
        // DYAD output untouched (R3 — additive, never replacing).
        let side = CameraConfig.outputSize
        var frames = [QuantizedFrame]()
        let u = lcg(31)
        for f in 0..<CameraConfig.totalFrames {
            let n = side * side
            var rgb = [(Float, Float, Float)](); var depths = [Float]()
            for p in 0..<n {
                let x = p % side
                rgb.append((Float(0.5 + 0.2 * u.next()!),
                            Float(0.4 + 0.2 * u.next()!),
                            Float(0.35 + 0.1 * u.next()!)))
                depths.append(x < side / 2 ? 0.9 : 0.1)
            }
            frames.append(QuantizedFrame(
                index: f, paletteIndices: [UInt8](repeating: 0, count: n),
                rawRGB: rgb, depths: depths,
                measure: BirkhoffMeasure(paletteIndices: [UInt8](repeating: 0, count: n)),
                subjectAnalysis: nil, anchorTrace: nil, timestamp: Double(f)))
        }
        let base = try XCTUnwrap(DyadPipeline.process(frames: frames))
        let off = try XCTUnwrap(DyadPipeline.process(frames: frames, chaosLoop: false))
        XCTAssertEqual(base.indexFrames, off.indexFrames)
        // Flag on: lawful output, same tables, face side untouched.
        let on = try XCTUnwrap(DyadPipeline.process(frames: frames, chaosLoop: true))
        XCTAssertEqual(on.tables, base.tables, "the loop never touches tables")
        XCTAssertEqual(on.indexFrames.count, base.indexFrames.count)
    }
}
