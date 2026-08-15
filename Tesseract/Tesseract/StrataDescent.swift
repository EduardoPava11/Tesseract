// StrataDescent.swift
// Tesseract
//
// S8: THE RUNGS WRITE THE INDEX (port of spec/output/AdditiveLadder.hs,
// AD1-AD12; the Haskell is authoritative).
//
// Daniel's ruling (2026-08-14): "all rungs require a meaningful
// additive to the creation of GIFs", and separately: "read the
// incoming information in 16x16, 32x32 and 64x64 so that we can lift
// a coarse intuition into the final 64x64x64 voxel creation."
//
// The spec states the principle in one line: "A rung that only
// measures is not a view of the GIF, it is a view of the measurement."
// Before this file, TriScaleLadder pooled the REALIZED index cube into
// telemetry after quantization, so the coarse rungs saw only their own
// output. Here they read the INCOMING staged signal and each one
// writes its own bits of every index:
//
//   bit 7    ROLE     figure/σ    depth, via the Bayer coverage (AD7)
//   bit 6    rung 16³ 4-level     4096 voxels write 1 bit
//   bits 5-3 rung 32³ 32-level    32768 voxels write 3 bits
//   bits 2-0 rung 64³ 256-level   262144 voxels write 3 bits
//
// index = role·128 + r16·64 + r32·8 + r64 (AD2), and a stratum's bits
// are decided AT ITS OWN RUNG, therefore CONSTANT across that rung's
// spacetime block. That constancy is the whole measurable content of
// the law, and AdditiveCensus.conformance is the meter (AD11).
//
// ── THE TREE IS ALREADY THIS SHAPE ──────────────────────────────
//
// No new structure is needed, which is why this is a port and not a
// design. PairTree's 128 figure leaves are 7 generations, first
// generation = MSB, and PT5 says truncating ℓ bits of the leaf index
// EQUALS the nearest level-ℓ centroid. So the strata ARE the tree's
// own generations, and DL1's fixed serial depth 3 with fan-outs
// [2, 8, 8] is exactly this descent:
//
//   j >> 6        = h, the half              generation 1   (rung 16)
//   (j >> 3) & 7  = m, the node under h      generations 2-4 (rung 32)
//   j & 7         = the leaf under the node  generations 5-7 (rung 64)
//
// and node c = j >> 3 in 0..<16 is PairTree's own `nodes16`, whose
// members are leaves 8c ..< 8c+8. 2 × 8 × 8 = 128.
//
// ── WHY LOOKAHEAD, NOT GREEDY ───────────────────────────────────
//
// The obvious descent commits each level to the nearest node MEAN.
// nn/descent measured that and it is bad: 0.8601 leaf agreement
// against exhaustive, at 8x the excess distortion. The lawful form is
// LOOKAHEAD-L2 (DL7 dominance): commit to the candidate whose
// DESCENDANT layer holds the nearest point, which measured 0.9652 at
// 0.000076 excess. DL6 then says the level below a well-chosen
// commitment is EXACT. That is the entire reason nn/descent existed,
// and this file is where its finding is spent.
//
// So each commitment looks one layer down, and the leaf is exact:
//
//   stage A (rung 16)  choose h by summing, over the block's eight
//                      rung-32 sub-blocks, the distance from each
//                      sub-block mean to its nearest node under h
//   stage B (rung 32)  choose the node by the nearest LEAF under it,
//                      read from the 2×2×2 block mean
//   stage C (rung 64)  exact argmin over that node's 8 leaves
//
// ── COST ────────────────────────────────────────────────────────
//
// The fine stage searches 8 candidates instead of 128, so the inner
// loop shrinks by 16x. Whole-cube distance evaluations fall from
// 262144 × 128 = 33.5M to roughly 4.5M. The descent is cheaper than
// the exhaustive search it replaces, not a cost paid for structure.
//
// ── WHAT THIS FILE DOES NOT DO ──────────────────────────────────
//
// Conformance lands at the ROLE-PURE fraction, not at 1.0, and the
// reason is a standing decree this port deliberately does not break.
// AD3 notes the role bit was "lifted out of its pair (Daniel's σ
// ruling)", so the additive law wants σ to set bit 7 and SHARE the
// colour bits. The shipped involution instead sets σ = 255 − j, which
// complements all eight bits (DY2/PT6, locked byte-for-byte by
// DyadGIFContractTests). Under the complement, a rung-16 block holding
// both figure and σ pixels carries bit 6 in both polarities, so mixed
// blocks cannot conform however well the descent chooses. Role-pure
// blocks conform exactly. Reaching 1.0 means relabelling the σ half
// from T[255−j] to T[128+j], which is a palette PERMUTATION (free in
// LZW, visually identical output) but changes a decreed byte contract,
// and that is Daniel's ruling to make, not this file's.

