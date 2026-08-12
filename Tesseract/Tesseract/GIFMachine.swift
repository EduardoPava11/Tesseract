// GIFMachine.swift
// Tesseract
//
// The 64³ GIF machine: every export is 64 frames of 64×64 indices,
// each frame carrying its own 256-entry Local Color Table — the
// DYAD-256 scheme is the ONLY export law (Daniel's decree,
// 2026-08-12: per-frame palettes, non-negotiable; the tesseract/
// refined global-table methods are deleted). A capture that cannot
// run DYAD exports NOTHING — the nil is surfaced honestly
// (encodeFailedMessage), never silently downgraded to a global
// table. Port of spec/output/ExportMethods.hs (XM1–XM4, XP1–XP2 —
// the Haskell spec is authoritative).

import Foundation

/// The persisted settings. Missing stored values parse to defaults.
/// Useful and simple: every entry here has a visible effect on the
/// GIF. (The old `method` setting is gone — DYAD is the law, not a
/// choice; a stale "export.method" default is simply ignored.)
struct ExportSettings: Sendable {
    /// DYAD background: coverage dither band (true) or hard MAP
    /// classes only (false — role law v1, a lawful subset).
    var bleed: Bool
    /// Mirror the exported GIF horizontally (selfie orientation).
    /// Index-domain flip — exact.
    var mirror: Bool

    static let bleedKey = "export.bleed"
    static let mirrorKey = "export.mirror"

    static func load() -> ExportSettings {
        let defaults = UserDefaults.standard
        return ExportSettings(
            bleed: defaults.object(forKey: bleedKey) as? Bool ?? true,
            mirror: defaults.object(forKey: mirrorKey) as? Bool ?? false)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(bleed, forKey: Self.bleedKey)
        defaults.set(mirror, forKey: Self.mirrorKey)
    }
}

/// One dispatcher for every capture export.
enum GIFMachine {

    /// DYAD needs per-pixel color (the mask rides the always-present
    /// depth slot). Both capture managers provide rawRGB on the
    /// record path; an ineligible capture exports nothing.
    static func eligible(frames: [QuantizedFrame]) -> Bool {
        !frames.isEmpty && frames.allSatisfy { $0.rawRGB != nil }
    }

    /// Horizontal index-domain flip (exact, involutive) — the MIRROR
    /// toggle. No color math; palette indices move, values don't.
    static func mirrored(_ indices: [UInt8], side: Int) -> [UInt8] {
        var out = indices
        for y in 0..<side {
            let row = y * side
            for x in 0..<(side / 2) {
                out.swapAt(row + x, row + side - 1 - x)
            }
        }
        return out
    }

    /// Ou & Luo pair-harmony of the whole capture's DYAD tables, for
    /// the GIF provenance trace: mean of the per-frame means, minimum
    /// over every pair of every frame. Each 768-byte table is entry i
    /// at bytes 3i..3i+2; harmony is scored over the 128 sigma-pairs.
    static func harmonyTrace(tables: [Data]) -> String {
        var meanSum = 0.0
        var worst = Double.infinity
        for table in tables {
            let entries = (0..<256).map { i -> (UInt8, UInt8, UInt8) in
                (table[table.startIndex + 3 * i],
                 table[table.startIndex + 3 * i + 1],
                 table[table.startIndex + 3 * i + 2])
            }
            let h = DyadHarmony.tableHarmony(entries)
            meanSum += h.mean
            worst = Swift.min(worst, h.min)
        }
        return String(format: "DYAD HARMONY mean=%.2f min=%.2f pairs=128 frames=%d",
                      meanSum / Double(max(1, tables.count)), worst, tables.count)
    }

