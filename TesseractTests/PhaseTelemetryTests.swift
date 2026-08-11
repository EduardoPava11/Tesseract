// PhaseTelemetryTests.swift
// Tesseract
//
// Swift gate for the step-2 phase measurement (PhaseTelemetry),
// mirroring spec/quantization/PhasePalette.hs on the same 8³ model
// cube: the PP1 keystone identity, PP15 contraction, the chaos
// entropy bill (PP10's trace), and the provenance line.

import XCTest
@testable import Tesseract

final class PhaseTelemetryTests: XCTestCase {

    // Deterministic inputs (house LCG — no randomness in tests).
    private func lcgStream(_ seed: Int) -> AnyIterator<Double> {
        var s = seed
        return AnyIterator {
            s = (1103515245 &* s &+ 12345) % 2147483648
            return Double(s) / 2147483648.0
        }
    }

    // MARK: - PP1 + PP15 on the model cube

    func testKeystoneIdentityAndContraction() throws {
        let side = 8, frames = 8
        let u = lcgStream(11)
        let e = (0..<(side * side * frames)).map { _ in
            (u.next()! - 0.5, u.next()! - 0.5, u.next()! - 0.5)
        }
        let b = try XCTUnwrap(PhaseTelemetry.bands(errorField: e,
                                                   side: side, frameCount: frames))
        // PP1: the three reads ARE the 3:2:1 Haar bands, exactly.
        XCTAssertLessThanOrEqual(b.identityGap, 1e-9)
        let n = Double(side * side * frames)
        let reads: Double = b.d16 + b.d32 + b.d64
        let bandSum: Double = 3 * b.u4 + 2 * b.u2 + b.u1
        XCTAssertEqual(reads, bandSum / n, accuracy: 1e-9)
        // PP15: pooled distortion contracts.
        XCTAssertLessThanOrEqual(b.d16, b.d32 + 1e-12)
        XCTAssertLessThanOrEqual(b.d32, b.d64 + 1e-12)
    }

    func testBlockConstantFieldLivesInU4() throws {
        let side = 8, frames = 8
        // Constant on every 4³ block: all energy in u4, reads equal.
        var e = [(Double, Double, Double)]()
        for f in 0..<frames {
            for y in 0..<side {
                for x in 0..<side {
                    let v = Double((x / 4) + 2 * (y / 4) + 4 * (f / 4))
                    e.append((v * 0.1 - 0.3, 0.05, -0.02))
                }
            }
        }
        let b = try XCTUnwrap(PhaseTelemetry.bands(errorField: e,
                                                   side: side, frameCount: frames))
        XCTAssertLessThanOrEqual(abs(b.u2), 1e-9)
        XCTAssertLessThanOrEqual(abs(b.u1), 1e-9)
        XCTAssertEqual(b.d16, b.d64, accuracy: 1e-9)
        XCTAssertEqual(b.d32, b.d64, accuracy: 1e-9)
    }

    // MARK: - The chaos bill (PP10's trace)

    func testChaosBillBalancedConcentratedAndOrdered() throws {
        let side = 8, frames = 8
        func cube(_ pixel: (Int, Int, Int) -> UInt8) -> [[UInt8]] {
            (0..<frames).map { f in
                (0..<(side * side)).map { p in pixel(p % side, p / side, f) }
            }
        }
        // Balanced two-color ground: each 4³ block splits 32/32.
        let balanced = cube { x, y, f in (x + y + f) % 2 == 0 ? 128 : 129 }
        let bal = try XCTUnwrap(PhaseTelemetry.chaosBill(indexFrames: balanced,
                                                          side: side))
        let perBlock = PhaseTelemetry.logFactorial[64]
                     - 2 * PhaseTelemetry.logFactorial[32]
        XCTAssertEqual(bal.blocks, 2 * 2 * 2)
        XCTAssertEqual(bal.bill, Double(bal.blocks) * perBlock, accuracy: 1e-9)
        // Concentrated ground: PP10's vertex exception — bill zero.
        let solid = cube { _, _, _ in 255 }
        let sol = try XCTUnwrap(PhaseTelemetry.chaosBill(indexFrames: solid,
                                                          side: side))
        XCTAssertEqual(sol.blocks, 8)
        XCTAssertEqual(sol.bill, 0, accuracy: 1e-12)
        // Pure order: no ground voxels, no chaos blocks, no bill.
        let order = cube { _, _, _ in 17 }
        let ord = try XCTUnwrap(PhaseTelemetry.chaosBill(indexFrames: order,
                                                          side: side))
        XCTAssertEqual(ord.blocks, 0)
        XCTAssertEqual(ord.bill, 0, accuracy: 1e-12)
    }

