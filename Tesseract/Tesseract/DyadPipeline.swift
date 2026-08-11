// DyadPipeline.swift
// Tesseract
//
// DYAD-256 export path: per-frame depth-masked OKLab statistics →
// EMA warm start → paired 256-entry table per frame → role-law
// index assignment under THE AERIAL MIRROR LAW (spec §6c v5,
// comp-halo default pending ruling R4): every pixel is γ-staged
// ŷ = c_F + γ(s)·(y − c_F) with γ(s) = 1/(2−s) — the chroma octave
// that pays for the temporal octave (σ(s)·γ(s) = σ_base) — then ONE
// search gives q and the posterior t routes coverage between q and
// 255−q. Face → primaries, background → mirrored binomial shells
// at compressed radius; no solid fill, no chroma seam (DY9–DY12).
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
// Runs beside the lattice pipeline, never instead of it: process()
// returns nil when a capture lacks raw RGB, and callers fall back
// to the canonical PerfectQuantizer/CentroidRefiner path.

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
    /// stage 0 solves the role law (one pooled mixture fit per
    /// capture — the crossover must not flicker across frames, the
    /// DepthSignal fixed-map rationale); stage 1 (CPU, exact) solves
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
    static func process(frames: [QuantizedFrame], bleed: Bool = true,
                        onFrameTable: ((Int, Data) -> Void)? = nil) -> Output? {
        guard !frames.isEmpty,
              frames.allSatisfy({ $0.rawRGB != nil }) else { return nil }

        // ── Stage 0: THE ROLE LAW ──
        let pooled = frames.flatMap { $0.depths.map { Double($0) } }
        let mixture = DepthMixture.fit(pooled)
        let twoPhase = DepthMixture.isTwoPhase(pooled, fit: mixture)

        // Coverage of the σ side per pixel. Single-phase ⇒ all-face
        // (R3). Bleed off ⇒ v1: MAP classes, no band.
        func coverage(_ d: Float) -> Double {
            guard twoPhase else { return 0 }
            let t = mixture.pull(Double(d))
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
        for frame in frames {
            let samples = frame.rawRGB!.map { srgb8(from: $0) }
            let ts = frame.depths.map { coverage($0) }
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
        var labPrimaries: [[OKLabColor]] = []
        var labs: [[OKLabColor]] = []
        var masks: [[Bool]] = []
        var fars: [[Bool]] = []
        var pulls: [[Float]] = []
        tables.reserveCapacity(frames.count)

        var smoothed: DyadPalette.Stats?
        for (f, raw) in rawStats.enumerated() {
            let warm = smoothed.map { DyadPalette.ema(alpha: alpha, raw, $0) } ?? raw
            smoothed = warm

            let table = DyadPalette.table(stats: warm)
            tables.append(DyadPalette.gifColorTable(table))
            onFrameTable?(f, tables[f])
            frameStats.append(warm)
            let prims = (0..<DyadPalette.primaryCount).map {
                DyadPalette.oklab(fromSRGB8: table[$0])
            }
            labPrimaries.append(prims)

            var frameLabs = [OKLabColor]()
            var frameMask = [Bool]()
            var frameFar = [Bool]()
            var framePull = [Float]()
            frameLabs.reserveCapacity(stagedAll[f].count)
            for (p, rgb) in stagedAll[f].enumerated() {
                let t = tsAll[f][p]
                frameMask.append(t < coverageFloor)   // solid-face side
                frameFar.append(false)                 // v5: no short-circuit
                framePull.append(Float(t))
                frameLabs.append(DyadPalette.oklab(fromSRGB8: rgb))  // ŷ
            }
            labs.append(frameLabs)
            masks.append(frameMask)
            fars.append(frameFar)
            pulls.append(framePull)
        }

        // ── Band post-pass: the pair dither (spec §6 v3), applied
        // IDENTICALLY to both engines' outputs. Stage 2 put every
        // band pixel on the σ side s; the Bayer threshold at the
        // pixel's grid position flips coverage 1 − t of each tile
        // back to the primary side 255 − s. Face and far pixels are
        // untouched; bleed off / single-phase has no band.
        func pairDither(_ engineOut: [[UInt8]]) -> [[UInt8]] {
            return engineOut.enumerated().map { f, indices in
                var out = indices
                let side = Int(Double(indices.count).squareRoot())
                for p in 0..<indices.count where !masks[f][p] && !fars[f][p] {
                    if bayer4[(p / side) % 4][(p % side) % 4] >= pulls[f][p] {
                        out[p] = 255 - out[p]
                    }
                }
                return out
            }
        }

        // ── Stage 2: assignment — ANE whole-capture, CPU otherwise ──
        if let ane = DyadANE.assign(labs: labs, primaries: labPrimaries,
                                    masks: masks, fars: fars) {
            return Output(indexFrames: pairDither(ane), tables: tables,
                          stats: frameStats, mixture: mixture,
                          twoPhase: twoPhase, alpha: alpha)
        }
        let cpu = (0..<frames.count).map { f in
            assignRoles(labs: labs[f], mask: masks[f], far: fars[f],
                        labPrimaries: labPrimaries[f])
        }
        return Output(indexFrames: pairDither(cpu), tables: tables,
                      stats: frameStats, mixture: mixture,
                      twoPhase: twoPhase, alpha: alpha)
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