    /// The full DYAD provenance trace: harmony, settings, and the
    /// capture's GENERATING STATISTICS — 9 doubles per frame in
    /// shortest exact round-trip form (centroid l a b, covariance
    /// upper triangle c00 c01 c02 c11 c12 c22). Since DY8 made the
    /// solver a single-valued function of these, the STATS section
    /// rebuilds every palette byte: the GIF carries its own generator.
    static func dyadTrace(_ dyad: DyadPipeline.Output,
                          settings: ExportSettings,
                          frames: [QuantizedFrame] = []) -> String {
        let tables = dyad.tables, stats = dyad.stats, indexFrames = dyad.indexFrames
        var lines = [harmonyTrace(tables: tables)]
        lines.append("DYAD SETTINGS bleed=\(settings.bleed ? 1 : 0) mirror=\(settings.mirror ? 1 : 0)")
        // The derived role law — every number an OUTPUT of the capture's
        // own depth field (spec temporal/DepthMixture.hs; no naked
        // constants). m* is the crossover reported in meters.
        let m = dyad.mixture
        lines.append(String(
            format: "DYAD MIXTURE phases=%d muF=%.6g muB=%.6g piB=%.6g sigma=%.6g "
                  + "sStar=%.6g tau=%.6g mStar=%.4gm alpha=%.6g msAlpha=%.6g",
            dyad.twoPhase ? 2 : 1, m.muF, m.muB, m.piB, m.sigma,
            m.crossover, m.temperature,
            DepthMixture.metersOf(signal: m.crossover), dyad.alpha,
            dyad.msGain))
        // v2 (phase-palette step 3, ruling R2): 9 stats numbers plus
        // the frame's fitted ground moments (deltaL alphaC betaC cap)
        // — 13 per line. The GIF still carries its full generator.
        // v3 (★PAIR TREE, 2026-08-12): same 13 numbers, solved
        // through the analytic dyadic tree instead of the rings —
        // the version tag picks the rebuild law.
        lines.append("DYAD STATS \(CameraConfig.pairTree ? "v3" : "v2") frames=\(stats.count)")
        for (s, gm) in zip(stats, dyad.groundMoments) {
            let c = s.covariance
            let nums = [s.centroid.l, s.centroid.a, s.centroid.b,
                        c[0][0], c[0][1], c[0][2], c[1][1], c[1][2], c[2][2],
                        gm.deltaL, gm.alphaC, gm.betaC]
            lines.append((nums.map { "\($0)" } + [gm.capped ? "1" : "0"])
                            .joined(separator: " "))
        }
        lines.append(DyadEnergy.trace(tables: tables, indexFrames: indexFrames))
        // RATE LEDGER v1 (rate-ladder redesign step S0 — measurement
        // only; spec output/RateLadder.hs RL5): H₀ = order-0 entropy
        // of the emitted index cube, K̂ = bits/px the encoder's own
        // LZW spends, M = (8 − K̂)/8 — Rigau's operational Birkhoff
        // measure. Every later stratum step is judged against this
        // line's before/after. Comment bytes only.
        let pxCount = indexFrames.reduce(0) { $0 + $1.count }
        if pxCount > 0 {
            var hist = [Int](repeating: 0, count: 256)
            for f in indexFrames { for i in f { hist[Int(i)] += 1 } }
            let n = Double(pxCount)
            let h0 = hist.reduce(0.0) { acc, c in
                c > 0 ? acc - (Double(c) / n) * log2(Double(c) / n) : acc
            }
            let lzwBytes = GIFEncoder.lzwCost(indexFrames: indexFrames)
            let kHat = 8 * Double(lzwBytes) / n
            lines.append(String(
                format: "RATE LEDGER v1 px=%d lzw=%d H0=%.4f K=%.4f M=%.4f",
                pxCount, lzwBytes, h0, kHat, (8 - kHat) / 8))
        }
        // PHASE F (step 2, measurement only — docs/phase-palette-design.md):
        // the three reads' distortions, the Haar band energies with the
        // PP1 identity witness, and the chaos entropy bill Σ log W.
        // Basis = the emitted (unmirrored) cube against the record
        // path's rawRGB; absent rawRGB, the line is simply absent.
        if frames.count == indexFrames.count,
           frames.allSatisfy({ $0.rawRGB != nil }),
           let phase = PhaseTelemetry.measure(
               indexFrames: indexFrames, tables: tables,
               sourceRGB: frames.map { $0.rawRGB! },
               side: QuantizedFrame.size) {
            lines.append(PhaseTelemetry.trace(phase))
        }
        // SK GENES (v1, measurement only — the grounded gene machine,
        // docs/sk-gene-calculus-2026-08-11.md §14): one gene per phase
        // class played from every rung-16 block latent. Comment bytes
        // only; flag-gated (CameraConfig.skGenes, default ON —
        // measurement channel, TriScale/Dissonance precedent).
        if CameraConfig.skGenes,
           frames.count == indexFrames.count,
           frames.allSatisfy({ $0.rawRGB != nil }),
           let sk = SKGene.trace(sourceRGB: frames.map { $0.rawRGB! },
                                 side: QuantizedFrame.size) {
            #if DEBUG
            print("SKGene: \(sk) (ground=\(SKGene.isGroundAvailable ? 1 : 0) "
                  + "passer=\(SKGene.isPasserAvailable ? 1 : 0) "
                  + "codec=\(SKGene.isCodecAvailable ? 1 : 0))")
            #endif
            lines.append(sk)
        }
        return lines.joined(separator: "\n")
    }

