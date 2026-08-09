// GIFMachine.swift
// Tesseract
//
// The 64³ GIF machine: every export is 64 frames of 64×64 indices
// against a 256-entry table scheme. Methods differ only in how
// indices and tables are produced; the shape, the stream, and the
// setting are one. Port of spec/output/ExportMethods.hs (XM1–XM5,
// XP1–XP2 — the Haskell spec is authoritative).

import Foundation

/// How indices and tables are made. Raw values are the persisted
/// setting strings (spec §3: render/parse round-trip).
enum ExportMethod: String, CaseIterable, Sendable {
    case tesseract   // canonical 4⁴ lattice, one global table
    case refined     // lattice indices, pass-2 cell-clamped global table
    case dyad        // DYAD-256 paired per-frame local tables

    static let defaultMethod: ExportMethod = .dyad

    /// Fallback chain: dyad → refined → tesseract → ∅ (spec §2).
    var fallback: ExportMethod? {
        switch self {
        case .dyad:      return .refined
        case .refined:   return .tesseract
        case .tesseract: return nil
        }
    }

    /// Pill cycle order (UI): tesseract → refined → dyad → tesseract.
    var next: ExportMethod {
        switch self {
        case .tesseract: return .refined
        case .refined:   return .dyad
        case .dyad:      return .tesseract
        }
    }

    var label: String {
        switch self {
        case .tesseract: return "TESS"
        case .refined:   return "REFINE"
        case .dyad:      return "DYAD"
        }
    }
}

/// The persisted settings. Unknown or missing stored values parse to
/// defaults (spec XM4: garbage → default). Useful and simple: every
/// entry here has a visible effect on the GIF.
struct ExportSettings: Sendable {
    var method: ExportMethod
    /// DYAD background: harsh σ-mirror bleed (true) or the flat
    /// solid comp(centroid) everywhere (false — role law v1, a lawful
    /// subset of v2: every background pixel fully pulled).
    var bleed: Bool
    /// Mirror the exported GIF horizontally (selfie orientation).
    /// Index-domain flip — exact, method-independent.
    var mirror: Bool

    static let methodKey = "export.method"
    static let bleedKey = "export.bleed"
    static let mirrorKey = "export.mirror"

    static func load() -> ExportSettings {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: methodKey) ?? ""
        return ExportSettings(
            method: ExportMethod(rawValue: stored) ?? .defaultMethod,
            bleed: defaults.object(forKey: bleedKey) as? Bool ?? true,
            mirror: defaults.object(forKey: mirrorKey) as? Bool ?? false)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(method.rawValue, forKey: Self.methodKey)
        defaults.set(bleed, forKey: Self.bleedKey)
        defaults.set(mirror, forKey: Self.mirrorKey)
    }
}

/// One dispatcher for every capture export. DualCubeAnimator's
/// organism artifacts stay outside — that A/B surface is
/// deprecation-eligible (Daniel, 2026-08-09).
enum GIFMachine {

    /// Dyad needs per-pixel color (the mask rides the always-present
    /// depth slot); the lattice methods accept anything (spec §2).
    static func eligible(_ method: ExportMethod, frames: [QuantizedFrame]) -> Bool {
        switch method {
        case .dyad:
            return !frames.isEmpty && frames.allSatisfy { $0.rawRGB != nil }
        case .tesseract, .refined:
            return true
        }
    }

