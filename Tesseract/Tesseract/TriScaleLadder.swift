// TriScaleLadder.swift
// Tesseract
//
// Swift port of spec/output/TriScaleLadder.hs — the 64³ → 32³ → 16³
// spacetime pyramid, ported from SixFour's color head
// (Spec.TriScaleTraining + palette16.zig). One 2×2×2 spacetime block
// (frame pair × 2×2 cells) per coarse voxel: side and frame count
// halve together, and side × delay = 320 cs at every rung (TL4), so
// the loop is 3.2 s on the whole ladder.
//
// THE CARRIER is exact UInt64 block SUMS over the 4⁴ lattice levels
// (d = epoch, a/b/c = R/G/B, each 0..3 at the base rung) — sums
// compose transitively (TL1); rounded means do not (TL2), so no rung
// ever stores a mean. Lattice levels, not sRGB8 bytes, are the mass:
// realized sRGB8 has a floor of 32, so nothing would ever concentrate,
// while level mass has true zeros and makes the TL7 meter live.
//
// ★ THIS RUNG READ IS UNFINISHED WORK, AND SAYING SO IS THE POINT
// (NO-STUBS decree, 2026-08-14). Today this file pools the realized
// index cube into telemetry AFTER quantization: no GIF byte depends on
// it, and it trains nothing (★NO-CAPTURE-TRAINING).
//
// That is precisely what AD10 forbids. spec/output/AdditiveLadder.hs:
// "★ NO RUNG IS SILENT ... no rung can be demoted to telemetry."
// Daniel's ruling the same day: "all rungs require a meaningful
// additive to the creation of GIFs." AD11 PRICES the gap on a freely
// assigned cube: conformance is 0.0 at rung 16 and 0.0 at rung 32,
// because today's pipeline assigns freely at the fine rung and so
// conforms at the leaf stratum and nowhere else.
//
// Computing the whole 16³ and 32³ tower on every capture and then
// discarding it is a stub with a finished face. It is recorded here,
// on the file that does it, rather than in a doc nobody opens.
//
// THE CLOSE is the S8 port, and its shape is already ruled
// (docs/ATLAS.md §7, step 2: "promote RUNGING from METER to SIGNAL").
// The index becomes the SUM of its strata rather than a free choice:
//
//   bit 7    ROLE     figure/σ    depth, via the Bayer coverage (AD7)
//   bit 6    rung 16³ 4-level     4096 voxels write 1 bit
//   bits 5-3 rung 32³ 32-level    32768 voxels write 3 bits
//   bits 2-0 rung 64³ 256-level   262144 voxels write 3 bits
//
// AdditiveCensus.swift is the instrument that prices it before and
// after. The gate on doing the work is Daniel's own, recorded in
// ATLAS §8: nothing in §7 is wired before the shipping path has been
// seen on hardware. So this is BLOCKED, not forgotten, and the
// distinction is the whole reason this comment exists.

import Foundation

/// One rung of the pyramid: side³ voxels of exact per-axis UInt64
/// sums, frame-major then row-major.
struct RungCube: Equatable {
    let side: Int
    var d: [UInt64]
    var a: [UInt64]
    var b: [UInt64]
    var c: [UInt64]
}

/// Per-burst ladder telemetry (published by both capture managers).
struct RungTelemetry: Equatable {
    /// Grand lattice mass (d+a+b+c summed) at the base rung.
    let mass: UInt64
    /// TL3: the same mass at 64, 32, and 16 — nothing dropped,
    /// nothing double-counted.
    let massConserved: Bool
    /// TL7 meter, per transition: blocks whose 8 children carry
    /// ≤ 1 nonzero lattice mass — conditional factor W = 1, zero
    /// bits. These blocks are informationless at that rung.
    let freeBlocks3264: Int   // of 32³ = 32768
    let freeBlocks1632: Int   // of 16³ = 4096

    /// TL4 time law: GIF-exact centisecond delays; side × delay ==
    /// loopCs at every rung, and 128 has no integer delay (why the
    /// ladder caps at 64).
    static let delayCs: [Int: Int] = [64: 5, 32: 10, 16: 20]
    static let loopCs = 320

    /// TL8/TL9 (2026-08-10) — 16³ == 32³ == 64³ in the information
    /// process; compute time is the equivalence (one process, three
    /// rates, ×8 per rung). THE RESOLUTION OF DEPTH is rung 16: one
    /// judgment aggregates (64/16)³ = 64 base samples (two rungs,
    /// 8²), giving 16³ = 4096 judgments per 320 cs loop at 5 Hz
    /// while RGB rides the 64-rung at 20 Hz.
    static let baseRungSide = 64
    static let depthRungSide = 16
    static let samplesPerJudgment = 64
    static let judgmentsPerLoop = 4096
}

