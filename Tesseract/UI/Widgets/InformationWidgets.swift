// InformationWidgets.swift
// Tesseract
//
// PORT of the four instruments Daniel named, as they are declared in
// spec/ui/WidgetGrid.hs (WG1, WG8, WG12) — Preview64, Palette, Timer,
// FramesBar. The Haskell is authoritative; this is a port and may not
// improve on it.
//
// Daniel (2026-08-13): "when the user opens the app and camera they
// should see the preview but also a 16x16 for the color palette of
// that frame, a timer, a bar to show how close it is to the 64 frame
// limit. INFORMATION! we need to surface!"
//
// ── PLACEMENT ───────────────────────────────────────────────────
// Every widget below is EXACTLY its spec footprint in atoms and does
// no positioning of its own. The caller places it through the one
// sanctioned door — View.place(_:) on a proven GridRegion (WG1: a
// placement determines the exact region; scripts/lint-grid.sh
// LINT-PLACEMENT). Nothing in this file constructs a GridRegion or
// touches .position/.offset; the lattice files own that math and
// Arrangement.swift owns the runtime placement that feeds it. Sizes
// are read from the ONE footprint table, `Widget.spec` — a widget
// that restated its own size would drift from the arrangement that
// places it.
//
// ── EMPTY IS A STATE, NOT A HOLE ────────────────────────────────
// Before the first solve closes, DyadPipeline.Live.table is EMPTY
// (DyadPipeline.swift:806 — "empty until the first solve") and the
// capture clock reads zero. Each widget renders its own no-evidence
// face — the 2×2 checker for the palette, the void square for the
// preview, ghost ink for the readouts — so a waking surface shows an
// instrument, never a blank rectangle and never a crash.
//
// All colour is opaque ink (Ink / CellChecker); all drawing goes
// through the cell vocabulary (CellSprite / CellText / pixelFrame).

import SwiftUI
import simd

// ════════════════════════════════════════════════════════════════
// § 1. THE READOUTS (pure — everything the tests can hold)
// ════════════════════════════════════════════════════════════════

/// The palette instrument's arithmetic: cells ↔ palette entries.
enum PaletteReadout {

    /// 16 — the coarse rung's side (FeedFormat.Rung, the resolution of
    /// depth, TL9). NOT a chosen number: WG12 pins
    /// `footprint Palette == footprint Preview16`, and 16 × 16 = 256 =
    /// `CameraConfig.paletteSize` is the bijection — the 16×16 IS the
    /// 256 entries, not a picture of them.
    static let side = Rung.coarse.side

    /// 256. Equal to CameraConfig.paletteSize by the bijection above.
    static var entryCount: Int { side * side }

    /// Row-major by palette index — the same order CellPalette draws
    /// and the DYAD table is written in, so the structure reads
    /// directly: primaries fill the top half (the PairTree leaves),
    /// Wada grounds mirror them in the bottom half, T[255−i].
    ///
    /// This map is a BIJECTION cells → entries. Do NOT resample it: a
    /// resampled palette is a different instrument that answers a
    /// different question.
    static func index(col: Int, row: Int) -> Int { row * side + col }

    /// True once the live driver has published a whole table.
    static func isComplete(_ table: [(UInt8, UInt8, UInt8)]) -> Bool {
        table.count >= entryCount
    }

    /// The managers publish the table as the encoder writes it — 768
    /// bytes, RGB triples, exactly the GIF color-table packing
    /// (`CellPalette` consumes the same shape). This is the ONE
    /// unpacking; a short or absent buffer yields the empty table, and
    /// every widget below already renders "not yet solved" for that.
    static func entries(_ data: Data?) -> [(UInt8, UInt8, UInt8)] {
        guard let data, data.count >= entryCount * 3 else { return [] }
        var out = [(UInt8, UInt8, UInt8)]()
        out.reserveCapacity(entryCount)
        for i in 0..<entryCount {
            let o = data.startIndex + i * 3
            out.append((data[o], data[o + 1], data[o + 2]))
        }
        return out
    }

