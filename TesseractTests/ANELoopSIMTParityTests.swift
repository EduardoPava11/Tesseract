// ANELoopSIMTParityTests.swift
// Tesseract
//
// The SIMT port's gate (spec §4b AL9; Metal/ANELoop.metal): the
// float32 GPU kernel against the Double CPU twin (the law), on the
// DyadANEParity pattern — agreement up to score near-ties (XP2),
// never bit-exactness across precisions. The hard laws are AL4's:
// F never increases from the start state, and the two ports land
// within a whisker of the same objective value. Skips where Metal
// is unavailable; the timing story lives in ANELoopBenchTests.

import XCTest
@testable import Tesseract

final class ANELoopSIMTParityTests: XCTestCase {

    private static let blocks = 64
    private static let sweeps = 4

    /// F of one block from candidate indices (the ANELoopTests
    /// evaluator: ‖e‖² + Σ 2-cells 8‖mean‖² + 64‖block mean‖²).
    private func blockF(_ q: [UInt8], _ y: [(Double, Double, Double)],
                        _ cand: [(Double, Double, Double)]) -> Double {
        let e = (0..<64).map { v -> (Double, Double, Double) in
            let c = cand[Int(q[v])]
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
        var bm = (0.0, 0.0, 0.0)
        for v in 0..<64 { bm.0 += e[v].0; bm.1 += e[v].1; bm.2 += e[v].2 }
        bm = (bm.0 / 64, bm.1 / 64, bm.2 / 64)
        f += 64 * (bm.0 * bm.0 + bm.1 * bm.1 + bm.2 * bm.2)
        return f
    }

    func testSIMTMatchesCPUTwinUpToNearTies() throws {
        guard ANELoop.isSIMTAvailable else {
            throw XCTSkip("Metal unavailable — SIMT parity runs on device/simulator with a GPU.")
        }
        var s = 29
        func next() -> Double {
            s = (1103515245 &* s &+ 12345) % 2147483648
            return Double(s) / 2147483648.0 - 0.5
        }
        let b = Self.blocks
        var yRaw = [Float](); var candRaw = [Float]()
        var q0 = [UInt8]()
        var yBlocks: [[(Double, Double, Double)]] = []
        var candBlocks: [[(Double, Double, Double)]] = []
        for _ in 0..<b {
            var yb: [(Double, Double, Double)] = []
            var cb: [(Double, Double, Double)] = []
            for _ in 0..<8 {
                let c = (0.2 * next(), 0.2 * next(), 0.2 * next())
                cb.append(c)
                candRaw += [Float(c.0), Float(c.1), Float(c.2)]
            }
            let coarse = (0.1 * next(), 0.1 * next(), 0.1 * next())
            for _ in 0..<64 {
                let t = (0.16 * next() + coarse.0, 0.16 * next() + coarse.1,
                         0.16 * next() + coarse.2)
                yb.append(t)
                yRaw += [Float(t.0), Float(t.1), Float(t.2)]
                q0.append(UInt8(Int(abs(next()) * 8) % 8))
            }
            yBlocks.append(yb)
            candBlocks.append(cb)
        }

        // FLOAT PARITY, NOT DOUBLE: the twin must see the same
        // rounded inputs the kernel sees, or "near-tie" is untestable.
        let yD = yBlocks.enumerated().map { bi, yb in
            yb.indices.map { v -> (Double, Double, Double) in
                let base = (bi * 64 + v) * 3
                return (Double(yRaw[base]), Double(yRaw[base + 1]), Double(yRaw[base + 2]))
            }
        }
        let candD = candBlocks.enumerated().map { bi, cb in
            cb.indices.map { c -> (Double, Double, Double) in
                let base = (bi * 8 + c) * 3
                return (Double(candRaw[base]), Double(candRaw[base + 1]), Double(candRaw[base + 2]))
            }
        }

        guard let simt = ANELoop.sweepSIMT(
            q0: q0, y: yRaw, cand: candRaw,
            blockCount: b, sweeps: Self.sweeps) else {
            return XCTFail("sweepSIMT returned nil with Metal available")
        }
        XCTAssertEqual(simt.count, b * 64)

        var agree = 0
        var fStart = 0.0, fCPU = 0.0, fSIMT = 0.0
        for bi in 0..<b {
            let start = (0..<64).map { Int(q0[bi * 64 + $0]) }
            let cpu = ANELoop.sweepBlockCPU(
                q0: start, y: yD[bi], cand: candD[bi], k: Self.sweeps)
            let gpu = (0..<64).map { simt[bi * 64 + $0] }
            agree += zip(cpu, gpu).filter { UInt8($0.0) == $0.1 }.count
            fStart += blockF(start.map(UInt8.init), yD[bi], candD[bi])
            fCPU += blockF(cpu.map(UInt8.init), yD[bi], candD[bi])
            fSIMT += blockF(gpu, yD[bi], candD[bi])
        }
        let agreement = Double(agree) / Double(b * 64)

        // AL4 (hard): the GPU result never worsens the start state.
        XCTAssertLessThanOrEqual(fSIMT, fStart + 1e-9,
            "SIMT sweep increased F — monotonicity violated")
        // XP2 (near-ties only): overwhelming agreement, same objective.
        XCTAssertGreaterThanOrEqual(agreement, 0.98,
            "SIMT/CPU disagreement beyond the near-tie regime")
        XCTAssertLessThanOrEqual(abs(fSIMT - fCPU), max(1e-6, 0.01 * fCPU),
            "SIMT objective diverged from the CPU twin's")
        print(String(format: "ANE-LOOP SIMT parity: %.2f%% agree, F start %.2f cpu %.2f simt %.2f",
                     100 * agreement, fStart, fCPU, fSIMT))
    }

    func testRuntimeKZeroIsIdentity() throws {
        guard ANELoop.isSIMTAvailable else { throw XCTSkip("Metal unavailable.") }
        let b = 4
        let q0 = (0..<(b * 64)).map { UInt8($0 % 8) }
        let y = [Float](repeating: 0.1, count: b * 64 * 3)
        let cand = (0..<(b * 8 * 3)).map { Float($0 % 8) * 0.05 }
        // AL5 on the GPU: K = 0 must return the input verbatim.
        XCTAssertEqual(ANELoop.sweepSIMT(q0: q0, y: y, cand: cand,
                                         blockCount: b, sweeps: 0), q0)
    }
}
