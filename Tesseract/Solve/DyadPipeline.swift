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
// BACKGROUND's own hue (the blue-haze negation is dead — DY14 v7 —
// and so, since 2026-08-13, is v7's forced same-hue: the ground
// family's fourth coordinate Δh is fitted from the background's own
// chroma-weighted resultant, spec/quantization/GroundHue.hs GH1–GH11.
// Δh = identity on every degenerate case ⇒ v7's bytes exactly);
// no solid fill, no chroma seam (DY9–DY16).
//
// ★ EM12/EM13 — THE PREVIEW IS THE GIF (Daniel's decree, spec/ui/
// EditMachine.hs, 2026-08-13): weave = watch + keep. WATCHING and
// WEAVING run the SAME encoder and differ only in RETENTION, so a
// second preview implementation cannot exist — DyadPreview.swift is
// DELETED and `Live` (below) is a DRIVER, not a second law: it reads
// the live feed at the coarse rung, hands that cube to this file's
// own `process`, and assigns the fine frame through this file's own
// `stagedField` / `assignRoles` / `chaosPool` / `pairDitherFrame`.
// The ladder is the only thing parameterised: the solve runs at
// rung 16 / 5 Hz (TL8/TL9 — the resolution of depth), the assignment
// at rung 64 / 20 Hz, exactly the cadence split the export already
// obeys. Nothing else about the live path differs from the export.
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
// surfaces that nil honestly (no export). There is no global-table
// path anymore (2026-08-12 decree).

import Foundation
import simd

enum DyadPipeline {

    /// What the caller KEEPS — not which encoder runs. Stages 0–1
    /// solve the generating state; stage 2 turns it into the artifact.
    ///
    /// EM12 says weave = watch + keep, so the two dispositions must
    /// share every law. They do: `.generatingState` stops at the stage
    /// boundary and runs stages 0–1 byte for byte, which
    /// `testGeneratingStateMatchesArtifactSolves` gates.
    ///
    /// `Live` wants `.generatingState` because the assignment it shows
    /// is taken at the FINE rung by `assign`, 20 Hz, from the live
    /// frame — never at the coarse rung the solve is read at. Running
    /// stage 2 in the solve produced coarse-rung indices that were
    /// discarded unexamined, on the capture callback's budget.
    enum Disposition: Sendable, CaseIterable {
        case artifact          // the export: index frames + tables
        case generatingState   // the live solve: tables + solves only
    }

    struct Output: Sendable {
        /// One index frame per input frame, role law applied. EMPTY
        /// under `.generatingState` — stage 2 never ran.
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
        /// these regenerate every table byte (DYAD STATS + the
        /// DYAD GROUNDHUE section, which carries the fourth
        /// coordinate — absent ⇒ identity ⇒ the v7 path).
        let groundMoments: [DyadPalette.GroundMoments]
        /// ★JEPA-H (JH4): true when the one model actually steadied
        /// the rung-16 ring for this capture (flag on AND the frame
        /// count divided into 16 equal slots). Provenance needs no
        /// new rebuild law — the traced per-frame numbers ARE the
        /// smoothed generating state.
        let jepaH: Bool
        /// ★EM13: the per-frame generating state the assignment ran
        /// on. WEAVING keeps the index frames; WATCHING keeps only
        /// this — the same solve, dropped instead of written.
        let solves: [FrameSolve]
    }

    /// Everything one frame's assignment needs, and nothing else:
    /// the solved figures, the 32-level prefix nodes, the table the
    /// surface draws with, and the role law that routes coverage.
    /// Produced by the solve (stages 0–1c) at whatever rung the
    /// caller read; consumed by the assignment at the fine rung.
    struct FrameSolve: Sendable {
        /// The 128 figure primaries, OKLab (tree leaves since P1).
        let primaries: [OKLabColor]
        /// ★PAIR TREE P2: the 16 depth-4 node means (prefix law), and
        /// each node's canonical FIGURE leaf. Empty when the tree is off.
        let nodes16: [OKLabColor]
        let canonical16: [Int]
        /// The 256 entries, before `gifColorTable` packs them.
        let table: [(UInt8, UInt8, UInt8)]
        let moments: DyadPalette.GroundMoments
        /// c_F — the γ-staging centroid this frame's pixels staged about.
        let centroid: OKLabColor
        /// The role law as this frame saw it (MS-filtered per frame).
        let mixture: DepthMixture.Fit
        let twoPhase: Bool
        /// The BLEED setting the coverage was routed under.
        let bleed: Bool
    }

    /// Everything the aerialPreview Metal kernel needs for one 20 Hz
    /// assignment — the GPU twin of `assignRoles` + `pairDitherFrame`.
    struct MetalState {
        var primaries: [SIMD4<Float>]   // 128 OKLab primaries (xyz)
        /// ★PAIR TREE P2: the 16 depth-4 node means (xyz) with the
        /// node's canonical FIGURE leaf index in w — the σ side's
        /// 32-level targets. Empty when the tree is off.
        var nodes: [SIMD4<Float>]
        var centroid: SIMD3<Float>      // the γ-staging centroid c_F
        var sStar: Float                // mixture crossover
        var tau: Float                  // mixture temperature
        var twoPhase: Bool
        /// The BLEED setting the coverage rides under. The kernel must
        /// collapse t to hard MAP classes when this is off, exactly as
        /// `coverage(_:fit:twoPhase:bleed:)` does — without it the GPU
        /// surface answers a different setting than the CPU and the
        /// export, which is the one thing EM13 forbids.
        var bleed: Bool
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

    /// The σ-side chaos rung: the block a fine cell pools into for the
    /// blur target. κ = 2×2×2 applied twice (OV10 / TriScaleLadder §8)
    /// — the ladder's own step from the fine rung to the coarse one,
    /// never a second number.
    static var chaosRung: Int { Rung.fine.side / Rung.coarse.side }

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

    /// The staged field of ONE frame (the DY12 construction): every
    /// pixel γ-staged about c_F and round-tripped through sRGB8, so
    /// spec and Swift see the same bytes. Export and preview call
    /// this — there is no second staging.
    static func stagedField(samples: [(UInt8, UInt8, UInt8)], depths: [Float],
                            about cF: OKLabColor) -> [(UInt8, UInt8, UInt8)] {
        zip(samples, depths).map { rgb, d in
            DyadPalette.srgb8(from: stageAerial(
                DyadPalette.oklab(fromSRGB8: rgb),
                s: Double(d), about: cF))
        }
    }

