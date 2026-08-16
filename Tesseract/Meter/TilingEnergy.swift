// TilingEnergy.swift
// Tesseract
//
// ★ THE VALUE HEAD, AND IT HAS NO WEIGHTS.
//
// Port of spec/statistics/TilingEntropy.hs (TE1 to TE10) plus the
// Pareto order of spec/neural/MerkleSearch.hs (§4, MT6 to MT9). The
// Haskell is authoritative; TilingEnergyTests pins every number here
// to the figures that spec's own harness prints.
//
// WHY THIS FILE EXISTS. MerkleSearch's whole economy (MT9) is that
// KataGo must LEARN a value head because Go has no closed form for a
// non-terminal position, and this app has one. E and E_wall are exact
// arithmetic in the wire's own units, computable from any candidate
// with no model at all, so only the policy is ever learned. This file
// is that closed form, and until it existed the tree had nothing to
// rank with.
//
// ── THE TWO ENERGIES, AND WHY BOTH ──────────────────────────────
//
//   E       = Σ nᵢ·log₂(nᵢ/16) bits over the 256-bin occupancy
//             histogram of a 64×64 index frame. Ground state 0 at
//             every colour exactly 16 times; ceiling 32768 at a solid
//             frame. It is N·D(p‖uniform): a divergence in bits, so
//             it is the RATE LEDGER read from the other end (TE10).
//
//   E_wall  = B·(1 − h(w)) over the B = 8064 open-lattice bonds,
//             w = the fraction of bonds whose two cells sit on
//             opposite sides of the σ split. Order and ANTI-order
//             cost the same: solid (w = 0) and Néel (w = 1) both sit
//             at the ceiling, random static near zero (TE8).
//
// ★ NEITHER IS A SCALAR SCORE AND THEY ARE NOT SUMMED. TE8 says in as
// many words that a dimensionless wall fraction and a normalised
// entropy are different currencies; both of these are in BITS, which
// is what makes the pair lawful, but the pair is still a PAIR. The
// order is (E low, E_wall high) and the answer is the Pareto front,
// because MT7 measured each energy blind to a different degeneracy
// and MT8 showed the front excludes both by DOMINATION rather than by
// tuning. A scalar would have had to pick a corner.
//
// ── ★ THE THIRD STRATUM, AND THE RULING BEHIND IT ───────────────
//
// Daniel, 2026-08-15, two rulings that are one object seen twice:
// the value head GETS a temporal bond, on the CLOSED loop; and a
// rotation of Z/64 IS an equivalence on the artifact (Ruling 7,
// open since 2026-08-14, now answered).
//
// E_time = B_t·(1 − h(w_t)) over the cyclic bonds (p, t) ~ (p, t+1
// mod nf). B_t = nf·4096 = 262144 for a 64-tick cube, and the last
// bond is the 63 → 0 one. It is the SAME law as E_wall over a
// different set of adjacent pairs, so it needs no new constant and
// lands in the same currency.
//
// ★ WHY THIS FILE NEEDED IT. E pools the histogram over all frames
// and E_wall sums disjoint per-frame bond sets, so BOTH are symmetric
// in the 64 frames: this meter used to score a GIF and its shuffle
// identically. It could not see a delta or a loop at all. E_time is
// invariant under a ROTATION (exactly, on the integer observables)
// and not under a SHUFFLE, which is precisely the distinction the
// artifact makes. Spec TE11-TE15.
//
// ★ AND IT IS THE MISSING HALF OF DEPTH. Depth is 57% of the retained
// capture and reaches the artifact as ONE BIT per voxel, the role bit
// (AD7). E_wall reads where that bit changes across the plane. Nothing
// read where it changes along the loop, which is depth's motion. This
// is not a new quantity bolted on; it is the second direction of a
// measurement that had only ever been taken in one.
//
// The three strata are disjoint and all in bits, so TE15 says they MAY
// be summed. They are kept separate anyway, because the ruling asked
// for the artifact to be categorized BY deltas and a sum discards
// exactly that. Summing is lawful; collapsing is lossy; both are true.