import Foundation

/// The additive ladder's assignment: three reads, three strata, one
/// index. Pure and deterministic; `AdditiveCensus` is its meter.
enum StrataDescent {

    /// Leaves under a node (AD3's bit-triple): 8.
    static let leavesPerNode = 8
    /// Nodes under a half: 8. Halves: 2. 2 × 8 × 8 = 128 figures.
    static let nodesPerHalf = 8
    static let halves = 2
    /// Rung-16 blocks are 4×4×4 on the fine cube, rung-32 are 2×2×2.
    static let coarseBlock = 4
    static let midBlock = 2

    /// The block extent on an axis of length `n`, wanting `want`.
    ///
    /// ★ THIS IS NOT A SECOND LAW. The spec states the ladder on the
    /// cube's OWN extent, not on a fixed 64 ("nT = length cube div k,
    /// the cube's own depth, not 64"), and a cube shorter than a block
    /// has no blocks of that rung at all, which `conformance` treats as
    /// vacuously conformant. So a short axis does not get a different
    /// descent, it gets the SAME descent with the block clamped to what
    /// exists. Every shipped shape (64 frames of 64², the live coarse
    /// read of 16 frames of 16²) returns `want` unchanged; only the
    /// small cubes the tests build ever clamp.
    static func blockFit(_ n: Int, _ want: Int) -> Int {
        guard n > 0 else { return 1 }
        var k = min(want, n)
        while k > 1 && n % k != 0 { k -= 1 }
        return max(1, k)
    }