    /// Requested method → method actually run. Total; terminates at
    /// tesseract, which accepts anything (spec XM2).
    static func resolve(_ method: ExportMethod, frames: [QuantizedFrame]) -> ExportMethod {
        if eligible(method, frames: frames) { return method }
        return resolve(method.fallback ?? .tesseract, frames: frames)
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

    private static func mirrorFrames(_ frames: [QuantizedFrame]) -> [QuantizedFrame] {
        frames.map { f in
            QuantizedFrame(
                index: f.index,
                paletteIndices: mirrored(f.paletteIndices, side: QuantizedFrame.size),
                rawRGB: f.rawRGB, depths: f.depths, measure: f.measure,
                subjectAnalysis: f.subjectAnalysis, anchorTrace: f.anchorTrace,
                timestamp: f.timestamp)
        }
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
    static func dyadTrace(tables: [Data], stats: [DyadPalette.Stats],
                          settings: ExportSettings) -> String {
        var lines = [harmonyTrace(tables: tables)]
        lines.append("DYAD SETTINGS bleed=\(settings.bleed ? 1 : 0) mirror=\(settings.mirror ? 1 : 0)")
        lines.append("DYAD STATS v1 frames=\(stats.count)")
        for s in stats {
            let c = s.covariance
            let nums = [s.centroid.l, s.centroid.a, s.centroid.b,
                        c[0][0], c[0][1], c[0][2], c[1][1], c[1][2], c[2][2]]
            lines.append(nums.map { "\($0)" }.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    /// Inverse of the STATS section: parse 9 doubles per frame and
    /// re-solve the tables. The provenance law (tested): the rebuilt
    /// tables byte-equal the LCTs embedded in the same GIF.
    static func rebuildTables(fromTrace trace: String) -> [Data]? {
        let lines = trace.split(separator: "\n", omittingEmptySubsequences: false)
        guard let header = lines.firstIndex(where: { $0.hasPrefix("DYAD STATS v1") })
        else { return nil }
        var out: [Data] = []
        for line in lines[(header + 1)...] {
            let parts = line.split(separator: " ")
            guard parts.count == 9 else { break }
            let v = parts.compactMap { Double($0) }
            guard v.count == 9 else { return nil }
            let cov = [[v[3], v[4], v[5]],
                       [v[4], v[6], v[7]],
                       [v[5], v[7], v[8]]]
            let stats = DyadPalette.makeStats(
                centroid: OKLabColor(l: v[0], a: v[1], b: v[2]), covariance: cov)
            out.append(DyadPalette.gifColorTable(DyadPalette.table(stats: stats)))
        }
        return out.isEmpty ? nil : out
    }

    static func makeGIF(
        frames: [QuantizedFrame],
        measure: BirkhoffMeasure?,
        method: ExportMethod
    ) -> Data? {
        makeGIF(frames: frames, measure: measure,
                settings: ExportSettings(method: method, bleed: true, mirror: false))
    }

    /// The machine. Every capture export in the app goes through here.
    static func makeGIF(
        frames: [QuantizedFrame],
        measure: BirkhoffMeasure?,
        settings: ExportSettings
    ) -> Data? {
        switch resolve(settings.method, frames: frames) {
        case .dyad:
            // process() can still decline at runtime (defensive); the
            // chain continues exactly as eligibility would have.
            if let dyad = DyadPipeline.process(frames: frames, bleed: settings.bleed),
               let data = GIFEncoder.encode(
                   indexFrames: settings.mirror
                       ? dyad.indexFrames.map { mirrored($0, side: QuantizedFrame.size) }
                       : dyad.indexFrames,
                   side: QuantizedFrame.size,
                   measure: measure, upscale: CameraConfig.exportUpscale,
                   perFrameTables: dyad.tables,
                   trace: dyadTrace(tables: dyad.tables, stats: dyad.stats,
                                    settings: settings)) {
                return data
            }
            var fallback = settings
            fallback.method = .refined
            return makeGIF(frames: frames, measure: measure, settings: fallback)

        case .refined:
            let input = settings.mirror ? mirrorFrames(frames) : frames
            let refined = CentroidRefiner.refineAuto(frames: input)
            return GIFEncoder.encode(
                frames: input, measure: measure,
                upscale: CameraConfig.exportUpscale, refined: refined)

        case .tesseract:
            let input = settings.mirror ? mirrorFrames(frames) : frames
            return GIFEncoder.encode(
                frames: input, measure: measure,
                upscale: CameraConfig.exportUpscale)
        }
    }
}