import Foundation

enum TilingEnergy {

    // MARK: - The plane and its counts (TE §1)

    static let side = 64
    static let cells = side * side          // N = 4096
    static let colors = 256                 // K
    static let balanced = cells / colors    // 16, the ground occupancy
    static let bonds = 2 * side * (side - 1) // B = 8064

    /// log₂|Ω| for one frame: 32768 bits exactly, the ceiling of E.
    static let omegaBits = Double(cells) * log2(Double(colors))

    // MARK: - The index stratum (TE §2)

    /// Occupancy histogram of one index frame.
    static func histogram(_ frame: [UInt8]) -> [Int] {
        var h = [Int](repeating: 0, count: colors)
        for i in frame { h[Int(i)] += 1 }
        return h
    }

    /// Zeroth-order entropy, bits per cell in [0, 8].
    static func h0(_ hist: [Int]) -> Double {
        let n = Double(hist.reduce(0, +))
        guard n > 0 else { return 0 }
        var acc = 0.0
        for c in hist where c > 0 {
            let p = Double(c) / n
            acc -= p * log2(p)
        }
        return acc
    }

    /// ★ THE ENERGY. E = Σ nᵢ·log₂(nᵢ/n̄), n̄ = N/K.
    static func energy(_ hist: [Int]) -> Double {
        let total = hist.reduce(0, +)
        guard total > 0 else { return 0 }
        let nb = Double(total) / Double(colors)
        var acc = 0.0
        for c in hist where c > 0 {
            acc += Double(c) * log2(Double(c) / nb)
        }
        return acc
    }

    /// Intensive form: bits per cell in [0, 8].
    static func energyPerCell(_ hist: [Int]) -> Double {
        let total = hist.reduce(0, +)
        guard total > 0 else { return 0 }
        return energy(hist) / Double(total)
    }

    /// log₂ n! by direct summation, ascending, matching the spec's own
    /// evaluation order so the two agree to floating-point noise.
    static func logFactBits(_ n: Int) -> Double {
        guard n > 1 else { return 0 }
        var acc = 0.0
        for k in 2...n { acc += log2(Double(k)) }
        return acc
    }

    /// log₂ of the multinomial N!/∏nᵢ!: how many frames wear this
    /// histogram.
    static func logMultiplicityBits(_ hist: [Int]) -> Double {
        logFactBits(hist.reduce(0, +)) - hist.reduce(0.0) { $0 + logFactBits($1) }
    }

    /// The ground multiplicity, 31922.0109 bits (TE7).
    static let groundMultiplicityBits =
        logMultiplicityBits([Int](repeating: balanced, count: colors))

    /// The EXACT Boltzmann twin: E_B = log₂W_bal − log₂W(n). Shares the
    /// zero, is bounded above by E (Stirling's correction is a debit).
    static func energyExact(_ hist: [Int]) -> Double {
        groundMultiplicityBits - logMultiplicityBits(hist)
    }

    // MARK: - The pair-tree chain rule (TE §3)

    /// Binary entropy from two counts, bits, 0 when either side empty.
    static func hBin(_ a: Int, _ b: Int) -> Double {
        guard a > 0, b > 0 else { return 0 }
        let n = Double(a + b)
        let p = Double(a) / n, q = Double(b) / n
        return -(p * log2(p) + q * log2(q))
    }

    /// Energy of each dyadic level, root (bit 7, the σ split) first.
    /// Eight levels, summing to `energy` exactly (TE4), and the first
    /// is N·(1 − h(φ)): the order parameter re-read as energy (TE5).
    static func levelEnergies(_ hist: [Int]) -> [Double] {
        var out: [Double] = []
        var nodes = [hist]
        while let first = nodes.first, first.count >= 2 {
            var level = 0.0
            var next: [[Int]] = []
            for nd in nodes {
                let half = nd.count / 2
                let l = Array(nd[0..<half]), r = Array(nd[half...])
                let sl = l.reduce(0, +), sr = r.reduce(0, +)
                level += Double(sl + sr) * (1 - hBin(sl, sr))
                if l.count >= 2 { next.append(l) }
                if r.count >= 2 { next.append(r) }
            }
            out.append(level)
            nodes = next
        }
        return out
    }