enum TriScaleLadder {

    /// levels[i] = (d, a, b, c) of palette index i — the base-4
    /// decomposition of the 4⁴ bijection, precomputed once.
    private static let levelTable: [(UInt64, UInt64, UInt64, UInt64)] =
        (0...255).map { i in
            let t = TesseractCoord(index: UInt8(i))
            return (UInt64(t.d), UInt64(t.a), UInt64(t.b), UInt64(t.c))
        }

    /// The base rung: the 64-frame index cube as lattice-level sums
    /// (each voxel is its own 1×1×1 block). nil unless the burst is
    /// the full 64³.
    static func rung64(frames: [QuantizedFrame]) -> RungCube? {
        let side = 64
        guard frames.count == side,
              frames.allSatisfy({ $0.paletteIndices.count == side * side })
        else { return nil }
        let n = side * side * side
        var d = [UInt64](repeating: 0, count: n)
        var a = [UInt64](repeating: 0, count: n)
        var b = [UInt64](repeating: 0, count: n)
        var c = [UInt64](repeating: 0, count: n)
        var v = 0
        for frame in frames {
            for idx in frame.paletteIndices {
                let t = levelTable[Int(idx)]
                d[v] = t.0; a[v] = t.1; b[v] = t.2; c[v] = t.3
                v += 1
            }
        }
        return RungCube(side: side, d: d, a: a, b: b, c: c)
    }

    /// TL1 carrier: one rung down by exact 2×2×2 sum pooling.
    static func poolL(_ cube: RungCube) -> RungCube {
        let s = cube.side, h = s / 2, n = h * h * h
        var d = [UInt64](repeating: 0, count: n)
        var a = [UInt64](repeating: 0, count: n)
        var b = [UInt64](repeating: 0, count: n)
        var c = [UInt64](repeating: 0, count: n)
        for f in 0..<h {
            for r in 0..<h {
                for col in 0..<h {
                    var sd: UInt64 = 0, sa: UInt64 = 0
                    var sb: UInt64 = 0, sc: UInt64 = 0
                    for df in 0...1 {
                        for dr in 0...1 {
                            for dc in 0...1 {
                                let src = (2 * f + df) * s * s
                                        + (2 * r + dr) * s
                                        + (2 * col + dc)
                                sd &+= cube.d[src]; sa &+= cube.a[src]
                                sb &+= cube.b[src]; sc &+= cube.c[src]
                            }
                        }
                    }
                    let dst = f * h * h + r * h + col
                    d[dst] = sd; a[dst] = sa; b[dst] = sb; c[dst] = sc
                }
            }
        }
        return RungCube(side: h, d: d, a: a, b: b, c: c)
    }

    /// Total lattice mass of a rung (TL3 invariant).
    static func mass(_ cube: RungCube) -> UInt64 {
        var t: UInt64 = 0
        for i in 0..<cube.d.count {
            t &+= cube.d[i] &+ cube.a[i] &+ cube.b[i] &+ cube.c[i]
        }
        return t
    }

    /// TL7 meter for the transition out of `fine`: coarse blocks
    /// whose 8 children carry ≤ 1 nonzero lattice mass (W = 1).
    static func freeBlocks(fine: RungCube) -> Int {
        let s = fine.side, h = s / 2
        var free = 0
        for f in 0..<h {
            for r in 0..<h {
                for col in 0..<h {
                    var nonzero = 0
                    for df in 0...1 {
                        for dr in 0...1 {
                            for dc in 0...1 {
                                let src = (2 * f + df) * s * s
                                        + (2 * r + dr) * s
                                        + (2 * col + dc)
                                let m = fine.d[src] &+ fine.a[src]
                                      &+ fine.b[src] &+ fine.c[src]
                                if m > 0 { nonzero += 1 }
                            }
                        }
                    }
                    if nonzero <= 1 { free += 1 }
                }
            }
        }
        return free
    }

    /// The full ladder over a finished burst. nil unless 64³.
    static func telemetry(frames: [QuantizedFrame]) -> RungTelemetry? {
        guard let r64 = rung64(frames: frames) else { return nil }
        let r32 = poolL(r64)
        let r16 = poolL(r32)
        let m = mass(r64)
        return RungTelemetry(
            mass: m,
            massConserved: m == mass(r32) && m == mass(r16),
            freeBlocks3264: freeBlocks(fine: r64),
            freeBlocks1632: freeBlocks(fine: r32)
        )
    }
}