    /// ★ THE SAME STAGING, WITHOUT THE RETURN TRIP, and the two are
    /// NOT interchangeable. `stagedField` above exists for TABLE
    /// CONSTRUCTION, where DY12's own fixture round-trips
    /// (`oklabToSrgb8 . stageAerial . srgb8ToOklab`) because `analyze`
    /// and `buildDyad` consume RGB8 and the trace must rebuild the
    /// table from bytes. ASSIGNMENT is a different law:
    /// `aerialPrimary` is
    ///   nearestPrimaryLab tbl (stageAerial ... (srgb8ToOklab c))
    /// with no return trip, so the search happens in Lab.
    ///
    /// Until 2026-08-16 both call sites fed the argmin the
    /// round-tripped bytes, which is neither the spec nor the GPU
    /// twin: Quantize.metal round-trips its INPUT and then stages in
    /// float, so THE KERNEL MATCHED THE SPEC AND THIS FILE DID NOT.
    /// Sixteen DyadPalette axioms were green because not one of them
    /// said which staged value the argmin reads. DY17 now does, and
    /// its second conjunct proves the two searches are genuinely
    /// different functions rather than a cosmetic difference.
    static func stagedFieldLab(samples: [(UInt8, UInt8, UInt8)], depths: [Float],
                               about cF: OKLabColor) -> [OKLabColor] {
        zip(samples, depths).map { rgb, d in
            stageAerial(DyadPalette.oklab(fromSRGB8: rgb),
                        s: Double(d), about: cF)
        }
    }

    /// ★ BOTH STAGED VALUES FROM ONE PASS, and it is strictly cheaper
    /// than computing either pair the obvious way.
    ///
    /// The table path wants BYTES (DY12) and the argmin wants the
    /// CONTINUOUS Lab (DY17), and the bytes are just the Lab rounded.
    /// Computing them separately converts sRGB8 to OKLab TWICE per
    /// pixel, and that conversion is six transcendentals: three
    /// `pow(_, 2.4)` in srgbToLinear and three `cbrt`.
    ///
    /// Costs, per pixel, on the export path (262144 pixels per
    /// capture) and the live path (4096 pixels at 20 Hz):
    ///   before DY17   2 x oklab + 1 x srgb8   (staged, then re-read
    ///                                          the bytes back to Lab)
    ///   naive DY17    2 x oklab + 1 x srgb8   (staged twice, once for
    ///                                          each convention)
    ///   this          1 x oklab + 1 x srgb8
    /// So the correctness fix pays for itself: about a third fewer
    /// transcendental calls than the code it replaced, on a path that
    /// runs 20 times a second.
    static func stagedPair(samples: [(UInt8, UInt8, UInt8)], depths: [Float],
                           about cF: OKLabColor)
        -> (lab: [OKLabColor], bytes: [(UInt8, UInt8, UInt8)]) {
        var lab = [OKLabColor]()
        var bytes = [(UInt8, UInt8, UInt8)]()
        lab.reserveCapacity(samples.count)
        bytes.reserveCapacity(samples.count)
        for (rgb, d) in zip(samples, depths) {
            let y = stageAerial(DyadPalette.oklab(fromSRGB8: rgb),
                                s: Double(d), about: cF)
            lab.append(y)
            bytes.append(DyadPalette.srgb8(from: y))
        }
        return (lab, bytes)
    }

    /// The σ coverage of one pixel — the ONE reading of the role law.
    /// Single-phase ⇒ all-face (R3); `bleed: false` ⇒ MAP classes
    /// only, no dither band (role law v1, a lawful subset).
    /// ★ C5: a DEGENERATE fit (coincident components — a constant
    /// depth frame) is the single-phase case by construction, so it
    /// takes the same `return 0` rather than propagating NaN. The
    /// totality is stated here as well as in `pull` because this is
    /// the only reading of the role law: nothing downstream inspects
    /// the fit again.
    static func coverage(_ d: Float, fit: DepthMixture.Fit,
                         twoPhase: Bool, bleed: Bool) -> Double {
        guard twoPhase, !fit.isDegenerate else { return 0 }
        let t = fit.pull(Double(d))
        return bleed ? t : (t < 0.5 ? 0 : 1)
    }

    /// Build per-frame DYAD tables + index frames from a capture.
    /// Requires rawRGB on every frame (present in the record path);
    /// returns nil otherwise so callers keep the lattice output.
    static func process(frames: [QuantizedFrame], bleed: Bool = true,
                        chaosLoop: Bool = false,
                        onFrameTable: ((Int, Data) -> Void)? = nil) -> Output? {
        guard !frames.isEmpty,
              frames.allSatisfy({ $0.rawRGB != nil }) else { return nil }
        return process(rgb: frames.map { $0.rawRGB! },
                       depths: frames.map { $0.depths },
                       bleed: bleed, chaosLoop: chaosLoop,
                       onFrameTable: onFrameTable)
    }