    /// The σ order parameter: the mass on the ground side.
    static func phi(_ hist: [Int]) -> Double {
        let total = hist.reduce(0, +)
        guard total > 0 else { return 0 }
        return Double(hist[128...].reduce(0, +)) / Double(total)
    }

    // MARK: - The spatial stratum (TE §4)

    /// The σ split: the involution's own halves, so the bond field
    /// reads figure against ground and nothing else.
    static func spin(_ i: UInt8) -> Bool { i >= 128 }

    /// Bonds whose two cells disagree, over the OPEN lattice (no
    /// wrap): 2·side·(side−1) of them.
    static func wallCount(_ frame: [UInt8]) -> Int {
        var w = 0
        for y in 0..<side {
            for x in 0..<side {
                let s = spin(frame[y * side + x])
                if x + 1 < side, s != spin(frame[y * side + x + 1]) { w += 1 }
                if y + 1 < side, s != spin(frame[(y + 1) * side + x]) { w += 1 }
            }
        }
        return w
    }

    /// B·(1 − h(w)). Maximal at w = 0 and at w = 1 alike (TE8).
    static func wallEnergy(_ frame: [UInt8]) -> Double {
        let w = wallCount(frame)
        return Double(bonds) * (1 - hBin(w, bonds - w))
    }

    // MARK: - The temporal stratum (TE §4b)

    /// The closed loop's bond count: one per voxel per tick, and the
    /// last tick's bond is the 63 → 0 one. nf·N, never (nf−1)·N.
    static func timeBonds(frames: Int) -> Int { frames * cells }

    /// Voxels whose ROLE differs from its own value one tick later,
    /// around the loop.
    static func wallCountTime(cube frames: [[UInt8]]) -> Int {
        guard let count = frames.first?.count, frames.count > 1 else { return 0 }
        var w = 0
        for t in 0..<frames.count {
            let a = frames[t], b = frames[(t + 1) % frames.count]
            for p in 0..<count where spin(a[p]) != spin(b[p]) { w += 1 }
        }
        return w
    }

    /// B_t·(1 − h(w_t)). Ceiling at BOTH ends: a cube that never moves
    /// and a cube whose roles invert every tick cost the same, exactly
    /// as TE8 in space. Only temporal noise is cheap, so this measures
    /// COHERENCE and not motion.
    static func timeEnergy(cube frames: [[UInt8]]) -> Double {
        guard frames.count > 1 else { return 0 }
        let b = timeBonds(frames: frames.count)
        let w = wallCountTime(cube: frames)
        return Double(b) * (1 - hBin(w, b - w))
    }

    // MARK: - The value (MerkleSearch §4, TE §4b)

    /// What the search ranks with, and what the surface shows. A
    /// VECTOR, never a number: MT7 measured each component blind to a
    /// different degeneracy, and TE13 measured the first two blind to
    /// frame order entirely.
    ///
    /// ★ THE AXES CARRY THEIR OWN DIRECTION, as data. Whether an axis
    /// is better low or better high is a property OF THE AXIS, and
    /// burying it in a comparison is how a third one gets added with
    /// the sign wrong. `senses` is the whole ordering law.
    enum Sense: Sendable { case low, high }

    /// One frame: two strata. There is no temporal bond inside a
    /// single frame, so a frame's value genuinely has two components
    /// rather than three with one zeroed.
    struct Value: Equatable, Sendable {
        /// E, the index stratum, bits. Low is diverse.
        let eHist: Double
        /// E_wall, the spatial stratum, bits. High is structured.
        let eWall: Double

