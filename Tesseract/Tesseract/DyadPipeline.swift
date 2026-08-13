// DyadPipeline.swift
// Tesseract
//
// DYAD-256 export path: per-frame depth-masked OKLab statistics →
// EMA warm start → paired 256-entry table per frame → role-law
// index assignment under THE AERIAL MIRROR LAW (spec §6c/§6d v7 —
// SAME-HUE GROUND + CHAOS BLUR, Daniel's ruling 2026-08-12): every
// pixel is γ-staged ŷ = c_F + γ(s)·(y − c_F) with γ(s) = 1/(2−s) —
// the chroma octave that pays for the temporal octave (σ(s)·γ(s) =
// σ_base) — then ONE search gives q and the posterior t routes
// coverage between q and the σ side, whose target is the rung-16
// BLOCK MEAN of ŷ: the background blurs as it becomes chaos.
// Face → primaries, background → mirrored binomial shells in the
// figure's OWN hue (the blue-haze negation is dead — DY14 v7);
// no solid fill, no chroma seam (DY9–DY16).
//
// THE ROLE LAW IS CONSTANT-FREE (Daniel's decree, 2026-08-10; spec
// temporal/DepthMixture.hs DM1–DM10). No faceThreshold, no bleedWidth,
// no bleedGamma: the pull coverage t is the posterior of a two-phase
// mixture solved from the capture's own pooled depth field, the
// solid/band boundaries are the Bayer matrix's own coverage extrema,
// the stats EMA gain is the derived Kalman gain (ruling R2), analyze
// weights are 1 − t (ruling R1), and a BIC-single-phase capture is
// all-face (ruling R3).
//
// process() returns nil when a capture lacks raw RGB; GIFMachine
// surfaces that nil honestly (no export) — there is no global-table
// fallback path anymore (2026-08-12 decree).

import Foundation

enum DyadPipeline {

    struct Output: Sendable {
        /// One index frame per input frame, role law applied.
        let indexFrames: [[UInt8]]
        /// One 768-byte Local Color Table per frame, involution law inside.
        let tables: [Data]
        /// The smoothed per-frame statistics the tables were solved
        /// from. Since DY8 (sign-canonical PCA), table = f(stats)
        /// single-valuedly: these 9 numbers per frame REBUILD the
        /// tables byte-exactly — the capture's generating state.
        let stats: [DyadPalette.Stats]
        /// The fitted role law (provenance: s*, τ, m* are OUTPUTS).
        let mixture: DepthMixture.Fit
        /// BIC verdict: false = single-phase capture, all-face (R3).
        let twoPhase: Bool
        /// Derived EMA gain (R2) actually used for the warm start.
        let alpha: Double
        /// Derived MS gain: the mixture local-level filter's α.
        let msGain: Double
        /// The per-frame ground-law parameters (phase-palette step 3,
        /// ruling R2): scene-fit on two-phase captures, the Wada
        /// dictionary prior on single-phase. Together with `stats`
        /// these regenerate every table byte (DYAD STATS v2).
        let groundMoments: [DyadPalette.GroundMoments]
        /// ★JEPA-H (JH4): true when the one model actually steadied
        /// the rung-16 ring for this capture (flag on AND the frame
        /// count divided into 16 equal slots). Provenance needs no
        /// new rebuild law — the traced per-frame numbers ARE the
        /// smoothed generating state.
        let jepaH: Bool
    }

