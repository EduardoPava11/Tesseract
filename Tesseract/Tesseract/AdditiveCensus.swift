// AdditiveCensus.swift
// Tesseract
//
// S1 INSTRUMENT — the measurement half of the ADDITIVE LADDER
// (spec/output/AdditiveLadder.hs is authoritative, AD1–AD12).
//
// Daniel's ruling (2026-08-14): "all rungs require a meaningful
// additive to the creation of GIFs." The law seats one stratum of
// the index on each rung:
//
//   bit 7    ROLE     figure/σ    — depth, via the Bayer coverage
//   bit 6    rung 16³ 4-level     — 4096 voxels write 1 bit
//   bits 5-3 rung 32³ 32-level    — 32768 voxels write 3 bits
//   bits 2-0 rung 64³ 256-level   — 262144 voxels write 3 bits
//
// so index = role·128 + r16·64 + r32·8 + r64 (AD2).
//
// A stratum's bits are decided at its own rung, therefore CONSTANT
// across that rung's block. Today's pipeline assigns freely at the
// fine rung, so it conforms at the leaf stratum and nowhere else —
// the spec measures 0.0 at rungs 16 and 32 on a freely-assigned
// cube (AD11). That gap is what the S8 port closes, and this file
// is how it is priced before and after.
//
// MEASUREMENT ONLY. No index, no table, no byte depends on these
// numbers; the census rides the DYAD provenance comment.

import Foundation

enum AdditiveCensus {

    // MARK: - The strata (AD1)

    struct Stratum: Sendable {
        let name: String
        let low: Int        // lowest bit index owned
        let width: Int      // bits owned
        let rung: Int       // cube side that writes it (0 = depth)
        let level: Int      // classes distinguishable once written

        /// Block side on a fine cube of side 64. The role stratum is
        /// not written at a rung (AD7 — it is a Bayer expansion of
        /// the coverage field, varying per fine voxel), so its block
        /// is one voxel and its conformance is trivially 1; the law
        /// that constrains it is AD7's 17 patterns.
        var blockSide: Int { rung == 0 ? 1 : 64 / rung }
    }

    static let role = Stratum(name: "role", low: 7, width: 1, rung: 0, level: 2)
    static let r16 = Stratum(name: "rung16", low: 6, width: 1, rung: 16, level: 4)
    static let r32 = Stratum(name: "rung32", low: 3, width: 3, rung: 32, level: 32)
    static let r64 = Stratum(name: "rung64", low: 0, width: 3, rung: 64, level: 256)

    static let strata: [Stratum] = [role, r16, r32, r64]

    // MARK: - The index algebra (AD2, AD5)

    static func field(_ st: Stratum, _ i: UInt8) -> Int {
        (Int(i) >> st.low) & ((1 << st.width) - 1)
    }

    /// The prefix law's operator: the class a stratum completes.
    static func classAt(_ st: Stratum, _ i: UInt8) -> Int { Int(i) >> st.low }

    /// index = role·128 + r16·64 + r32·8 + r64 (AD2's identity).
    static func compose(role r: Int, r16 a: Int, r32 b: Int, r64 c: Int) -> UInt8 {
        UInt8((r << 7) + (a << 6) + (b << 3) + c)
    }

    // MARK: - The census

    /// Fraction of a stratum's rung-blocks on which its field is
    /// constant. 1.0 means the cube already obeys the additive law
    /// at that stratum.
    static func conformance(_ st: Stratum, indexFrames: [[UInt8]],
                            side: Int) -> Double {
        let k = st.blockSide
        guard k >= 1, side % k == 0, indexFrames.count % k == 0,
              let first = indexFrames.first, first.count == side * side
        else { return 1 }
        let n = side / k
        let nT = indexFrames.count / k
        var constant = 0, total = 0
        for bt in 0..<nT {
            for by in 0..<n {
                for bx in 0..<n {
                    var seen = -1
                    var uniform = true
                    for dt in 0..<k where uniform {
                        let frame = indexFrames[bt * k + dt]
                        for dy in 0..<k where uniform {
                            for dx in 0..<k {
                                let v = field(st, frame[(by * k + dy) * side + bx * k + dx])
                                if seen < 0 { seen = v }
                                else if v != seen { uniform = false; break }
                            }
                        }
                    }
                    total += 1
                    if uniform { constant += 1 }
                }
            }
        }
        return total == 0 ? 1 : Double(constant) / Double(total)
    }

    /// Distinct classes used at a stratum's cumulative level (AD12).
    static func classesUsed(_ st: Stratum, indexFrames: [[UInt8]]) -> Int {
        var seen = Set<Int>()
        for f in indexFrames { for i in f { seen.insert(classAt(st, i)) } }
        return seen.count
    }

    /// Occupancy of a stratum's classes over the whole cube, and the
    /// balance target the 1024 invariant sets for it (AD4). At the
    /// emitted fine rung the cube holds 64·4096 voxels, so the target
    /// per class is voxels/level.
    static func occupancy(_ st: Stratum, indexFrames: [[UInt8]]) -> (min: Int, max: Int, target: Int) {
        var counts = [Int](repeating: 0, count: st.level)
        for f in indexFrames {
            for i in f {
                let c = classAt(st, i)
                if c < counts.count { counts[c] += 1 }
            }
        }
        let voxels = indexFrames.reduce(0) { $0 + $1.count }
        return (counts.min() ?? 0, counts.max() ?? 0, voxels / max(1, st.level))
    }

    // MARK: - Trace (ADDITIVE CENSUS v1)

    /// One header plus one line per stratum:
    ///   name block conformance classesUsed level occMin occMax occTarget
    /// Shortest exact round-trip doubles for the conformance, the
    /// DYAD ENERGY format law.
    static func trace(indexFrames: [[UInt8]], side: Int) -> String {
        var lines = ["ADDITIVE CENSUS v1 frames=\(indexFrames.count) side=\(side)"]
        for st in strata {
            let conf = conformance(st, indexFrames: indexFrames, side: side)
            let used = classesUsed(st, indexFrames: indexFrames)
            let occ = occupancy(st, indexFrames: indexFrames)
            lines.append("\(st.name) \(st.blockSide) \(conf) \(used) \(st.level) "
                         + "\(occ.min) \(occ.max) \(occ.target)")
        }
        return lines.joined(separator: "\n")
    }
}