    /// Inverse of the STATS section: parse the per-frame generating
    /// state and re-solve the tables. v3 lines carry 13 numbers and
    /// rebuild through the PAIR TREE; v2 lines carry the same 13 and
    /// rebuild through the ring solver; v1 lines carry 9 and rebuild
    /// through the ring prior path — the library's older GIFs stay
    /// self-reproducing under THEIR generation law. The provenance
    /// law (tested): the rebuilt tables byte-equal the LCTs embedded
    /// in the same GIF.
    static func rebuildTables(fromTrace trace: String) -> [Data]? {
        let lines = trace.split(separator: "\n", omittingEmptySubsequences: false)
        guard let header = lines.firstIndex(where: {
            $0.hasPrefix("DYAD STATS v1") || $0.hasPrefix("DYAD STATS v2")
                || $0.hasPrefix("DYAD STATS v3") })
        else { return nil }
        let isV3 = lines[header].hasPrefix("DYAD STATS v3")
        let isV2 = lines[header].hasPrefix("DYAD STATS v2")
        let want = (isV2 || isV3) ? 13 : 9
        var out: [Data] = []
        for line in lines[(header + 1)...] {
            let parts = line.split(separator: " ")
            guard parts.count == want else { break }
            let v = parts.compactMap { Double($0) }
            guard v.count == want else { return nil }
            let cov = [[v[3], v[4], v[5]],
                       [v[4], v[6], v[7]],
                       [v[5], v[7], v[8]]]
            let stats = DyadPalette.makeStats(
                centroid: OKLabColor(l: v[0], a: v[1], b: v[2]), covariance: cov)
            let table: [(UInt8, UInt8, UInt8)]
            if isV3 || isV2 {
                let gm = DyadPalette.GroundMoments(
                    deltaL: v[9], alphaC: v[10], betaC: v[11], capped: v[12] != 0)
                table = isV3 ? PairTree.table(stats: stats, moments: gm)
                             : DyadPalette.table(stats: stats, moments: gm)
            } else {
                table = DyadPalette.table(stats: stats)
            }
            out.append(DyadPalette.gifColorTable(table))
        }
        return out.isEmpty ? nil : out
    }

    /// The machine. Every capture export in the app goes through here.
    /// DYAD or nothing: a capture that cannot run the per-frame-
    /// palette law returns nil, surfaced as encodeFailedMessage —
    /// never a silent global-table downgrade.
    ///
    /// Returns the encoded bytes AND the Birkhoff measure of the
    /// EMITTED cube (line pass 2026-08-12: the measure shown on
    /// RESULT and written into the comment used to describe the
    /// deleted lattice quantization, not the DYAD indices shipped).
    static func makeGIF(
        frames: [QuantizedFrame],
        settings: ExportSettings,
        onFrameTable: ((Int, Data) -> Void)? = nil
    ) -> (data: Data, measure: BirkhoffMeasure)? {
        guard eligible(frames: frames),
              let dyad = DyadPipeline.process(frames: frames, bleed: settings.bleed,
                                              chaosLoop: CameraConfig.phaseChaosLoop,
                                              onFrameTable: onFrameTable)
        else { return nil }
        var counts = [Int](repeating: 0, count: 256)
        for f in dyad.indexFrames { for i in f { counts[Int(i)] += 1 } }
        let measure = BirkhoffMeasure(
            counts: counts.map { $0 / max(1, dyad.indexFrames.count) })
        guard let data = GIFEncoder.encode(
            indexFrames: settings.mirror
                ? dyad.indexFrames.map { mirrored($0, side: QuantizedFrame.size) }
                : dyad.indexFrames,
            side: QuantizedFrame.size,
            measure: measure, upscale: CameraConfig.exportUpscale,
            perFrameTables: dyad.tables,
            trace: dyadTrace(dyad, settings: settings, frames: frames))
        else { return nil }
        return (data, measure)
    }
}