    /// Standard Bayer 4×4 thresholds, normalized to the midpoints
    /// {0.5/16 … 15.5/16} (spec DyadPalette.hs §6 v3). The band
    /// dithers between the two sides of its pair: coverage t of each
    /// tile shows the σ side, the rest the primary side.
    static let bayer4: [[Float]] = {
        let m: [[Float]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
        return m.map { row in row.map { ($0 + 0.5) / 16 } }
    }()

    /// Role boundaries = the dither's own representable-coverage
    /// extrema (spec DM8) — structural, not tuned. Below the finest
    /// threshold no tile can show the σ side; above the coarsest,
    /// none can show the primary side.
    static let coverageFloor = Double(bayer4.flatMap { $0 }.min()!)   // 1/32
    static let coverageCeil = Double(bayer4.flatMap { $0 }.max()!)    // 31/32

    // MARK: - THE AERIAL MIRROR LAW (spec §6c v5, ported 2026-08-10)

    /// γ(s) = 1/(2−s) ∈ [½, 1]: the chroma octave. The invariant
    /// σ(s)·γ(s) = σ_base(K) — a pixel buys its temporal octave with
    /// a chroma octave (DY9, exact). The 2 is the shipped cadence
    /// octave; zero new constants.
    static func gammaAerial(_ s: Double) -> Double {
        1 / (2 - min(max(s, 0), 1))
    }

    /// ŷ = c_F + γ(s)·(y − c_F): compress chroma toward the centroid
    /// with distance — aerial perspective as law, applied to ALL
    /// roles (DY10: continuous in s, independent of t; at s = 1 the
    /// staging is the identity, so the face select is unchanged).
    static func stageAerial(_ lab: OKLabColor, s: Double,
                            about c: OKLabColor) -> OKLabColor {
        let g = gammaAerial(s)
        return OKLabColor(l: c.l + (lab.l - c.l) * g,
                          a: c.a + (lab.a - c.a) * g,
                          b: c.b + (lab.b - c.b) * g)
    }

    /// Build per-frame DYAD tables + index frames from a capture.
    /// Requires rawRGB on every frame (present in the record path);
    /// returns nil otherwise so callers keep the lattice output.
    ///
    /// Stages, split on the law boundary (ExportMethods XP1–XP2):
    /// stage 0 solves the role law (pooled fit for R3/provenance +
    /// per-frame fits filtered by the MS local-level law — drift
    /// followed, flicker frozen); stage 1 (CPU, exact) solves
    /// statistics → derived-α EMA → tables; stage 2 (assignment) runs
    /// on the ANE in one dispatch for full 64-frame captures, and
    /// falls back to the identical CPU search otherwise — near-tie
    /// flips are the only permitted difference.
    /// `bleed: false` = MAP classes only, no dither band: every
    /// background pixel is the hard σ-mirror of its own staged
    /// primary (no solid fill on either setting).
    ///
    /// `onFrameTable` (palette-creation visibility, 2026-08-10): called
    /// once per frame as its warm-started table is solved, BEFORE
    /// assignment — the UI shows the palette being created.
    /// `chaosLoop` (ruling R3, flag-gated, default OFF): after the
    /// band post-pass, fully-far blocks are rearranged by the ANE
    /// exchange loop (descent on F; face/band bytes untouched).
    static func process(frames: [QuantizedFrame], bleed: Bool = true,
                        chaosLoop: Bool = false,
                        onFrameTable: ((Int, Data) -> Void)? = nil) -> Output? {
        guard !frames.isEmpty,
              frames.allSatisfy({ $0.rawRGB != nil }) else { return nil }

        // ── Stage 0: THE ROLE LAW ──
        let pooled = frames.flatMap { $0.depths.map { Double($0) } }
        let mixture = DepthMixture.fit(pooled)
        let twoPhase = DepthMixture.isTwoPhase(pooled, fit: mixture)

        // ★MS — the mixture local-level law (spec MixtureStability.hs
        // MS1–MS7, ruled 2026-08-11 on the first 17 Pro export): the
        // pooled crossover froze while the per-frame depth signal
        // drifted, and the σ class died mid-loop (φ 0.34 → 0.00 at
        // frame ~45). Per-frame fits follow drift by construction;
        // the derived gain (R2's law on the mixture state) freezes
        // flicker. R3's capture-level two-phase decision and the
        // pooled provenance fit are unchanged.
        let (msFits, msGain) = DepthMixture.filtered(
            frames.map { DepthMixture.fit($0.depths.map { Double($0) }) })

        // Coverage of the σ side per pixel, from the FILTERED
        // per-frame state. Single-phase ⇒ all-face (R3). Bleed off
        // ⇒ v1: MAP classes, no band.
        func coverage(_ d: Float, _ f: Int) -> Double {
            guard twoPhase else { return 0 }
            let t = msFits[f].pull(Double(d))
            return bleed ? t : (t < 0.5 ? 0 : 1)
        }

        // ── Stage 1a: v5 AERIAL STAGING + stats-on-ŷ (DY12) ──
        // Per frame: (1) raw (1−t)-weighted stats give the staging
        // centroid c_F; (2) every pixel is staged ŷ = c_F + γ(s)·(y−c_F)
        // and round-tripped through sRGB8 (the DY12 construction, so
        // spec and Swift see the same bytes); (3) the palette stats are
        // solved on the STAGED samples with the R1 weights unchanged —
        // the shells whiten the distribution the assigner quantizes.
        var stagedAll: [[(UInt8, UInt8, UInt8)]] = []
        var tsAll: [[Double]] = []
        var rawStats: [DyadPalette.Stats] = []
        stagedAll.reserveCapacity(frames.count)
        for (fi, frame) in frames.enumerated() {
            let samples = frame.rawRGB!.map { srgb8(from: $0) }
            let ts = frame.depths.map { coverage($0, fi) }
            let weights = ts.map { 1 - $0 }
            let cF = DyadPalette.analyze(samples, weights: weights).centroid
            let staged = zip(samples, frame.depths).map { rgb, d in
                DyadPalette.srgb8(from: stageAerial(
                    DyadPalette.oklab(fromSRGB8: rgb),
                    s: Double(d), about: cF))
            }
            stagedAll.append(staged)
            tsAll.append(ts)
            rawStats.append(DyadPalette.analyze(staged, weights: weights))
        }

        // ── Stage 1b: derived EMA gain (R2) over the stats sequence ──
        let alpha = DepthMixture.localLevelAlpha(rawStats.map(statVector))

        // ── Stage 1b′: ★JEPA-H (JH4, flag-gated — the ONE model
        // line, decree 2026-08-12): pool the per-frame stats to the
        // rung-16 latent ring and steady it with the v7 head before
        // any table solves. Tables then hold at the 5 Hz cadence —
        // the resolution of depth (TL9), the cadence DyadPreview
        // already fits at. The bg-moments triple keeps its derived-
        // gain EMA below (the model's latent doesn't cover it).
        // nil (flag off or partial capture) ⇒ the EMA law stands.
        let jepaStats = CameraConfig.jepaH ? jepaSmoothed(rawStats) : nil

        // ── Stage 1c: warm-started tables + assignment inputs (v5).
        // Every pixel was already γ-staged in 1a; assignment runs ONE
        // search on ŷ for all roles (DY10: the pair {q, 255−q} is a
        // function of s only). The far side occupies the mirrored
        // binomial shells at compressed radius (DY11); `fars` stays
        // all-false: both engines run the shared search and the
        // mask=false σ-mirror, and the Bayer post-pass leaves far
        // pixels on the σ side because t > every threshold.
        var tables: [Data] = []
        var frameStats: [DyadPalette.Stats] = []
        var frameMoments: [DyadPalette.GroundMoments] = []
        var labPrimaries: [[OKLabColor]] = []
        var labs: [[OKLabColor]] = []
        var masks: [[Bool]] = []
        var fars: [[Bool]] = []
        var pulls: [[Float]] = []
        // ★PAIR TREE (P2): the per-frame 32-level nodes + their
        // canonical figure leaves — the prefix-law targets the
        // σ side quantizes against.
        var nodes16All: [[OKLabColor]] = []
        var canon16All: [[Int]] = []
        tables.reserveCapacity(frames.count)

        var smoothed: DyadPalette.Stats?
        // Ground-law state (ruling R2): the background's (mean L,
        // mean lnC, sd lnC) triple, EMA'd with the SAME derived gain
        // as the stats — one smoothing law for all generating state.
        // Frames without background mass carry the smoothed triple;
        // before any exists (or single-phase), the Wada prior rules.
        var smoothedBg: (meanL: Double, meanLnC: Double, sdLnC: Double)?
        for (f, raw) in rawStats.enumerated() {
            let emaWarm = smoothed.map { DyadPalette.ema(alpha: alpha, raw, $0) } ?? raw
            smoothed = emaWarm
            let warm = jepaStats?[f] ?? emaWarm

            let stagedLabs = stagedAll[f].map { DyadPalette.oklab(fromSRGB8: $0) }
            if twoPhase,
               let rb = DyadPalette.backgroundMoments(labs: stagedLabs,
                                                      weights: tsAll[f]) {
                smoothedBg = smoothedBg.map { prev in
                    ( alpha * rb.meanL + (1 - alpha) * prev.meanL
                    , alpha * rb.meanLnC + (1 - alpha) * prev.meanLnC
                    , alpha * rb.sdLnC + (1 - alpha) * prev.sdLnC )
                } ?? rb
            }

            // ★PAIR TREE (P1): figures = the analytic dyadic tree of
            // the warm-started stats (closed-form Gaussian splits —
            // PairTree.swift); rings remain only as the v1/v2
            // rebuild path. cL anchors the ground family at the
            // FIGURE CENTROID's lightness — for rings that was T[0];
            // the tree's T[0] is a corner leaf, so read the centroid
            // from the stats themselves (same number, honest source).
            let tree = CameraConfig.pairTree ? PairTree.solveFigures(stats: warm) : nil
            let prims8 = tree?.figures8 ?? DyadPalette.primaries(stats: warm)
            let prims = tree?.figures ?? prims8.map { DyadPalette.oklab(fromSRGB8: $0) }
            let cL = tree != nil ? warm.centroid.l : DyadPalette.centroidL(prims8)
            let gm = smoothedBg.map {
                DyadPalette.groundMoments(centroidL: cL, primsLab: prims,
                                          background: $0)
            } ?? DyadPalette.priorMoments(centroidL: cL)
            frameMoments.append(gm)

            let table = tree.map { PairTree.table(figures8: $0.figures8, moments: gm) }
                ?? DyadPalette.table(stats: warm, moments: gm)
            tables.append(DyadPalette.gifColorTable(table))
            nodes16All.append(tree?.nodes16 ?? [])
            canon16All.append(tree?.canonical16 ?? [])
            onFrameTable?(f, tables[f])
            frameStats.append(warm)
            labPrimaries.append(prims)

            var frameMask = [Bool]()
            var frameFar = [Bool]()
            var framePull = [Float]()
            frameMask.reserveCapacity(stagedAll[f].count)
            for p in 0..<stagedAll[f].count {
                let t = tsAll[f][p]
                frameMask.append(t < coverageFloor)   // solid-face side
                frameFar.append(false)                 // v5: no short-circuit
                framePull.append(Float(t))
            }
            labs.append(stagedLabs)                    // ŷ, converted once
            masks.append(frameMask)
            fars.append(frameFar)
            pulls.append(framePull)
        }

        // ── Band post-pass: the pair dither (spec §6c/§6d v7 — THE
        // CHAOS BLUR, Daniel's ruling 2026-08-12, superseding R4
        // faithful-hue: with the same-hue ground the σ half displays
        // its figure's own hue, so the comp re-route is deleted).
        // Stage 2 put every band pixel on the σ side; the Bayer
        // threshold flips coverage 1 − t back to the primary side.
        // Pixels that STAY on the σ side target the rung-16 block
        // mean of ŷ — SPACETIME since S4 (rate-ladder step, "be
        // bold" 2026-08-12): 4×4 in space × 4 frames in time, the
        // full 2×2×2 atom composed twice; the background holds
        // still across 4-frame groups and the coder's K̂ pays less.
        // ★PAIR TREE P2 (prefix law): those targets quantize at the
        // 32-LEVEL — nearest of the 16 depth-4 node means, emitted
        // as the node's canonical leaf's partner. The background's
        // palette rate drops 8:1 exactly where its spatial rate
        // does. Assignment/ANE stay untouched — blur and prefix
        // live entirely in this post-pass.
        func pairDither(_ engineOut: [[UInt8]]) -> [[UInt8]] {
            let frameCount = engineOut.count
            guard let first = engineOut.first else { return engineOut }
            let side = Int(Double(first.count).squareRoot())
            let rung = 4
            let bSide = side / rung
            let blockCount = bSide * bSide
            // Per-frame spatial rung-16 pools of the staged field.
            var spatial = [[OKLabColor]]()
            spatial.reserveCapacity(frameCount)
            for f in 0..<frameCount {
                var pooled = [OKLabColor](
                    repeating: OKLabColor(l: 0, a: 0, b: 0), count: blockCount)
                for by in 0..<bSide {
                    for bx in 0..<bSide {
                        var sl = 0.0, sa = 0.0, sb = 0.0
                        for dy in 0..<rung {
                            for dx in 0..<rung {
                                let lab = labs[f][(by * rung + dy) * side + bx * rung + dx]
                                sl += lab.l; sa += lab.a; sb += lab.b
                            }
                        }
                        let n = Double(rung * rung)
                        pooled[by * bSide + bx] = OKLabColor(l: sl / n, a: sa / n, b: sb / n)
                    }
                }
                spatial.append(pooled)
            }
            // Temporal pooling over 4-frame groups (partial tail
            // groups are lawful degenerates; 64 divides exactly).
            let groupCount = (frameCount + 3) / 4
            var spacetime = [[OKLabColor]]()
            spacetime.reserveCapacity(groupCount)
            for g in 0..<groupCount {
                let lo = 4 * g, hi = min(4 * g + 4, frameCount)
                var pooled = [OKLabColor](
                    repeating: OKLabColor(l: 0, a: 0, b: 0), count: blockCount)
                for b in 0..<blockCount {
                    var sl = 0.0, sa = 0.0, sb = 0.0
                    for f in lo..<hi {
                        sl += spatial[f][b].l; sa += spatial[f][b].a; sb += spatial[f][b].b
                    }
                    let n = Double(hi - lo)
                    pooled[b] = OKLabColor(l: sl / n, a: sa / n, b: sb / n)
                }
                spacetime.append(pooled)
            }
            return engineOut.enumerated().map { f, indices in
                var out = indices
                let prims = labPrimaries[f]
                let nodes = nodes16All[f]
                let canon = canon16All[f]
                let pooled = spacetime[f / 4]
                for p in 0..<indices.count where !masks[f][p] && !fars[f][p] {
                    if bayer4[(p / side) % 4][(p % side) % 4] >= pulls[f][p] {
                        out[p] = 255 - out[p]
                    } else {
                        let target = pooled[((p / side) / rung) * bSide + (p % side) / rung]
                        if !nodes.isEmpty {
                            // prefix law: 32-level quantization
                            var best = 0
                            var bestD = Double.infinity
                            for c in 0..<nodes.count {
                                let d = DyadPalette.dLab2(nodes[c], target)
                                if d < bestD { bestD = d; best = c }
                            }
                            out[p] = UInt8(255 - canon[best])
                        } else {
                            var best = 0
                            var bestD = Double.infinity
                            for j in 0..<prims.count {
                                let d = DyadPalette.dLab2(prims[j], target)
                                if d < bestD { bestD = d; best = j }
                            }
                            out[p] = UInt8(255 - best)
                        }
                    }
                }
                return out
            }
        }

        // ── Chaos post-pass (R3, flag-gated): fully-far blocks only,
        // descent on F; the shipped v4 far law is the flag-off path.
        func chaosRefine(_ dithered: [[UInt8]]) -> [[UInt8]] {
            guard chaosLoop, twoPhase else { return dithered }
            return ANELoop.refineFarBlocks(
                indexFrames: dithered, labs: labs, pulls: pulls,
                tables: tables, coverageCeil: coverageCeil)
        }

        // ── Stage 2: assignment — ANE whole-capture, CPU otherwise ──
        if let ane = DyadANE.assign(labs: labs, primaries: labPrimaries,
                                    masks: masks, fars: fars) {
            return Output(indexFrames: chaosRefine(pairDither(ane)), tables: tables,
                          stats: frameStats, mixture: mixture,
                          twoPhase: twoPhase, alpha: alpha,
                          msGain: msGain, groundMoments: frameMoments,
                          jepaH: jepaStats != nil)
        }
        let cpu = (0..<frames.count).map { f in
            assignRoles(labs: labs[f], mask: masks[f], far: fars[f],
                        labPrimaries: labPrimaries[f])
        }
        return Output(indexFrames: chaosRefine(pairDither(cpu)), tables: tables,
                      stats: frameStats, mixture: mixture,
                      twoPhase: twoPhase, alpha: alpha,
                      msGain: msGain, groundMoments: frameMoments,
                      jepaH: jepaStats != nil)
    }

    /// ★JEPA-H (JH4): the deployed placement law. Pool the 64
    /// per-frame stats to the 16-slot ring (slot = 4-frame mean —
    /// the rung-16 cadence, the resolution of depth), steady the
    /// 6-dim latent (centroid l,a,b + LOG-diagonals — exactly the
    /// corpus law the model trained on), rebuild per-slot Stats.
    /// The model smooths LOCATION and SCALE; SHAPE — the correlation
    /// coefficients the corpus never modeled — rides the slot pool
    /// and recombines as c_ij = r_ij·√(c_ii·c_jj), positive-
    /// semidefinite by construction, no new constants. Frames
    /// within a slot share one generating state, so tables hold at
    /// 5 Hz exactly like the preview. Requires the frame count to
    /// divide into 16 equal slots; otherwise nil.
    static func jepaSmoothed(_ raw: [DyadPalette.Stats]) -> [DyadPalette.Stats]? {
        let slots = JepaHHead.slots
        guard raw.count >= slots, raw.count % slots == 0 else { return nil }
        let group = raw.count / slots
        let eps = 1e-12                    // whitening-law epsilon
        var pooled: [[Double]] = []        // [slot][9], statVector order
        pooled.reserveCapacity(slots)
        for s in 0..<slots {
            var acc = [Double](repeating: 0, count: 9)
            for f in (s * group)..<((s + 1) * group) {
                let v = statVector(raw[f])
                for i in 0..<9 { acc[i] += v[i] }
            }
            pooled.append(acc.map { $0 / Double(group) })
        }
        let ring = pooled.map { v in
            [v[0], v[1], v[2],
             log(max(v[3], eps)), log(max(v[6], eps)), log(max(v[8], eps))]
        }
        let shat = JepaHHead.smoothRing(ring)
        var out: [DyadPalette.Stats] = []
        out.reserveCapacity(raw.count)
        for s in 0..<slots {
            let v = pooled[s], sh = shat[s]
            let c00 = exp(sh[3]), c11 = exp(sh[4]), c22 = exp(sh[5])
            func corr(_ cij: Double, _ cii: Double, _ cjj: Double) -> Double {
                let den = (max(cii, eps) * max(cjj, eps)).squareRoot()
                return min(1, max(-1, cij / den))
            }
            let c01 = corr(v[4], v[3], v[6]) * (c00 * c11).squareRoot()
            let c02 = corr(v[5], v[3], v[8]) * (c00 * c22).squareRoot()
            let c12 = corr(v[7], v[6], v[8]) * (c11 * c22).squareRoot()
            let st = DyadPalette.makeStats(
                centroid: OKLabColor(l: sh[0], a: sh[1], b: sh[2]),
                covariance: [[c00, c01, c02], [c01, c11, c12], [c02, c12, c22]])
            for _ in 0..<group { out.append(st) }
        }
        return out
    }

    /// Exact CPU assignment on staged labs: face → nearest primary
    /// (0..127); band background → σ-mirror 255 − nearest; far
    /// background → exactly 255. The reference the ANE path is
    /// parity-tested against. The band pair dither is NOT here:
    /// process() applies it as a post-pass on both engines.
    static func assignRoles(
        labs: [OKLabColor],
        mask: [Bool],
        far: [Bool],
        labPrimaries: [OKLabColor]
    ) -> [UInt8] {
        labs.enumerated().map { p, lc in
            if !mask[p] && far[p] { return UInt8(DyadPalette.backgroundIndex) }
            var best = 0
            var bestD = Double.infinity
            for j in 0..<labPrimaries.count {
                let d = DyadPalette.dLab2(labPrimaries[j], lc)
                if d < bestD { bestD = d; best = j }
            }
            return mask[p] ? UInt8(best) : UInt8(255 - best)
        }
    }

    /// The 9 generating numbers of a Stats, in a fixed order, for the
    /// α derivation (centroid + upper-triangle covariance).
    static func statVector(_ s: DyadPalette.Stats) -> [Double] {
        [s.centroid.l, s.centroid.a, s.centroid.b,
         s.covariance[0][0], s.covariance[0][1], s.covariance[0][2],
         s.covariance[1][1], s.covariance[1][2], s.covariance[2][2]]
    }

    static func srgb8(from f: (Float, Float, Float)) -> (UInt8, UInt8, UInt8) {
        func to8(_ c: Float) -> UInt8 {
            UInt8(min(255, max(0, (Double(c) * 255).rounded(.toNearestOrEven))))
        }
        return (to8(f.0), to8(f.1), to8(f.2))
    }
}