        var coords: [Double] { [eHist, eWall] }
        static let senses: [Sense] = [.low, .high]
    }

    /// A whole loop: three strata, disjoint, all in bits (TE15).
    struct CubeValue: Equatable, Sendable {
        /// Pooled over all 64·4096 cells (TE9). Ceiling 2,097,152 b.
        let eHist: Double
        /// Summed over the frames' disjoint plane bonds. Ceiling 516,096 b.
        let eWall: Double
        /// The closed loop's own bonds. Ceiling 262,144 b.
        let eTime: Double

        var coords: [Double] { [eHist, eWall, eTime] }
        static let senses: [Sense] = [.low, .high, .high]

        /// The two BOND strata added. TE15 licenses exactly this and
        /// no more: same law, disjoint sets, same currency, same
        /// direction. E is not in it, because folding an axis that is
        /// better LOW into axes that are better HIGH needs a sign that
        /// no law supplies, and inventing one is how a Pareto front
        /// quietly becomes a weighted sum.
        var bondEnergy: Double { eWall + eTime }
    }

    /// One frame's value.
    static func value(frame: [UInt8]) -> Value {
        Value(eHist: energy(histogram(frame)), eWall: wallEnergy(frame))
    }

    /// The loop's value. One pass for the first two strata, one for
    /// the third.
    static func value(cube frames: [[UInt8]]) -> CubeValue {
        var pooled = [Int](repeating: 0, count: colors)
        var wall = 0.0
        for f in frames {
            let h = histogram(f)
            for i in 0..<colors { pooled[i] += h[i] }
            wall += wallEnergy(f)
        }
        return CubeValue(eHist: energy(pooled), eWall: wall,
                         eTime: timeEnergy(cube: frames))
    }

    // MARK: - The order (MT8)

    /// `a` dominates `b`: at least as good on every axis and strictly
    /// better on one, each axis read in its own direction. One law,
    /// any number of strata.
    static func dominates(_ a: [Double], _ b: [Double], senses: [Sense]) -> Bool {
        guard a.count == b.count, a.count == senses.count else { return false }
        var strict = false
        for i in a.indices {
            let better: Bool, worse: Bool
            switch senses[i] {
            case .low:  better = a[i] < b[i]; worse = a[i] > b[i]
            case .high: better = a[i] > b[i]; worse = a[i] < b[i]
            }
            if worse { return false }
            if better { strict = true }
        }
        return strict
    }

    static func dominates(_ a: Value, _ b: Value) -> Bool {
        dominates(a.coords, b.coords, senses: Value.senses)
    }

    static func dominates(_ a: CubeValue, _ b: CubeValue) -> Bool {
        dominates(a.coords, b.coords, senses: CubeValue.senses)
    }

    /// The Pareto front: the candidates nothing else beats. ★ MT8 is
    /// why this is the answer and not a weighted sum: grey is beaten
    /// by any picture at the same E_wall, and static is beaten by the
    /// balanced tiling at the same E, so the front structurally holds
    /// neither. Ties (mutually non-dominating equals) all survive,
    /// which is the honest reading of "nothing beats it".
    ///
    /// ★ A THIRD AXIS WIDENS THE FRONT, and that is the price of the
    /// ruling: more candidates are mutually incomparable, so the
    /// surface has more to show and the search prunes less.
    static func front<T>(_ candidates: [T],
                         coords: (T) -> [Double],
                         senses: [Sense]) -> [T] {
        let vs = candidates.map(coords)
        return candidates.indices
            .filter { i in
                !vs.indices.contains { j in dominates(vs[j], vs[i], senses: senses) }
            }
            .map { candidates[$0] }
    }

    static func front<T>(_ candidates: [T], value: (T) -> Value) -> [T] {
        front(candidates, coords: { value($0).coords }, senses: Value.senses)
    }

    static func front<T>(_ candidates: [T], cube: (T) -> CubeValue) -> [T] {
        front(candidates, coords: { cube($0).coords }, senses: CubeValue.senses)
    }
}
