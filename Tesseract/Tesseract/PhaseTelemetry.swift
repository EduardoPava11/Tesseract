// PhaseTelemetry.swift
// Tesseract
//
// STEP 2 of the phase-palette law (docs/phase-palette-design.md,
// rulings R1–R5 confirmed): MEASUREMENT of the objective
//
//     F = D_16 + D_32 + D_64
//
// on the emitted DYAD cube, plus the chaos entropy bill. Port of
// spec/quantization/PhasePalette.hs (the Haskell spec is
// authoritative): the PP1 keystone identity
//
//     F = (3·‖u4‖² + 2·‖u2‖² + ‖u1‖²) / N
//       = (‖e‖² + ‖Π₂e‖² + ‖Π₄e‖²) / N
//
// is carried as a traced witness (identityGap — float noise only),
// and Σ log W over ground-half occupancy per 4³ spacetime block is
// the traced entropy-bill ESTIMATE of PP10 (an LZW lower-bound
// heuristic, never the byte count).
//
// At this step nothing but the provenance comment depends on these
// numbers: no index, no table, no byte. The chaos SOLVER is step 4,
// flag-gated (ruling R3).

import Foundation

enum PhaseTelemetry {

    struct Output: Sendable {
        /// The three reads' distortions (mean ‖·‖² per voxel, OKLab).
        let d16: Double
        let d32: Double
        let d64: Double
        /// Haar band energies ‖u4‖², ‖u2‖², ‖u1‖² (unnormalized).
        let u4: Double
        let u2: Double
        let u1: Double
        /// PP1 witness: |F − (3u4+2u2+u1)/N|. Algebraically zero;
        /// anything above float noise is a pooling bug.
        let identityGap: Double
        /// Σ log W(n) over ground-half (index ≥ 128) occupancy per
        /// 4³ spacetime block — the chaos entropy bill estimate.
        let logWBill: Double
        /// Blocks that contained any ground-half voxel.
        let chaosBlocks: Int

        var f: Double { d16 + d32 + d64 }
    }

    // MARK: - The pooling tower (generic over cube shape, spec § 2)

    /// Band split of an error field over a side×side×frames cube.
    /// Returns nil unless both dimensions carry the full 2×2×2
    /// pooling tower (divisible by 4).
    static func bands(
        errorField e: [(Double, Double, Double)],
        side: Int, frameCount: Int
    ) -> (d16: Double, d32: Double, d64: Double,
          u4: Double, u2: Double, u1: Double, identityGap: Double)? {
        guard side % 4 == 0, frameCount % 4 == 0,
              e.count == side * side * frameCount else { return nil }
        let n = Double(e.count)

        func projNorm2(_ b: Int) -> Double {
            let sb = side / b, fb = frameCount / b
            var sums = [(Double, Double, Double)](repeating: (0, 0, 0),
                                                  count: sb * sb * fb)
            for f in 0..<frameCount {
                for y in 0..<side {
                    for x in 0..<side {
                        let v = e[x + side * (y + side * f)]
                        let idx = (x / b) + sb * ((y / b) + sb * (f / b))
                        sums[idx].0 += v.0
                        sums[idx].1 += v.1
                        sums[idx].2 += v.2
                    }
                }
            }
            let vol = Double(b * b * b)
            return sums.reduce(0) { acc, s in
                acc + (s.0 * s.0 + s.1 * s.1 + s.2 * s.2) / vol
            }
        }

        let e2 = e.reduce(0) { $0 + ($1.0 * $1.0 + $1.1 * $1.1 + $1.2 * $1.2) }
        let p2 = projNorm2(2)
        let p4 = projNorm2(4)
        let d64 = e2 / n, d32 = p2 / n, d16 = p4 / n
        let u4 = p4, u2 = p2 - p4, u1 = e2 - p2
        let gap = abs((d16 + d32 + d64) - (3 * u4 + 2 * u2 + u1) / n)
        return (d16, d32, d64, u4, u2, u1, gap)
    }

    // MARK: - The chaos entropy bill (spec § 6, PP10's trace)