    /// Assign a whole cube under the additive law.
    ///
    /// - labs: the staged OKLab signal, per frame, `side²` each. This
    ///   is the INCOMING read the coarse rungs pool, never the
    ///   realized index cube.
    /// - masks: face flags (true = figure)
    /// - fars: fully-pulled flags (index is exactly 255)
    /// - primaries: the 128 figure leaves per frame, in leaf order
    /// - nodes16: the 16 depth-4 node means per frame (PairTree P2)
    ///
    /// The cube must divide by the coarse block on every axis. Every
    /// shipped shape does (64 frames of 64², and the live coarse read
    /// of 16 frames of 16²), so a cube that does not is a DEFECT and
    /// traps in DEBUG rather than quietly taking a different law.
    static func assign(labs: [[OKLabColor]],
                       masks: [[Bool]],
                       fars: [[Bool]],
                       primaries: [[OKLabColor]],
                       nodes16: [[OKLabColor]],
                       side: Int) -> [[UInt8]] {
        let frames = labs.count
        guard frames > 0, side > 0 else { return [] }
        assert(primaries.count == frames && nodes16.count == frames
               && masks.count == frames && fars.count == frames,
               "ragged cube: the five arrays must describe one cube")
        assert(primaries.allSatisfy { $0.count == DyadPalette.primaryCount },
               "the descent needs all 128 tree leaves")
        assert(nodes16.allSatisfy { $0.count == halves * nodesPerHalf },
               "the descent needs the 16 depth-4 nodes (PairTree P2)")

        // The block extents, clamped to the cube (see `blockFit`).
        // Mid is half of coarse, which is the 2×2×2 atom itself.
        let ktC = blockFit(frames, coarseBlock), ksC = blockFit(side, coarseBlock)
        let ktM = max(1, ktC / midBlock), ksM = max(1, ksC / midBlock)

        let nT16 = frames / ktC, n16y = side / ksC
        let nT32 = frames / ktM, n32y = side / ksM

        // The half chosen per rung-16 block, and the node per rung-32
        // block. Each is written ONCE at its own rung, which is exactly
        // what makes its bits constant across that block (AD11).
        var halfOf = [Int](repeating: 0, count: nT16 * n16y * n16y)
        var nodeOf = [Int](repeating: 0, count: nT32 * n32y * n32y)

        // ── The rung-32 READ: one OKLab mean per 2×2×2 spacetime block
        // of the INCOMING staged signal. Computed first because stage A
        // looks ahead at it.
        var midMean = [OKLabColor](repeating: OKLabColor(l: 0, a: 0, b: 0),
                                   count: nodeOf.count)
        for bt in 0..<nT32 {
            for by in 0..<n32y {
                for bx in 0..<n32y {
                    var l = 0.0, a = 0.0, b = 0.0
                    for dt in 0..<ktM {
                        let f = bt * ktM + dt
                        for dy in 0..<ksM {
                            for dx in 0..<ksM {
                                let c = (by * ksM + dy) * side + bx * ksM + dx
                                l += labs[f][c].l; a += labs[f][c].a; b += labs[f][c].b
                            }
                        }
                    }
                    let d = Double(ktM * ksM * ksM)
                    midMean[(bt * n32y + by) * n32y + bx] =
                        OKLabColor(l: l / d, a: a / d, b: b / d)
                }
            }
        }

        // ── Stage A (rung 16): the half, by LOOKAHEAD one layer down.
        // Read the rung-32 sub-block means inside this rung-16 block
        // and ask which half's nodes cover them better. The tree is
        // constant across the block's own frames by the rung-16
        // cadence (TL8/TL9), so frame 0 of the block supplies it.
        let mPerC_t = ktC / ktM, mPerC_s = ksC / ksM
        for bt in 0..<nT16 {
            for by in 0..<n16y {
                for bx in 0..<n16y {
                    let tree = nodes16[bt * ktC]
                    var cost = [Double](repeating: 0, count: halves)
                    for dt in 0..<mPerC_t {
                        for dy in 0..<mPerC_s {
                            for dx in 0..<mPerC_s {
                                let mt = bt * mPerC_t + dt
                                let my = by * mPerC_s + dy
                                let mx = bx * mPerC_s + dx
                                let m = midMean[(mt * n32y + my) * n32y + mx]
                                for h in 0..<halves {
                                    var best = Double.infinity
                                    for k in 0..<nodesPerHalf {
                                        let d = DyadPalette.dLab2(tree[h * nodesPerHalf + k], m)
                                        if d < best { best = d }
                                    }
                                    cost[h] += best
                                }
                            }
                        }
                    }
                    halfOf[(bt * n16y + by) * n16y + bx] = cost[1] < cost[0] ? 1 : 0
                }
            }
        }

        // ── Stage B (rung 32): the node under that half, by LOOKAHEAD
        // to the leaves. DL6: given the half, this level is exact.
        for bt in 0..<nT32 {
            for by in 0..<n32y {
                for bx in 0..<n32y {
                    let leaves = primaries[bt * ktM]
                    let h = halfOf[((bt / mPerC_t) * n16y + by / mPerC_s) * n16y
                                   + bx / mPerC_s]
                    let m = midMean[(bt * n32y + by) * n32y + bx]
                    var bestC = h * nodesPerHalf
                    var bestD = Double.infinity
                    for k in 0..<nodesPerHalf {
                        let c = h * nodesPerHalf + k
                        for e in 0..<leavesPerNode {
                            let d = DyadPalette.dLab2(leaves[c * leavesPerNode + e], m)
                            if d < bestD { bestD = d; bestC = c }
                        }
                    }
                    nodeOf[(bt * n32y + by) * n32y + bx] = bestC
                }
            }
        }

        // ── Stage C (rung 64): the leaf, exact over the node's 8.
        var out: [[UInt8]] = []
        out.reserveCapacity(frames)
        for f in 0..<frames {
            let leaves = primaries[f]
            var frame = [UInt8](repeating: 0, count: side * side)
            for y in 0..<side {
                for x in 0..<side {
                    let p = y * side + x
                    if !masks[f][p] && fars[f][p] {
                        frame[p] = UInt8(DyadPalette.backgroundIndex)
                        continue
                    }
                    let c = nodeOf[((f / ktM) * n32y + y / ksM) * n32y + x / ksM]
                    let lc = labs[f][p]
                    var bestJ = c * leavesPerNode
                    var bestD = Double.infinity
                    for e in 0..<leavesPerNode {
                        let j = c * leavesPerNode + e
                        let d = DyadPalette.dLab2(leaves[j], lc)
                        if d < bestD { bestD = d; bestJ = j }
                    }
                    // The role stratum is bit 7. The shipped involution
                    // puts σ at 255 − j (see the file header on why
                    // this port keeps it).
                    frame[p] = masks[f][p] ? UInt8(bestJ) : UInt8(255 - bestJ)
                }
            }
            out.append(frame)
        }
        return out
    }
}