    // MARK: - measure() + the provenance line

    func testMeasureAndTraceLine() throws {
        let side = 8, frames = 8
        // Table: entry i = (i, i, i); source mid gray; indices split
        // order/ground by left/right half — a two-phase toy cube.
        let table = Data((0..<256).flatMap { [UInt8($0), UInt8($0), UInt8($0)] })
        let tables = [Data](repeating: table, count: frames)
        let indexFrames: [[UInt8]] = (0..<frames).map { f in
            (0..<(side * side)).map { p in
                let x = p % side
                return x < side / 2 ? 100 : UInt8(128 + (x + p / side + f) % 2)
            }
        }
        let source: [[(Float, Float, Float)]] = (0..<frames).map { _ in
            [(Float, Float, Float)](repeating: (0.5, 0.5, 0.5),
                                    count: side * side)
        }
        let out = try XCTUnwrap(PhaseTelemetry.measure(
            indexFrames: indexFrames, tables: tables,
            sourceRGB: source, side: side))
        // The identity holds on a real (index, table, source) triple…
        XCTAssertLessThanOrEqual(out.identityGap, 1e-9)
        XCTAssertGreaterThan(out.f, 0)
        // …the right half (x ≥ 4) is a balanced two-color ground:
        // exactly the bx = 1 column of blocks — 1 × 2 × 2 = 4.
        XCTAssertEqual(out.chaosBlocks, 4)
        XCTAssertGreaterThan(out.logWBill, 0)
        // The trace line carries every field.
        let line = PhaseTelemetry.trace(out)
        for tag in ["PHASE F v1", "D16=", "D32=", "D64=", "F=",
                    "u4=", "u2=", "u1=", "gap=", "logW=", "blocks=4"] {
            XCTAssertTrue(line.contains(tag), "missing \(tag) in: \(line)")
        }
    }

    // MARK: - Provenance parser inertness (appended sections)

    func testStatsRebuildIgnoresAppendedPhaseLine() throws {
        // The DYAD STATS parser is prefix-scoped: a PHASE F line after
        // the stats block (and after DYAD ENERGY) must not disturb it.
        let stats = DyadPalette.analyze([(180, 140, 110), (170, 130, 100)])
        let table = DyadPalette.gifColorTable(DyadPalette.table(stats: stats))
        let c = stats.covariance
        let nums = [stats.centroid.l, stats.centroid.a, stats.centroid.b,
                    c[0][0], c[0][1], c[0][2], c[1][1], c[1][2], c[2][2]]
        let trace = ([ "DYAD STATS v1 frames=1",
                       nums.map { "\($0)" }.joined(separator: " "),
                       "PHASE F v1 D16=0 D32=0 D64=0 F=0 u4=0 u2=0 u1=0 gap=0 logW=0 blocks=0"
                     ]).joined(separator: "\n")
        let rebuilt = try XCTUnwrap(GIFMachine.rebuildTables(fromTrace: trace))
        XCTAssertEqual(rebuilt.count, 1)
        XCTAssertEqual(rebuilt[0], table)
    }
}