    /// Σ log W over ground-half occupancy per 4³ spacetime block:
    /// log W(n) = lgamma(m+1) − Σ lgamma(nᵢ+1), m = ground voxels
    /// in the block. Vertex-concentrated blocks contribute 0 —
    /// PP10's exception, visible in the trace as it should be.
    static func chaosBill(
        indexFrames: [[UInt8]], side: Int
    ) -> (bill: Double, blocks: Int)? {
        let frameCount = indexFrames.count
        guard side % 4 == 0, frameCount % 4 == 0,
              indexFrames.allSatisfy({ $0.count == side * side }) else { return nil }
        let sb = side / 4, fb = frameCount / 4
        var counts = [[Int]](repeating: [Int](repeating: 0, count: 128),
                             count: sb * sb * fb)
        for f in 0..<frameCount {
            let frame = indexFrames[f]
            for y in 0..<side {
                for x in 0..<side {
                    let idx = Int(frame[x + side * y])
                    guard idx >= 128 else { continue }
                    counts[(x / 4) + sb * ((y / 4) + sb * (f / 4))][idx - 128] += 1
                }
            }
        }
        var bill = 0.0
        var blocks = 0
        for block in counts {
            let m = block.reduce(0, +)
            guard m > 0 else { continue }
            blocks += 1
            var w = logFactorial[m]
            for c in block where c > 0 { w -= logFactorial[c] }
            bill += w
        }
        return (bill, blocks)
    }

    /// log k! for k = 0...64 — the spec's logFacts table (block
    /// occupancies never exceed the 4³ = 64 voxels of a block).
    static let logFactorial: [Double] = {
        var acc = [0.0]
        for k in 1...64 { acc.append(acc[k - 1] + log(Double(k))) }
        return acc
    }()

    // MARK: - The capture-level measurement

    /// Measure F and the chaos bill on an emitted DYAD cube. Colors
    /// resolve through each frame's own 768-byte table (the shipped
    /// stream, before any mirror — telemetry basis = emitted cube);
    /// the source is the record path's rawRGB, converted through the
    /// same byte quantization the pipeline uses (round half-even).
    static func measure(
        indexFrames: [[UInt8]],
        tables: [Data],
        sourceRGB: [[(Float, Float, Float)]],
        side: Int
    ) -> Output? {
        let frameCount = indexFrames.count
        guard tables.count == frameCount, sourceRGB.count == frameCount,
              tables.allSatisfy({ $0.count == 768 }) else { return nil }

        var e = [(Double, Double, Double)]()
        e.reserveCapacity(side * side * frameCount)
        for f in 0..<frameCount {
            let table = tables[f]
            // 256 table entries → OKLab once per frame.
            let tableLab: [OKLabColor] = (0..<256).map { i in
                DyadPalette.oklab(fromSRGB8: (
                    table[table.startIndex + 3 * i],
                    table[table.startIndex + 3 * i + 1],
                    table[table.startIndex + 3 * i + 2]))
            }
            let frame = indexFrames[f]
            let src = sourceRGB[f]
            guard frame.count == side * side, src.count == side * side else { return nil }
            for p in 0..<frame.count {
                let shown = tableLab[Int(frame[p])]
                let truth = DyadPalette.oklab(fromSRGB8: srgb8(from: src[p]))
                e.append((shown.l - truth.l, shown.a - truth.a, shown.b - truth.b))
            }
        }

        guard let b = bands(errorField: e, side: side, frameCount: frameCount),
              let chaos = chaosBill(indexFrames: indexFrames, side: side)
        else { return nil }
        return Output(d16: b.d16, d32: b.d32, d64: b.d64,
                      u4: b.u4, u2: b.u2, u1: b.u1,
                      identityGap: b.identityGap,
                      logWBill: chaos.bill, chaosBlocks: chaos.blocks)
    }

    /// The provenance line. Appended to the DYAD trace; the STATS
    /// parser is prefix-scoped, so appended sections are inert.
    static func trace(_ o: Output) -> String {
        String(format: "PHASE F v1 D16=%.6g D32=%.6g D64=%.6g F=%.6g "
                     + "u4=%.6g u2=%.6g u1=%.6g gap=%.3g logW=%.6g blocks=%d",
               o.d16, o.d32, o.d64, o.f, o.u4, o.u2, o.u1,
               o.identityGap, o.logWBill, o.chaosBlocks)
    }

    /// The pipeline's byte quantization (round half-to-even ×255),
    /// kept identical to DyadPipeline's record-path conversion.
    static func srgb8(from c: (Float, Float, Float)) -> (UInt8, UInt8, UInt8) {
        func to8(_ v: Float) -> UInt8 {
            UInt8(min(255, max(0, (Double(v) * 255).rounded(.toNearestOrEven))))
        }
        return (to8(c.0), to8(c.1), to8(c.2))
    }
}
