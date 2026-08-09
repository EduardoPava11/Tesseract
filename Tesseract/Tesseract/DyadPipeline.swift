// DyadPipeline.swift
// Tesseract
//
// DYAD-256 export path: per-frame depth-masked OKLab statistics →
// EMA warm start → paired 256-entry table per frame → role-law
// index assignment (face → primaries 0..127, background → 255).
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
    }

    /// EMA weight of the CURRENT frame's statistics (spec DY7: the
    /// blend is on statistics, so shells stay deterministic and
    /// palettes cannot flicker by cluster permutation).
    static let currentFrameWeight = 0.3

    /// Face mask cut, matching PerfectQuantizer.analyzeSubject's
    /// subject threshold: depths > 0.6 = face, else background.
    static let faceThreshold: Float = 0.6

    /// The harsh bleed (spec DyadPalette.hs §6 v2): background pixels
    /// are pulled toward the centroid by t(d) over a narrow depth band,
    /// then assigned the σ-mirror of their nearest primary. Beyond the
    /// band the pull saturates and the pixel is exactly index 255.
    static let bleedWidth: Float = 0.15
    static let bleedGamma: Float = 0.5

    /// 0 at the silhouette, 1 at and beyond faceThreshold − bleedWidth.
    static func pull(_ depth: Float) -> Float {
        guard depth < faceThreshold else { return 0 }
        let t = min(1, (faceThreshold - depth) / bleedWidth)
        return pow(t, bleedGamma)
    }

    /// Standard Bayer 4×4 thresholds, normalized to the midpoints
    /// {0.5/16 … 15.5/16} (spec DyadPalette.hs §6 v3). The bleed band
    /// dithers between the two sides of its pair: coverage t of each
    /// tile shows the σ side, the rest the primary side.
    static let bayer4: [[Float]] = {
        let m: [[Float]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
        return m.map { row in row.map { ($0 + 0.5) / 16 } }
    }()

    /// Build per-frame DYAD tables + index frames from a capture.
    /// Requires rawRGB on every frame (present in the record path);
    /// returns nil otherwise so callers keep the lattice output.
    ///
    /// Two stages, split on the law boundary (ExportMethods XP1–XP2):
    /// stage 1 (CPU, exact) solves statistics → EMA → tables;
    /// stage 2 (assignment) runs on the ANE in one dispatch for full
    /// 64-frame captures, and falls back to the identical CPU search
    /// otherwise — near-tie flips are the only permitted difference.
    /// `bleed: false` = role law v1, a lawful subset of v2: every
    /// background pixel fully pulled → the flat solid comp(centroid).
    static func process(frames: [QuantizedFrame], bleed: Bool = true) -> Output? {
        guard !frames.isEmpty,
              frames.allSatisfy({ $0.rawRGB != nil }) else { return nil }

        // ── Stage 1: law-bearing (exact) — tables + staged inputs.
        // Labs are PRE-PULLED for the bleed: background pixels move
        // toward the centroid by t(d) before assignment, so face and
        // background share one nearest-primary search downstream.
        var tables: [Data] = []
        var frameStats: [DyadPalette.Stats] = []
        var labPrimaries: [[OKLabColor]] = []
        var labs: [[OKLabColor]] = []
        var masks: [[Bool]] = []
        var fars: [[Bool]] = []
        var pulls: [[Float]] = []
        tables.reserveCapacity(frames.count)

        var smoothed: DyadPalette.Stats?
        for frame in frames {
            let samples = frame.rawRGB!.map { srgb8(from: $0) }
            let weights = frame.depths.map { Double($0) }

            let stats = DyadPalette.analyze(samples, weights: weights)
            let warm = smoothed.map { DyadPalette.ema(alpha: currentFrameWeight, stats, $0) } ?? stats
            smoothed = warm

            let table = DyadPalette.table(stats: warm)
            tables.append(DyadPalette.gifColorTable(table))
            frameStats.append(warm)
            let prims = (0..<DyadPalette.primaryCount).map {
                DyadPalette.oklab(fromSRGB8: table[$0])
            }
            labPrimaries.append(prims)
            let centroid = prims[0]

            var frameLabs = [OKLabColor]()
            var frameMask = [Bool]()
            var frameFar = [Bool]()
            var framePull = [Float]()
            frameLabs.reserveCapacity(samples.count)
            for (p, rgb) in samples.enumerated() {
                let d = frame.depths[p]
                let face = d > faceThreshold
                let t: Float = face ? 0 : (bleed ? pull(d) : 1)
                frameMask.append(face)
                frameFar.append(!face && t >= 1)
                framePull.append(t)
                let lab = DyadPalette.oklab(fromSRGB8: rgb)
                if t <= 0 {
                    frameLabs.append(lab)
                } else {
                    let g = Double(1 - t)
                    frameLabs.append(OKLabColor(
                        l: centroid.l + (lab.l - centroid.l) * g,
                        a: centroid.a + (lab.a - centroid.a) * g,
                        b: centroid.b + (lab.b - centroid.b) * g))
                }
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
        // untouched; bleed off has no band (all background is far).
        func pairDither(_ engineOut: [[UInt8]]) -> [[UInt8]] {
            guard bleed else { return engineOut }
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
            return Output(indexFrames: pairDither(ane), tables: tables, stats: frameStats)
        }
        let cpu = (0..<frames.count).map { f in
            assignRoles(labs: labs[f], mask: masks[f], far: fars[f],
                        labPrimaries: labPrimaries[f])
        }
        return Output(indexFrames: pairDither(cpu), tables: tables, stats: frameStats)
    }

    /// Exact CPU assignment on PRE-PULLED labs: face → nearest primary
    /// (0..127); bleed-band background → σ-mirror 255 − nearest;
    /// fully pulled background → exactly 255. The reference the ANE
    /// path is parity-tested against. The band pair dither is NOT
    /// here: process() applies it as a post-pass on both engines.
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

    private static func srgb8(from f: (Float, Float, Float)) -> (UInt8, UInt8, UInt8) {
        func to8(_ c: Float) -> UInt8 {
            UInt8(min(255, max(0, (Double(c) * 255).rounded(.toNearestOrEven))))
        }
        return (to8(f.0), to8(f.1), to8(f.2))
    }
}