    /// The encoder itself, over a cube of raw frames at ANY rung —
    /// the export hands it the fine capture, `Live` hands it the
    /// coarse read of the live feed (EM12: one encoder, two
    /// dispositions).
    ///
    /// Stages, split on the law boundary (ExportMethods XP1–XP2):
    /// stage 0 solves the role law (pooled fit for R3/provenance +
    /// per-frame fits filtered by the MS local-level law — drift
    /// followed, flicker frozen); stage 1 (CPU, exact) solves
    /// statistics → derived-α EMA → tables; stage 2 (assignment) runs
    /// on the ANE in one dispatch for full 64-frame captures, and
    /// runs the identical CPU search (its TWIN) otherwise. Near-tie
    /// flips are the only permitted difference.
    /// `bleed: false` = MAP classes only, no dither band: every
    /// background pixel is the hard σ-mirror of its own staged
    /// primary (no solid fill on either setting).
    ///
    /// `withinVariance` (DM11, the τ-LIFT): the mean within-cell depth
    /// variance that pooling to a coarser rung removed. nil at the
    /// fine rung — there the field IS the read, and the fit is
    /// untouched. A coarse read MUST pass it: the naive pooled τ
    /// collapses and the band hardens (spec §4b, law of total
    /// variance — an identity, not a tunable).
    ///
    /// `onFrameTable` (palette-creation visibility, 2026-08-10): called
    /// once per frame as its warm-started table is solved, BEFORE
    /// assignment — the UI shows the palette being created.
    /// `chaosLoop` (ruling R3, flag-gated, default OFF): after the
    /// band post-pass, fully-far blocks are rearranged by the ANE
    /// exchange loop (descent on F; face/band bytes untouched).
    static func process(rgb: [[(Float, Float, Float)]], depths: [[Float]],
                        withinVariance: Double? = nil,
                        bleed: Bool = true, chaosLoop: Bool = false,
                        keeping disposition: Disposition = .artifact,
                        figureDepth: Int = PairTree.fullDepth,
                        onFrameTable: ((Int, Data) -> Void)? = nil) -> Output? {
        guard !rgb.isEmpty, rgb.count == depths.count else { return nil }
        let frameCount = rgb.count

        // ── Stage 0: THE ROLE LAW ──
        let pooled = depths.flatMap { $0.map { Double($0) } }
        let base = DepthMixture.fit(pooled)
        let twoPhase = DepthMixture.isTwoPhase(pooled, fit: base)
        // The BIC verdict is read off the fit of the data actually in
        // hand; only the PULL is lifted (DM11), so a coarse read
        // decides two-phase exactly as the preview always has.
        let mixture = withinVariance.map { DepthMixture.lift(base, byWithinVariance: $0) } ?? base

        // ★MS — the mixture local-level law (spec MixtureStability.hs
        // MS1–MS7, ruled 2026-08-11 on the first 17 Pro export): the
        // pooled crossover froze while the per-frame depth signal
        // drifted, and the σ class died mid-loop (φ 0.34 → 0.00 at
        // frame ~45). Per-frame fits follow drift by construction;
        // the derived gain (R2's law on the mixture state) freezes
        // flicker. R3's capture-level two-phase decision and the
        // pooled provenance fit are unchanged.
        let (msFits, msGain) = DepthMixture.filtered(depths.map { frame in
            let f = DepthMixture.fit(frame.map { Double($0) })
            return withinVariance.map { DepthMixture.lift(f, byWithinVariance: $0) } ?? f
        })

        // ── Stage 1a: v5 AERIAL STAGING + stats-on-ŷ (DY12) ──
        // Per frame: (1) raw (1−t)-weighted stats give the staging
        // centroid c_F; (2) every pixel is staged ŷ = c_F + γ(s)·(y−c_F)
        // and round-tripped through sRGB8 (the DY12 construction, so
        // spec and Swift see the same bytes); (3) the palette stats are
        // solved on the STAGED samples with the R1 weights unchanged —
        // the shells whiten the distribution the assigner quantizes.
        var stagedAll: [[(UInt8, UInt8, UInt8)]] = []
        var stagedLabsAll: [[OKLabColor]] = []
        var tsAll: [[Double]] = []
        var rawStats: [DyadPalette.Stats] = []
        var centroids: [OKLabColor] = []
        // ★ GH4's hue resultant is read on the UNSTAGED field. Kept
        // separately because every other moment here reads the staged
        // one, and the difference is not cosmetic — see below.
        stagedAll.reserveCapacity(frameCount)
        stagedLabsAll.reserveCapacity(frameCount)
        for fi in 0..<frameCount {
            let samples = rgb[fi].map { srgb8(from: $0) }
            let ts = depths[fi].map {
                coverage($0, fit: msFits[fi], twoPhase: twoPhase, bleed: bleed)
            }
            let weights = ts.map { 1 - $0 }
            let cF = DyadPalette.analyze(samples, weights: weights).centroid
            // ONE staging pass yields both conventions: bytes for the
            // table (DY12), continuous Lab for the argmin (DY17).
            let pair = stagedPair(samples: samples, depths: depths[fi], about: cF)
            let staged = pair.bytes
            stagedAll.append(staged)
            stagedLabsAll.append(pair.lab)
            tsAll.append(ts)
            centroids.append(cF)
            rawStats.append(DyadPalette.analyze(staged, weights: weights))
        }

        // ── Stage 1b: derived EMA gain (R2) over the stats sequence ──
        let alpha = DepthMixture.localLevelAlpha(rawStats.map(statVector))

        // Staged labs were built in the loop above, CONTINUOUS per
        // DY17. They used to be recovered here as
        //     stagedAll.map { $0.map { oklab(fromSRGB8: $0) } }
        // which fed the argmin a value the spec never searches.
        // The background's four moments — three scalars plus ★ GH4's
        // hue resultant, weighted by the σ coverage t (the background
        // class's own mass).
        //
        // ★ THE HUE RESULTANT READS THE UNSTAGED FIELD. Every other
        // moment reads the staged one; this one cannot, and the reason
        // is arithmetic, not taste. Staging is
        //     ŷ_ab = c_F,ab + γ(s)·(y_ab − c_F,ab),  γ(0) = ½
        // so a staged background resultant carries an ADDITIVE BIAS
        //     B·c_F,ab,   B = Σ t(1−γ) ≈ T/2
        // pointing exactly at the FIGURE's hue. Δh is then fitted
        // against the figure resultant, which points the same way, and
        // the two nearly cancel. The failure is not a shrink — it is
        // not monotone: the fitted Δh peaks near 90° of true
        // separation and returns to ZERO at 180°, i.e. a blue wall
        // behind a warm face — the very case this law exists for —
        // reproduces v7's bytes exactly. Measured on a synthetic
        // face-disc/wall frame: true 180° ⇒ fitted 0.4° staged,
        // 179.0° unstaged.
        //
        // The earlier comment here claimed the staged read was "a
        // conservative reading of the scene's own separation, never an
        // invented one". That was undefended and, in the case that
        // matters, false. GH14 argues the contraction away rather than
        // bounding it; it needs reopening now that Δh depends on it.
        let bgPerFrame: [DyadPalette.BackgroundMoments?] =
            (0..<frameCount).map { f in
                // ★ PEAK MEMORY, 2026-08-16. This used to read
                // `unstagedLabsAll[f]`, a retained [[OKLabColor]] of
                // 64 x 4096 x 24 B = 6291456 B kept alive for the whole
                // export closure, for ONE reader that is SKIPPED
                // ENTIRELY on single-phase captures. The labs are the
                // same sRGB8 bytes the staging starts from (DY12), just
                // not contracted about c_F, so they derive from `rgb`
                // which is in scope anyway.
                //
                // Cost: one OKLab pass over the cube, and only when the
                // mixture voted two-phase. Benefit: 6.29 MB off peak,
                // against a RETAINED cube of 1.8 MB, and zero work on
                // the single-phase path where it was pure waste.
                twoPhase
                    ? DyadPalette.backgroundMoments(
                        labs: rgb[f].map {
                            DyadPalette.oklab(fromSRGB8: srgb8(from: $0))
                        },
                        weights: tsAll[f])
                    : nil
            }

        // ── Stage 1b′: ★JEPA-H (JH4, flag-gated — the ONE model
        // line, decree 2026-08-12): pool the per-frame generating
        // state to the rung-16 latent ring and steady it with the
        // v7 head before any table solves. ONE ring for ALL of it —
        // the 6 stats dims AND the background's four moments, hue
        // resultant included (ruling R2:
        // one smoothing law for all generating state; the first
        // device capture, 11EB44F0, proved the split-cadence
        // alternative wrong — figure half held at 5 Hz while the
        // ground half churned at 20 Hz, +30% ground churn). Tables
        // then hold WHOLLY at the 5 Hz cadence — the resolution of
        // depth (TL9), the cadence the live read is taken at.
        // nil (flag off or partial capture) ⇒ the EMA law stands.
        let jepa = CameraConfig.jepaH ? jepaSmoothed(rawStats, bg: bgPerFrame) : nil

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
        var solves: [FrameSolve] = []
        var labs: [[OKLabColor]] = []
        var masks: [[Bool]] = []
        var fars: [[Bool]] = []
        var pulls: [[Float]] = []
        tables.reserveCapacity(frameCount)

        var smoothed: DyadPalette.Stats?
        // Ground-law state (ruling R2): the background's (mean L,
        // mean lnC, sd lnC) triple AND its hue resultant (★ the
        // fourth coordinate), EMA'd with the SAME derived gain as
        // the stats — one smoothing law for all generating state.
        // Frames without background mass carry the smoothed state;
        // before any exists (or single-phase), the Wada prior rules
        // — and the prior is the identity rotation, so a scene with
        // no background evidence emits exactly today's bytes (GH7).
        var smoothedBg: DyadPalette.BackgroundMoments?
        for (f, raw) in rawStats.enumerated() {
            let emaWarm = smoothed.map { DyadPalette.ema(alpha: alpha, raw, $0) } ?? raw
            smoothed = emaWarm
            let warm = jepa?.stats[f] ?? emaWarm

            let stagedLabs = stagedLabsAll[f]
            if let rb = bgPerFrame[f] {
                // ★ GH13: the hue rides this EMA as a VECTOR and is
                // renormalised where it is read — never as an angle.
                // An angle EMA across the 0/360 seam returns the
                // OPPOSITE hue (the GH5 failure, at 5 Hz).
                smoothedBg = smoothedBg.map { prev in
                    DyadPalette.BackgroundMoments(
                        meanL: alpha * rb.meanL + (1 - alpha) * prev.meanL,
                        meanLnC: alpha * rb.meanLnC + (1 - alpha) * prev.meanLnC,
                        sdLnC: alpha * rb.sdLnC + (1 - alpha) * prev.sdLnC,
                        hueA: alpha * rb.hueA + (1 - alpha) * prev.hueA,
                        hueB: alpha * rb.hueB + (1 - alpha) * prev.hueB)
                } ?? rb
            }
            // ★JEPA-H: when the ring engaged, the frame's ground law
            // reads the SAME steadied slot state as its figures.
            let bgForFrame = jepa != nil ? jepa!.bg[f] : smoothedBg

            let solve = solveFrame(warm: warm, background: bgForFrame,
                                   centroid: centroids[f], mixture: msFits[f],
                                   twoPhase: twoPhase, bleed: bleed,
                                   figureDepth: figureDepth)
            tables.append(DyadPalette.gifColorTable(solve.table))
            onFrameTable?(f, tables[f])
            frameStats.append(warm)
            solves.append(solve)

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
            guard let first = engineOut.first else { return engineOut }
            let side = Int(Double(first.count).squareRoot())
            let rung = chaosRung
            let blockCount = (side / rung) * (side / rung)
            // Per-frame spatial rung-16 pools of the staged field.
            let spatial = (0..<engineOut.count).map { chaosPool(labs: labs[$0], side: side) }
            // Temporal pooling over 4-frame groups (partial tail
            // groups are lawful degenerates; 64 divides exactly).
            let groupCount = (engineOut.count + rung - 1) / rung
            var spacetime = [[OKLabColor]]()
            spacetime.reserveCapacity(groupCount)
            for g in 0..<groupCount {
                let lo = rung * g, hi = min(rung * g + rung, engineOut.count)
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
                pairDitherFrame(indices, pooled: spacetime[f / rung],
                                solve: solves[f], mask: masks[f],
                                far: fars[f], pull: pulls[f], side: side)
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

        // ── The stage boundary (ExportMethods XP1–XP2) ──
        // Everything above is the generating state; everything below
        // turns it into bytes. A caller that keeps only the state
        // stops HERE rather than assigning a cube it will discard.
        if disposition == .generatingState {
            return Output(indexFrames: [], tables: tables,
                          stats: frameStats, mixture: mixture,
                          twoPhase: twoPhase, alpha: alpha,
                          msGain: msGain,
                          groundMoments: solves.map { $0.moments },
                          jepaH: jepa != nil, solves: solves)
        }

        // ── Stage 2: assignment — S8, THE ADDITIVE LADDER ──
        //
        // ★ Daniel's ruling 2026-08-14: "all rungs require a meaningful
        // additive to the creation of GIFs", and "read the incoming
        // information in 16x16, 32x32 and 64x64 so that we can lift a
        // coarse intuition into the final 64x64x64 voxel creation."
        //
        // The rungs now WRITE the index instead of metering it after
        // the fact: rung 16 commits bit 6 per 4×4×4 spacetime block,
        // rung 32 commits bits 5-3 per 2×2×2 block, rung 64 picks the
        // leaf exactly among that node's 8. AdditiveCensus is the
        // meter and StrataDescentTests is the gate (conformance 1.0 at
        // every stratum, against ~0 for the free search this replaces).
        //
        // ONE LAW, so there is no engine to choose between: the fine
        // search is 8 candidates rather than 128, which is 16× less
        // inner loop, and the whole descent costs roughly 4.5M distance
        // evaluations against the old 33.5M. DyadANE's fused graph
        // implements the SUPERSEDED free argmin over all 128 leaves, so
        // it is no longer this law's twin and is not consulted here.
        // Rebuilding it for the descent is Mac-lab work (nn/dyad-assign)
        // and is owed; until then the exact CPU descent IS the law,
        // not a substitute for it.
        let labPrimaries = solves.map { $0.primaries }
        let cubeSide = Int(Double(labs[0].count).squareRoot())
        let cpu = StrataDescent.assign(
            labs: labs, masks: masks, fars: fars,
            primaries: labPrimaries, nodes16: solves.map { $0.nodes16 },
            side: cubeSide)
        return Output(indexFrames: chaosRefine(pairDither(cpu)), tables: tables,
                      stats: frameStats, mixture: mixture,
                      twoPhase: twoPhase, alpha: alpha,
                      msGain: msGain,
                      groundMoments: solves.map { $0.moments },
                      jepaH: jepa != nil, solves: solves)
    }

    /// Stage 1c for ONE frame: ★PAIR TREE (P1) figures = the analytic
    /// dyadic tree of the warm-started stats (closed-form Gaussian
    /// splits — PairTree.swift); rings remain only as the v1/v2
    /// rebuild path. cL anchors the ground family at the FIGURE
    /// CENTROID's lightness — for rings that was T[0]; the tree's
    /// T[0] is a corner leaf, so read the centroid from the stats
    /// themselves (same number, honest source).
    ///
    /// ★ GroundHue: the ground family fitted here now carries Δh as
    /// well, so the σ half is emitted in the BACKGROUND's own hue.
    /// This is step A of GH12 — a DISPLAY-only rotation: the σ-side
    /// search still minimises d(node, target) in the figure frame, so
    /// the index stream is byte-identical and costs nothing in LZW.
    /// Step B (the pre-image search, which moves pixels) awaits its
    /// own device pass — GH12 notes that search is already
    /// suboptimal today at Δh = 0 whenever βC ≠ 1 or ΔL ≠ 0.
    static func solveFrame(
        warm: DyadPalette.Stats,
        background: DyadPalette.BackgroundMoments?,
        centroid cF: OKLabColor,
        mixture: DepthMixture.Fit,
        twoPhase: Bool,
        bleed: Bool,
        figureDepth: Int = PairTree.fullDepth
    ) -> FrameSolve {
        // ★ THE eFig DIAL, EXECUTABLE (2026-08-16). PT5's prefix law
        // says a truncated index names the coarser level's node, and
        // the tree now records every level, so the dial is a lookup
        // rather than a re-solve. `PairTree.fullDepth` is the identity
        // and the default, so every existing caller is byte-identical.
        let tree = CameraConfig.pairTree
            ? PairTree.solveFigures(stats: warm).truncated(toFigureDepth: figureDepth)
            : nil
        let prims8 = tree?.figures8 ?? DyadPalette.primaries(stats: warm)
        let prims = tree?.figures ?? prims8.map { DyadPalette.oklab(fromSRGB8: $0) }
        let cL = tree != nil ? warm.centroid.l : DyadPalette.centroidL(prims8)
        let gm = background.map {
            DyadPalette.groundMoments(centroidL: cL, primsLab: prims, background: $0)
        } ?? DyadPalette.priorMoments(centroidL: cL)
        let table = tree.map { PairTree.table(figures8: $0.figures8, moments: gm) }
            ?? DyadPalette.table(stats: warm, moments: gm)
        return FrameSolve(primaries: prims,
                          nodes16: tree?.nodes16 ?? [],
                          canonical16: tree?.canonical16 ?? [],
                          table: table, moments: gm, centroid: cF,
                          mixture: mixture, twoPhase: twoPhase, bleed: bleed)
    }

    /// The σ side's blur target for ONE frame: the rung-16 block mean
    /// of the staged field (spec §6d). The export pools these again
    /// over 4-frame groups (S4); the live read pools the frame it is
    /// showing. One pooling, two windows.
    static func chaosPool(labs: [OKLabColor], side: Int) -> [OKLabColor] {
        let rung = chaosRung
        let bSide = side / rung
        var pooled = [OKLabColor](repeating: OKLabColor(l: 0, a: 0, b: 0),
                                  count: bSide * bSide)
        for by in 0..<bSide {
            for bx in 0..<bSide {
                var sl = 0.0, sa = 0.0, sb = 0.0
                for dy in 0..<rung {
                    for dx in 0..<rung {
                        let lab = labs[(by * rung + dy) * side + bx * rung + dx]
                        sl += lab.l; sa += lab.a; sb += lab.b
                    }
                }
                let n = Double(rung * rung)
                pooled[by * bSide + bx] = OKLabColor(l: sl / n, a: sa / n, b: sb / n)
            }
        }
        return pooled
    }

    /// The band post-pass on ONE frame: the Bayer threshold flips
    /// coverage 1 − t back to the primary side; what stays on the σ
    /// side takes the pooled blur target, quantized at the 32-LEVEL
    /// when the tree is on (prefix law, P2). Export and preview call
    /// this — there is no second dither.
    static func pairDitherFrame(_ indices: [UInt8], pooled: [OKLabColor],
                                solve: FrameSolve, mask: [Bool], far: [Bool],
                                pull: [Float], side: Int) -> [UInt8] {
        let rung = chaosRung
        let bSide = side / rung
        let prims = solve.primaries
        let nodes = solve.nodes16
        let canon = solve.canonical16
        var out = indices
        for p in 0..<indices.count where !mask[p] && !far[p] {
            if bayer4[(p / side) % 4][(p % side) % 4] >= pull[p] {
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

    /// ★JEPA-H (JH4): the deployed placement law. Pool the per-frame
    /// generating state to the 16-slot ring (slot = 4-frame mean —
    /// the rung-16 cadence, the resolution of depth) and steady ONE
    /// ring holding ALL of it: the 6 stats dims the corpus trained
    /// on (centroid l,a,b + LOG-diagonals) plus the bg-moments
    /// triple (meanL, meanLnC, LOG sdLnC — location dims raw, scale
    /// dims in log, the corpus's own convention) plus ★ the hue
    /// RESULTANT's two components (GroundHue GH13: the ground's
    /// fourth coordinate rides the ring as a vector, never as an
    /// angle — an angle EMA across the 0/360 seam returns the
    /// opposite hue). The head is per-dim and scale-free, so the
    /// learned regime→kernel map covers the extra dims lawfully —
    /// ruling R2, one smoothing law for all generating state (the
    /// 11EB44F0 capture showed the split-cadence alternative churns
    /// the ground half).
    ///
    /// SHAPE — the correlation coefficients the corpus never
    /// modeled — rides the slot pool and recombines as
    /// c_ij = r_ij·√(c_ii·c_jj), positive-semidefinite by
    /// construction, no new constants. Slots without background
    /// evidence fill by carry AROUND the ring (the loop is a torus;
    /// "before" wraps); no evidence at all ⇒ bg stays nil and the
    /// Wada prior rules downstream. Frames within a slot share one
    /// generating state, so whole tables hold at 5 Hz exactly like
    /// the live read. Requires the frame count to divide into 16
    /// equal slots; otherwise nil and the EMA law stands.
    static func jepaSmoothed(
        _ raw: [DyadPalette.Stats],
        bg: [DyadPalette.BackgroundMoments?]
    ) -> (stats: [DyadPalette.Stats],
          bg: [DyadPalette.BackgroundMoments?])? {
        let slots = JepaHHead.slots
        guard raw.count >= slots, raw.count % slots == 0,
              bg.count == raw.count else { return nil }
        let group = raw.count / slots
        let eps = 1e-12                    // whitening-law epsilon
        var pooled: [[Double]] = []        // [slot][9], statVector order
        pooled.reserveCapacity(slots)
        var bgPooled: [DyadPalette.BackgroundMoments?] = []
        for s in 0..<slots {
            var acc = [Double](repeating: 0, count: 9)
            var bgAcc = (0.0, 0.0, 0.0, 0.0, 0.0)
            var bgN = 0.0
            for f in (s * group)..<((s + 1) * group) {
                let v = statVector(raw[f])
                for i in 0..<9 { acc[i] += v[i] }
                if let rb = bg[f] {
                    bgAcc.0 += rb.meanL; bgAcc.1 += rb.meanLnC
                    bgAcc.2 += rb.sdLnC
                    // ★ GH13: the hue pools as a VECTOR (the slot's
                    // own resultant), never as an angle.
                    bgAcc.3 += rb.hueA; bgAcc.4 += rb.hueB
                    bgN += 1
                }
            }
            pooled.append(acc.map { $0 / Double(group) })
            bgPooled.append(bgN > 0
                ? DyadPalette.BackgroundMoments(
                    meanL: bgAcc.0 / bgN, meanLnC: bgAcc.1 / bgN,
                    sdLnC: bgAcc.2 / bgN,
                    hueA: bgAcc.3 / bgN, hueB: bgAcc.4 / bgN)
                : nil)
        }

        // Torus fill: carry the nearest present slot around the ring.
        let haveBg = bgPooled.contains { $0 != nil }
        if haveBg {
            let first = bgPooled.firstIndex { $0 != nil }!
            var carry = bgPooled[first]!
            for k in 0..<slots {
                let s = (first + k) % slots
                if let v = bgPooled[s] { carry = v } else { bgPooled[s] = carry }
            }
        }

        let ring = (0..<slots).map { s -> [Double] in
            let v = pooled[s]
            var dims = [v[0], v[1], v[2],
                        log(max(v[3], eps)), log(max(v[6], eps)),
                        log(max(v[8], eps))]
            if haveBg {
                let b = bgPooled[s]!
                // Location dims raw, scale dims in log (the corpus's
                // own convention) — and the hue as its two VECTOR
                // components (GH13). The head is per-dim and
                // scale-free, so the learned regime→kernel map covers
                // them lawfully; a smoothed vector need not stay unit
                // because only its DIRECTION is read (GH6).
                dims += [b.meanL, b.meanLnC, log(max(b.sdLnC, eps)), b.hueA, b.hueB]
            }
            return dims
        }
        let shat = JepaHHead.smoothRing(ring)

        var outStats: [DyadPalette.Stats] = []
        var outBg: [DyadPalette.BackgroundMoments?] = []
        outStats.reserveCapacity(raw.count)
        outBg.reserveCapacity(raw.count)
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
            let bgOut: DyadPalette.BackgroundMoments? = haveBg
                ? DyadPalette.BackgroundMoments(
                    meanL: sh[6], meanLnC: sh[7], sdLnC: exp(sh[8]),
                    hueA: sh[9], hueB: sh[10])
                : nil
            for _ in 0..<group {
                outStats.append(st)
                outBg.append(bgOut)
            }
        }
        return (stats: outStats, bg: outBg)
    }

    /// Exact CPU assignment on staged labs: face → nearest primary
    /// (0..127); band background → σ-mirror 255 − nearest; far
    /// background → exactly 255. The reference the ANE path is
    /// parity-tested against. The band pair dither is NOT here:
    /// process() applies it as a post-pass on both engines.
    ///
    /// ★ DO NOT replace this exhaustive argmin with a greedy descent
    /// down the PairTree. It looks like free speed (7 levels x 2 evals
    /// instead of 128) and it is not. MEASURED, nn/descent/RESULTS.md,
    /// 96 held-out trees:
    ///
    ///     greedy-L2 (means only)   0.8601 agreement, excess 0.000634
    ///     lookahead-L2 (DL6/DL7)   0.9652 agreement, excess 0.000076
    ///     exhaustive (this code)   1.0,              excess 0
    ///
    /// Greedy costs 8x the excess distortion. Two further reasons this
    /// stays exact: (1) it is the PARITY REFERENCE for DyadANE, so an
    /// approximate reference dissolves the gate that validates the ANE
    /// path; (2) the lawful log-time form is lookahead-L2, and it does
    /// not pay where assignment actually runs, because on the ANE both
    /// 128-exhaustive and 80-eval lookahead are matmul-shaped (the
    /// honesty note in RESULTS.md). If the CPU path ever needs the
    /// win (FACE mode and the simulator run here, not on the ANE),
    /// lookahead-L2 is the ONLY sanctioned form, it ships inside this
    /// function rather than as a separate artifact per the ONE-MODEL
    /// decree, and it needs a ruling plus a device pass because it
    /// changes GIF bytes.
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

    // ════════════════════════════════════════════════════════════
    // MARK: - ★ WATCHING (spec/ui/EditMachine.hs EM12/EM13)
    //
    // weave = watch + keep. This is the live driver — the state a
    // continuous read needs and NOTHING ELSE. Every law it applies
    // is a call back into this same file:
    //
    //   the read    — κ = 2×2×2 twice (4 in space × 4 in time)
    //                 pools the fine feed to the coarse rung, and
    //                 carries the within-cell depth variance the
    //                 pooling removed (DM11's τ-lift is an identity,
    //                 so the crossover and the band are the fine
    //                 rung's, not the pooled field's);
    //   the solve   — `process` itself, over the 16-frame coarse
    //                 cube = the last 3.2 s = one loop. The preview
    //                 is the GIF the last loop would have made;
    //   the assign  — `stagedField` + `assignRoles` + `chaosPool` +
    //                 `pairDitherFrame`, at the fine rung, 20 Hz.
    //
    // The cadence split is the ladder's, not an approximation
    // invented here: rung 16 IS the resolution of depth (TL8/TL9,
    // 5 Hz), RGB rides the fine rung at 20 Hz — the same split the
    // export obeys inside `process`.
    //
    // Called ONLY on the owning manager's serial queue — no locking.
    // ════════════════════════════════════════════════════════════

    final class Live {

        /// Frames per solve: the ladder's own κ step from the fine
        /// rung to the coarse one — 20 Hz / 4 = the 5 Hz rung-16
        /// cadence (TL8/TL9). Never a second number.
        static let refreshStride = Rung.fine.side / Rung.coarse.side

        /// The coarse cube the solve reads: one full loop of coarse
        /// frames = 16 × 4 fine frames = 3.2 s (FeedFormat's span law).
        static let ringFrames = Rung.coarse.frames

        private let coarseSide = Rung.coarse.side
        private var counter = 0

        // The open coarse frame: κ sums in progress. Depth carries its
        // square sum too — the within-cell variance is the read's, and
        // pooling is the only thing that could lose it.
        private var accRGB: [(Double, Double, Double)]
        private var accDepth: [Double]
        private var accDepthSq: [Double]
        private var accN = 0

        // The closed coarse frames: the live feed's rung-16 cube.
        private var ringRGB: [[(Float, Float, Float)]] = []
        private var ringDepth: [[Float]] = []
        private var ringWithin: [Double] = []

        /// The last solve — the generating state the surface is
        /// showing. nil until the first coarse frame closes.
        private(set) var solve: FrameSolve?

        /// How many solves have landed. The surface's instruments
        /// (the 256-entry table, the coarse reads) are functions of
        /// the SOLVE, not of the frame, so republishing them at 20 Hz
        /// would be pure SwiftUI churn: a manager compares this
        /// counter and publishes only when it moves — i.e. on the
        /// ladder's own 5 Hz rung-16 cadence (TL8/TL9).
        private(set) var solveSerial = 0

        init() {
            let cells = Rung.coarse.side * Rung.coarse.side
            accRGB = [(Double, Double, Double)](repeating: (0, 0, 0), count: cells)
            accDepth = [Double](repeating: 0, count: cells)
            accDepthSq = [Double](repeating: 0, count: cells)
        }

        /// The 256 entries the surface draws indices with; empty until
        /// the first solve (callers show the lattice preview, the PRIOR).
        var table: [(UInt8, UInt8, UInt8)] { solve?.table ?? [] }

        /// The current state packaged for the aerialPreview Metal
        /// kernel, or nil until the first solve.
        var metalState: MetalState? {
            guard let solve, solve.primaries.count == DyadPalette.primaryCount
            else { return nil }
            return MetalState(
                primaries: solve.primaries.map {
                    SIMD4<Float>(Float($0.l), Float($0.a), Float($0.b), 0)
                },
                nodes: zip(solve.nodes16, solve.canonical16).map { node, leaf in
                    SIMD4<Float>(Float(node.l), Float(node.a), Float(node.b),
                                 Float(leaf))
                },
                centroid: SIMD3<Float>(Float(solve.centroid.l),
                                       Float(solve.centroid.a),
                                       Float(solve.centroid.b)),
                sStar: Float(solve.mixture.crossover),
                tau: Float(solve.mixture.temperature),
                twoPhase: solve.twoPhase,
                bleed: solve.bleed)
        }

        // MARK: - The read (κ pooling) and the 5 Hz solve

        /// Take one fine frame into the read. Always advances the
        /// cadence counter — call exactly once per frame.
        func read(rgb: [(Float, Float, Float)], depths: [Float]) {
            accumulate(rgb: rgb, depths: depths)
            // Close the coarse frame on the ladder's cadence — the
            // first fine frame closes one immediately, so the surface
            // has a real table from the start (a short group is the
            // same lawful degenerate `process` allows for a partial
            // tail group).
            if counter % Self.refreshStride == 0 {
                closeCoarseFrame()
                resolve()
            }
            counter += 1
        }

        /// κ pooling, fine → coarse: 4×4 in space now, 4 in time when
        /// the frame closes (OV10 / TriScaleLadder §8).
        private func accumulate(rgb: [(Float, Float, Float)], depths: [Float]) {
            let side = Int(Double(depths.count).squareRoot())
            let block = side / coarseSide
            guard block > 0 else { return }
            for cy in 0..<coarseSide {
                for cx in 0..<coarseSide {
                    var r = 0.0, g = 0.0, b = 0.0, d = 0.0, dd = 0.0
                    for dy in 0..<block {
                        for dx in 0..<block {
                            let p = (cy * block + dy) * side + cx * block + dx
                            r += Double(rgb[p].0); g += Double(rgb[p].1); b += Double(rgb[p].2)
                            // The depth signal is total: NaN reads the
                            // neutral fill, exactly as DepthSignal does.
                            let v = Double(depths[p])
                            let q = v.isNaN ? Double(DepthSignal.fill) : min(max(v, 0), 1)
                            d += q; dd += q * q
                        }
                    }
                    let c = cy * coarseSide + cx
                    let n = Double(block * block)
                    accRGB[c].0 += r / n; accRGB[c].1 += g / n; accRGB[c].2 += b / n
                    accDepth[c] += d / n; accDepthSq[c] += dd / n
                }
            }
            accN += 1
        }

        /// Divide the κ sums, push the coarse frame onto the ring, and
        /// keep the mean within-cell depth variance the pooling
        /// removed — the τ-lift's only input (DM11).
        private func closeCoarseFrame() {
            guard accN > 0 else { return }
            let n = Double(accN)
            let cells = accDepth.count
            var rgb = [(Float, Float, Float)](repeating: (0, 0, 0), count: cells)
            var depth = [Float](repeating: 0, count: cells)
            var within = 0.0
            for c in 0..<cells {
                rgb[c] = (Float(accRGB[c].0 / n), Float(accRGB[c].1 / n),
                          Float(accRGB[c].2 / n))
                let m = accDepth[c] / n
                depth[c] = Float(m)
                within += max(0, accDepthSq[c] / n - m * m)
                accRGB[c] = (0, 0, 0); accDepth[c] = 0; accDepthSq[c] = 0
            }
            accN = 0
            ringRGB.append(rgb)
            ringDepth.append(depth)
            ringWithin.append(within / Double(cells))
            if ringRGB.count > Self.ringFrames {
                ringRGB.removeFirst(); ringDepth.removeFirst(); ringWithin.removeFirst()
            }
        }

        /// THE SOLVE — `process` on the coarse cube, kept only as the
        /// generating state (EM12: one encoder, two dispositions).
        /// BLEED is read here so the live surface answers the same
        /// setting the export obeys.
        ///
        /// `.generatingState` is not a shortcut: stages 0–1 run
        /// exactly as the export runs them. It declines stage 2,
        /// which would assign the COARSE cube — indices at the wrong
        /// rung, discarded unexamined, paid for inside the capture
        /// callback's 50 ms budget. The assignment the surface shows
        /// is `assign`'s, at the fine rung, 20 Hz.
        private func resolve() {
            guard !ringRGB.isEmpty else { return }
            let within = ringWithin.reduce(0, +) / Double(ringWithin.count)
            let out = DyadPipeline.process(rgb: ringRGB, depths: ringDepth,
                                           withinVariance: within,
                                           bleed: ExportSettings.load().bleed,
                                           keeping: .generatingState)
            if let last = out?.solves.last {
                solve = last
                solveSerial &+= 1
            }
        }

        // MARK: - The coarse reads (32³ and 16³), at the solve cadence

        /// ★ EM2 / WG12: WATCHING reads the live feed at ALL THREE
        /// rungs at once. The fine read is `assign` above; these are
        /// the other two, and they are the SAME law — the feed is box
        /// pooled in space (κ, exactly `accumulate`'s spatial half)
        /// and then handed to `assign`, which is the export's own
        /// assignment. ★ Indices are NEVER pooled (the palette index
        /// is not a linear quantity); the FEED is pooled and then
        /// assigned, which is what makes the three windows agree.
        ///
        /// Cadence: the caller runs this only when `solveSerial`
        /// moves — rung 16 IS the resolution of depth at 5 Hz
        /// (TL8/TL9), so the coarse instruments read at the coarse
        /// clock and cost (1024 + 256)/4 assignments per fine frame
        /// rather than 1280.
        func coarseReads(rgb: [(Float, Float, Float)], depths: [Float])
            -> (mid: [UInt8], coarse: [UInt8])? {
            let side = Int(Double(depths.count).squareRoot())
            guard side > 0, side * side == depths.count else { return nil }
            guard let (r32, d32) = Self.poolSpace(rgb: rgb, depths: depths,
                                                  from: side, to: Rung.mid.side),
                  let (r16, d16) = Self.poolSpace(rgb: rgb, depths: depths,
                                                  from: side, to: Rung.coarse.side),
                  let mid = assign(rgb: r32, depths: d32),
                  let coarse = assign(rgb: r16, depths: d16)
            else { return nil }
            return (mid, coarse)
        }

        /// The κ box pool in space: `from`² → `to`² by averaging each
        /// block. Returns nil when the sides are not commensurate —
        /// a non-integer block is not a rung of the ladder (FC2).
        static func poolSpace(rgb: [(Float, Float, Float)], depths: [Float],
                              from: Int, to: Int)
            -> (rgb: [(Float, Float, Float)], depths: [Float])? {
            guard to > 0, from >= to, from % to == 0 else { return nil }
            let block = from / to
            if block == 1 { return (rgb, depths) }
            var outRGB = [(Float, Float, Float)](repeating: (0, 0, 0), count: to * to)
            var outD = [Float](repeating: 0, count: to * to)
            let n = Float(block * block)
            for cy in 0..<to {
                for cx in 0..<to {
                    var r: Float = 0, g: Float = 0, b: Float = 0, d: Float = 0
                    for dy in 0..<block {
                        for dx in 0..<block {
                            let p = (cy * block + dy) * from + cx * block + dx
                            r += rgb[p].0; g += rgb[p].1; b += rgb[p].2
                            // Total, exactly as `accumulate` is: NaN
                            // reads the neutral fill (DepthSignal).
                            let v = depths[p]
                            d += v.isNaN ? DepthSignal.fill : min(max(v, 0), 1)
                        }
                    }
                    let c = cy * to + cx
                    outRGB[c] = (r / n, g / n, b / n)
                    outD[c] = d / n
                }
            }
            return (outRGB, outD)
        }

        // MARK: - The 20 Hz assignment (fine rung)

        /// One fine frame under the export's own assignment law, or
        /// nil until the first solve. Every step is a call back into
        /// `DyadPipeline` — the preview runs no law of its own.
        func assign(rgb: [(Float, Float, Float)], depths: [Float]) -> [UInt8]? {
            guard let solve, !solve.primaries.isEmpty else { return nil }
            let side = Int(Double(rgb.count).squareRoot())
            let samples = rgb.map { DyadPipeline.srgb8(from: $0) }
            // DY17: the argmin reads the CONTINUOUS staged value. This
            // used to be `staged.map { oklab(fromSRGB8: $0) }`, which
            // searched a round-tripped value the spec never searches
            // and the GPU twin never produced. One pass gives both, so
            // the 20 Hz path does one OKLab conversion per pixel, not
            // two.
            let labs = DyadPipeline.stagedPair(samples: samples, depths: depths,
                                               about: solve.centroid).lab
            let ts = depths.map {
                DyadPipeline.coverage($0, fit: solve.mixture,
                                      twoPhase: solve.twoPhase, bleed: solve.bleed)
            }
            let mask = ts.map { $0 < DyadPipeline.coverageFloor }
            let far = [Bool](repeating: false, count: rgb.count)
            // ★ OWED, AND SAID OUT LOUD (NO-STUBS decree). The export
            // moved to the additive ladder (StrataDescent, S8) on
            // 2026-08-14; this surface has NOT. So right now the app
            // holds TWO assignment laws: the export descends the rungs,
            // this frame still searches all 128 leaves freely. That
            // contradicts EM13 (the preview IS the GIF), and it is a
            // second law rather than a twin, because the two do not
            // agree and no parity test claims they do.
            //
            // It is written here instead of in a doc because this line
            // is where the divergence lives.
            //
            // THE CLOSE, which the ladder architecture already fits:
            // stages A and B are decided at the COARSE rung, which this
            // driver already solves at 5 Hz over the 16-frame cube, so
            // the half and the node can be committed there and carried
            // on FrameSolve. Only stage C (the exact 8-way leaf argmin)
            // then runs per frame at 20 Hz, which is CHEAPER than the
            // 128-way search on this line today. The GPU twin in
            // Quantize.metal's aerialPreview needs the same two buffers.
            let engine = DyadPipeline.assignRoles(labs: labs, mask: mask, far: far,
                                                  labPrimaries: solve.primaries)
            return DyadPipeline.pairDitherFrame(
                engine, pooled: DyadPipeline.chaosPool(labs: labs, side: side),
                solve: solve, mask: mask, far: far,
                pull: ts.map { Float($0) }, side: side)
        }

        /// Full CPU path: read + assign (FACE mode, and the twin when
        /// the platform exposes no Metal).
        func process(rgb: [(Float, Float, Float)], depths: [Float]) -> [UInt8]? {
            read(rgb: rgb, depths: depths)
            return assign(rgb: rgb, depths: depths)
        }
    }
}