    /// The ink for one cell. An entry the solve has not produced yet
    /// wears the 2×2 checker — the app's existing "no evidence"
    /// texture (CellChecker, opaque, never alpha), so the widget is
    /// visibly an unsolved palette rather than a dead square.
    static func ink(_ table: [(UInt8, UInt8, UInt8)],
                    col: Int, row: Int, phase: Int = 0) -> SIMD3<UInt8> {
        let i = index(col: col, row: row)
        guard i >= 0, i < table.count else {
            return CellChecker.ink(col, row, phase: phase,
                                   lit: Ink.ledGhost, ghost: CellChecker.dark)
        }
        let e = table[i]
        return SIMD3(e.0, e.1, e.2)
    }
}

/// The timer instrument's arithmetic — a CAPTURE clock, not a wall
/// clock. Elapsed is frames ÷ fps, the exact expression
/// RecordingStateView already uses; there is no second Timer, because
/// SurfaceClock is the only tick source allowed to move the chrome.
enum TimerReadout {

    /// Elapsed seconds for a capture frame index. Negative frames read
    /// zero — the clock cannot run backwards before WEAVING starts.
    static func seconds(frame: Int) -> Double {
        Double(max(0, frame)) / Double(CameraConfig.targetFPS)
    }

    /// One decimal digit, DERIVED not chosen: at CameraConfig.targetFPS
    /// = 20 a frame is 0.05 s, so hundredths would change on every
    /// frame (a flicker, not a reading) while whole seconds would take
    /// only four values across the entire 64-frame weave. Tenths is the
    /// coarsest digit that still moves during a capture.
    static func text(frame: Int) -> String {
        String(format: "%.1fs", seconds(frame: frame))
    }
}

/// The frame-limit bar's arithmetic.
enum FrameBarReadout {

    /// 64 cells wide — read from the ONE footprint table
    /// (`Widget.framesBar.spec`, itself pinned to
    /// TesseractLattice.previewCells). The strip spans the GIF exactly,
    /// so the bar reads as "this many of those pixels".
    static let cols = Widget.framesBar.spec.w

    /// 2 rows — the height half of the same table row (Widget.stripRows).
    static let rows = Widget.framesBar.spec.h

    /// Lit cells, TOTAL and CLAMPED: out-of-range frames, an empty
    /// capture (total ≤ 0) and a degenerate bar (cols ≤ 0) all answer
    /// with a number in 0...cols rather than trapping.
    ///
    /// Because the export cube is 64 frames (CameraConfig.totalFrames)
    /// and the bar is 64 cells, one lit cell is exactly one frame: the
    /// bar shows the 64-frame limit at 1:1, not a percentage of it.
    static func lit(frame: Int,
                    total: Int = CameraConfig.totalFrames,
                    cols: Int = FrameBarReadout.cols) -> Int {
        guard total > 0, cols > 0 else { return 0 }
        let f = min(max(0, frame), total)
        let cells = (Double(f) / Double(total) * Double(cols)).rounded()
        return min(cols, max(0, Int(cells)))
    }
}

// ════════════════════════════════════════════════════════════════
// § 2. THE WIDGETS
// ════════════════════════════════════════════════════════════════

/// Preview64 — the live surface at one atom per GIF pixel (L5: the
/// preview widget IS the GIF, 64 cells = 64 pixels = 256 pt).
struct PreviewWidget: View {

    /// WG1 — read from the ONE footprint table (`Widget.spec`), never
    /// restated: spec/ui/WidgetGrid.hs `footprint Preview64 = (64,64)`.
    static let footprint = Widget.preview64.spec

    /// The quantized live frame — CameraManager.previewImage /
    /// FaceCaptureManager.previewImage. nil until the first frame.
    let image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1.0)
                    .interpolation(.none)   // nearest neighbour — no AA on content
                    .resizable()
                    .frame(width: Lattice.gif(Self.footprint.w),
                           height: Lattice.gif(Self.footprint.h))
            } else {
                // WAKING: the instrument states its own shape rather
                // than showing a hole.
                ZStack {
                    Color(srgb8: Ink.void)
                    CellText("\(Self.footprint.w) × \(Self.footprint.h)",
                             rows: TypeRows.label,
                             ink: Color(srgb8: Ink.ledGhost))
                }
                .frame(width: Lattice.gif(Self.footprint.w),
                       height: Lattice.gif(Self.footprint.h))
            }
        }
        .pixelFrame()
        .accessibilityLabel(image == nil
            ? "Live preview, waking"
            : "Live preview, \(Self.footprint.w) by \(Self.footprint.h)")
    }
}

/// Palette — THIS frame's 256 entries as a 16×16 block of atoms, one
/// atom per entry (WG12: `footprint Palette == footprint Preview16`).
///
/// This is also the monochrome diagnostic: the shipped GIF measured
/// 48 of 63 consecutive tables byte-identical and 164 of 256 entries
/// used, with circular hue concentration R = 0.9913. With the table on
/// screen during WATCHING that pathology is visible live, before the
/// shutter, at the rung-16 solve cadence — no new math required.
struct PaletteWidget: View {

    /// WG1 — from the one table: `footprint Palette = (16, 16)`.
    static let footprint = Widget.palette.spec

    /// DyadPipeline.Live.table — the 256 entries the surface is
    /// actually drawing indices with. EMPTY until the first solve.
    let table: [(UInt8, UInt8, UInt8)]

    /// SurfaceClock.heartbeat, so the not-yet-solved checker shimmers
    /// on the app's one clock. 0 = a static checker.
    var phase: Int = 0

    var body: some View {
        CellSprite(cols: Self.footprint.w,
                   rows: Self.footprint.h,
                   cellPt: Lattice.gifPx) { c, r in
            PaletteReadout.ink(table, col: c, row: r, phase: phase)
        }
        .accessibilityLabel(PaletteReadout.isComplete(table)
            ? "Color palette, \(PaletteReadout.entryCount) entries"
            : "Color palette, solving")
    }
}

/// Timer — elapsed capture time in the app's digit idiom (CellText,
/// rasterized AA-off at cell resolution).
struct TimerWidget: View {

    /// WG1 — from the one table: `footprint Timer = (20, 7)`, the
    /// readout register Timer/Counter/EnergyRead share.
    static let footprint = Widget.timer.spec

    /// The capture frame index — CameraState.recording(frame). Zero
    /// outside WEAVING, which reads "0.0s": the clock is honest about
    /// not running.
    let frame: Int

    /// The register the raster-fit test pins: "3.2s" at counter is
    /// 22 pt tall in a 28 pt region and well inside 80 pt of width.
    static let register = TypeRows.counter

    var body: some View {
        CellText(TimerReadout.text(frame: frame),
                 rows: Self.register,
                 ink: Color(srgb8: frame > 0 ? Ink.ink : Ink.ledGhost))
            .accessibilityLabel("Elapsed \(TimerReadout.text(frame: frame))")
    }
}

/// FramesBar — how close the weave is to the 64-frame limit, as lit
/// atoms. One cell per frame; no ProgressView, no alpha.
struct FrameBarWidget: View {

    /// WG1 — from the one table: `footprint FramesBar = (64, 2)`.
    static let footprint = Widget.framesBar.spec

    let frame: Int
    var total: Int = CameraConfig.totalFrames

    var body: some View {
        let lit = FrameBarReadout.lit(frame: frame, total: total,
                                      cols: Self.footprint.w)
        return CellSprite(cols: Self.footprint.w,
                          rows: Self.footprint.h,
                          cellPt: Lattice.gifPx) { c, _ in
            c < lit ? Ink.ink : Ink.ledGhost
        }
        .accessibilityLabel("Frame \(min(max(0, frame), max(0, total))) of \(total)")
    }
}
