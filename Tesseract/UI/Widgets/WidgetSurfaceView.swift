// WidgetSurfaceView.swift
// Tesseract
//
// PORT of spec/ui/WidgetGrid.hs (WG1–WG12) — the surface itself. The
// Haskell is authoritative; this is a port and may not improve on it.
//
// ★ A SCENE STOPS BEING A LAYOUT AND BECOMES A WIDGET SET (Daniel,
// 2026-08-13: "INFORMATION! we need to surface!"). WHERE each
// instrument sits is DATA the user owns: twelve (col,row) pairs held
// in one `Arrangement`, persisted through `ArrangementStore`, reset
// from a STATIC region on the settings cover. This view replaces
// GridLayout.captureScene as the WATCHING surface.
//
// ── HOW THIS SATISFIES scripts/lint-grid.sh (never bypasses it) ──
//
//  LINT-PLACEMENT      no hand positioning appears here at all.
//                      Every widget places through the ONE sanctioned
//                      primitive, `View.place(_:)`, on a GridRegion.
//                      A DRAG NEVER MOVES A VIEW: the finger
//                      translation is quantized to integer cells by
//                      `Lattice.cells(_:)` (WG8 — dragging IS
//                      snapping), handed to `Arrangement.moving`,
//                      and the widget re-`place()`s from the value
//                      that returns. There is no off-lattice frame to
//                      express, so the runtime arrangement changes
//                      the region's VALUE, never the path.
//  LINT-REGION-SOURCE  no region is CONSTRUCTED here. The candidate
//                      region during a drag comes from
//                      `Arrangement.region(for:)` on the CANDIDATE
//                      arrangement — the only region producer — so a
//                      view cannot mint a rectangle and launder hand
//                      positioning past the lint.
//  LINT-CONTROL-FACE   the three interactive widgets declare their
//                      faces in `CellMechanics.controlFaces` under the
//                      names `Widget`'s raw values give them; the
//                      lint scans Arrangement.swift's `WidgetSpec`
//                      rows with the same regex it uses on
//                      GridLayout's `GridRegion` rows.
//  LINT-DRAW-VOCAB     this file is in GOVERNED_VOCAB from its first
//                      line: cell vocabulary only (CellSprite,
//                      CellText, CellPalette, CellButton,
//                      ControlFrame) — no alpha, no AA shapes, no
//                      bare Text.
//
// ── WG10: OCCLUSION IS UNREPRESENTABLE ──────────────────────────
// One ZStack, one `.place()` per widget, no zIndex anywhere. During a
// drag the COMMITTED arrangement is untouched and the dragged widget
// only ever renders at a LAWFUL candidate (WG3: `moving` returns nil
// for anything else, and nil IS the refusal) — so nothing overlaps at
// any instant of the gesture, not merely at its end.

import SwiftUI
import simd

// ════════════════════════════════════════════════════════════════
// § 1. SCENE SETS — a scene is a SET of widgets, not a layout
// ════════════════════════════════════════════════════════════════

enum WidgetScene {

    /// Which instruments a machine state surfaces. Placement always
    /// comes from the ONE global arrangement, so every scene inherits
    /// the whole arrangement's lawfulness proof (WG2 is a conjunction
    /// over pairs, so a subset of a lawful arrangement is lawful).
    static func widgets(for state: EditMachine.State) -> Set<Widget> {
        switch state {
        case .watching:
            // ★ EM2's first loop: the live read at all three rungs,
            // every instrument on screen, everything movable.
            return Set(Widget.allCases)
        case .weaving:
            // EM4: work is sacred — the controls leave, the readouts
            // stay, so the frame limit is visible while it fills.
            return Set(Widget.allCases).subtracting([.shutter, .setButton, .shelfButton])
        case .solving:
            // EM6/SM5: SOLVING shows the palette being born.
            return [.preview64, .palette, .framesBar, .phaseStrip, .energyRead]
        default:
            return []
        }
    }
}

// ════════════════════════════════════════════════════════════════
// § 2. THE SURFACE
// ════════════════════════════════════════════════════════════════

struct WidgetSurfaceView: View {

    // ── What the managers supply (LIVE and FACE alike) ──
    let state: EditMachine.State
    let previewImage: CGImage?
    let midImage: CGImage?
    let coarseImage: CGImage?
    /// 768 bytes — the table the surface is drawing indices with.
    let paletteData: Data?
    /// The capture frame index; 0 outside WEAVING (the clock is
    /// honest about not running).
    let frame: Int
    let clock: SurfaceClock

    // ── The arrangement the user owns ──
    @Binding var arrangement: Arrangement
    @Binding var arranging: Bool

    // ── Actions ──
    let onShutter: () -> Void
    let onSettings: () -> Void
    let onShelf: () -> Void

    /// The widget under the finger, and how far it has travelled.
    /// Nothing is committed until the gesture ends.
    @State private var dragged: Widget?
    @State private var translation: CGSize = .zero

    private var visible: [Widget] {
        let set = WidgetScene.widgets(for: state)
        return Widget.allCases.filter { set.contains($0) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visible, id: \.self) { w in
                hosted(w)
            }
        }
    }

    // ── Placement (WG1/WG3/WG8) ─────────────────────────────────

    /// The arrangement this widget would land in if the finger lifted
    /// now — or nil if that placement is unlawful (WG3: nil IS the
    /// refusal). `Lattice.cells` is the only points→cells door, so the
    /// candidate is always on the lattice (WG8).
    private func candidate(_ w: Widget) -> Arrangement? {
        guard dragged == w else { return nil }
        let base = arrangement.placement(of: w)
        let p = Placement(col: base.col + Lattice.cells(translation.width),
                          row: base.row + Lattice.cells(translation.height))
        guard p != base else { return nil }
        return arrangement.moving(w, to: p)
    }

    /// WG1 — the region this widget renders in right now. Committed
    /// placement, unless a LAWFUL candidate is under the finger.
    private func liveRegion(_ w: Widget) -> GridRegion {
        (candidate(w) ?? arrangement).region(for: w)
    }

    /// True while the finger holds an ILLEGAL placement: the widget
    /// stays put and wears reject ink, so the refusal is seen rather
    /// than merely enforced.
    private func refusing(_ w: Widget) -> Bool {
        guard dragged == w else { return false }
        let base = arrangement.placement(of: w)
        let p = Placement(col: base.col + Lattice.cells(translation.width),
                          row: base.row + Lattice.cells(translation.height))
        return p != base && arrangement.moving(w, to: p) == nil
    }

    @ViewBuilder
    private func hosted(_ w: Widget) -> some View {
        let region = liveRegion(w)
        if arranging {
            arrangeFace(w)
                .contentShape(Rectangle())
                .gesture(dragGesture(w))
                .place(region)
        } else {
            widgetBody(w)
                .place(region)
        }
    }

    // ── ARRANGE mode (WG3/WG8) ──────────────────────────────────

    /// In ARRANGE mode every widget wears a control frame at exactly
    /// its own footprint — the instrument states its grabbable extent
    /// in atoms, and the frame IS the region, so nothing overlaps.
    private func arrangeFace(_ w: Widget) -> some View {
        let spec = w.spec
        return ZStack {
            widgetBody(w)
            if refusing(w) {
                CellSprite(cols: spec.w, rows: spec.h, cellPt: Lattice.gifPx) { c, r in
                    (c == 0 || c == spec.w - 1 || r == 0 || r == spec.h - 1)
                        ? Ink.reject : nil
                }
            } else {
                ControlFrame(cols: spec.w, rows: spec.h, state: 0,
                             tick: clock.tick, reduceMotion: clock.reduceMotion)
            }
        }
        .frame(width: Lattice.gif(spec.w), height: Lattice.gif(spec.h))
        .accessibilityLabel("\(w.rawValue), arranging")
    }

    /// WG8 ★ — the whole mutation API is `Arrangement.moving`. The
    /// gesture writes NOTHING until it ends, and a refused move writes
    /// nothing at all: storage can only ever hold arrangements that
    /// passed the same proof the static scenes pass at launch.
    ///
    /// A gesture that never left its own atom is a TAP: it is how
    /// ARRANGE mode is left, and it needs no extra region (a static
    /// DONE control could not be proven disjoint from a runtime
    /// arrangement, which is precisely what WG10 forbids).
    private func dragGesture(_ w: Widget) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragged = w
                translation = value.translation
            }
            .onEnded { value in
                let moved = Lattice.cells(value.translation.width) != 0
                    || Lattice.cells(value.translation.height) != 0
                if moved {
                    let base = arrangement.placement(of: w)
                    let p = Placement(
                        col: base.col + Lattice.cells(value.translation.width),
                        row: base.row + Lattice.cells(value.translation.height))
                    if let next = arrangement.moving(w, to: p) {
                        arrangement = next
                        ArrangementStore.save(next)
                    }
                } else {
                    arranging = false
                }
                dragged = nil
                translation = .zero
            }
    }

    // ════════════════════════════════════════════════════════════
    // § 3. THE TWELVE (WG6 — the vocabulary is CLOSED)
    // ════════════════════════════════════════════════════════════

    @ViewBuilder
    private func widgetBody(_ w: Widget) -> some View {
        switch w {
        case .preview64:
            PreviewWidget(image: previewImage)
        case .preview32:
            RungPreviewWidget(image: midImage, widget: .preview32)
        case .preview16:
            RungPreviewWidget(image: coarseImage, widget: .preview16)
        case .palette:
            PaletteWidget(table: PaletteReadout.entries(paletteData),
                          phase: clock.heartbeat)
        case .timer:
            TimerWidget(frame: frame)
        case .counter:
            CounterWidget(frame: frame)
        case .framesBar:
            FrameBarWidget(frame: frame)
        case .phaseStrip:
            PhaseStripWidget()
        case .energyRead:
            EnergyReadWidget(table: paletteData)
        case .shutter:
            shutter
        case .setButton:
            chrome(.setButton, title: arranging ? "DONE" : "SET", action: onSettings)
        case .shelfButton:
            chrome(.shelfButton, title: "SHELF", action: onShelf)
        }
    }

    /// The shutter — the lattice's own 22×22 footprint with the BEAT
    /// ring (CellMechanics), unchanged from the surface it replaces.
    private var shutter: some View {
        let treatment = CellMechanics.faceTreatment(
            state: 0, tick: clock.reduceMotion ? 1 : clock.tick)
        return Group {
            if arranging {
                CellButton(state: .disabled)
            } else {
                Button(action: onShutter) {
                    CellButton(state: .idle,
                               ringInk: treatment == 1 ? Ink.ink : Ink.ledGhost)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .accessibilityLabel("Record \(CameraConfig.totalFrames) frames")
    }

    /// SET and SHELF — the two chrome controls, same face algebra.
    @ViewBuilder
    private func chrome(_ w: Widget, title: String,
                        action: @escaping () -> Void) -> some View {
        let spec = w.spec
        let face = ZStack {
            ControlFrame(cols: spec.w, rows: spec.h, state: 0,
                         tick: clock.tick, reduceMotion: clock.reduceMotion)
            CellText(title, rows: TypeRows.body, ink: Color(srgb8: Ink.ledGhost))
        }
        .frame(width: Lattice.gif(spec.w), height: Lattice.gif(spec.h))
        if arranging {
            face
        } else {
            Button(action: action) {
                face.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
        }
    }
}

// ════════════════════════════════════════════════════════════════
// § 4. THE INSTRUMENTS THIS FILE ADDS
//
// Preview64, Palette, Timer and FramesBar live in
// InformationWidgets.swift (the four Daniel named). These are the
// remaining rows of the same WG1 footprint table — each reads its
// size from `Widget.spec` and does no positioning of its own.
// ════════════════════════════════════════════════════════════════

/// WG12 ★ — the 32³ and 16³ windows on the SAME render. The image is
/// the pooled FEED re-assigned by the export's own law
/// (`DyadPipeline.Live.coarseReads`), never a resample of the fine
/// picture: pooling indices is not a linear operation, and
/// point-sampling one would inject the aliasing the ladder exists to
/// remove. All three windows therefore agree (OV4: pool ∘ up = id).
struct RungPreviewWidget: View {
    let image: CGImage?
    let widget: Widget

    var body: some View {
        let spec = widget.spec
        return Group {
            if let image {
                Image(decorative: image, scale: 1.0)
                    .interpolation(.none)   // nearest neighbour — one atom per cell
                    .resizable()
                    .frame(width: Lattice.gif(spec.w), height: Lattice.gif(spec.h))
            } else {
                // The read has not landed yet: the instrument states
                // its own shape (the void square), never a hole.
                Color(srgb8: Ink.void)
                    .frame(width: Lattice.gif(spec.w), height: Lattice.gif(spec.h))
            }
        }
        .pixelFrame()
        .accessibilityLabel("Rung \(spec.w) read")
    }
}

/// Counter — n / 64, the frame budget as a number beside the bar.
///
/// The string is `"n/64"` and NOT `"n / 64"`: at `TypeRows.counter`
/// the spaced form rasterises ≈ 92 pt of ink against an 80 pt region
/// (20 cells) and overflows. The unspaced form is 5 characters
/// ≈ 66 pt. The raster-fit test is what settles this, not an
/// estimate.
struct CounterWidget: View {
    static let footprint = Widget.counter.spec
    let frame: Int
    var total: Int = CameraConfig.totalFrames

    static func text(frame: Int, total: Int = CameraConfig.totalFrames) -> String {
        "\(min(max(0, frame), max(0, total)))/\(total)"
    }

    var body: some View {
        CellText(Self.text(frame: frame, total: total),
                 rows: TypeRows.counter,
                 ink: Color(srgb8: frame > 0 ? Ink.ink : Ink.ledGhost))
            .accessibilityLabel("Frame \(min(max(0, frame), max(0, total))) of \(total)")
    }
}

/// EnergyRead — the palette's own ΔE² density (DyadEnergy.palette),
/// the phase-diagram readout. `TypeRows.label`, not `.counter`: the
/// eight-character reading overflows 80 pt at the counter register.
struct EnergyReadWidget: View {
    static let footprint = Widget.energyRead.spec
    /// The 768-byte live table.
    let table: Data?

    static func text(_ table: Data?) -> String {
        let entries = PaletteReadout.entries(table)
        guard PaletteReadout.isComplete(entries) else { return "ΔE ----" }
        return String(format: "ΔE %.3f", DyadEnergy.palette(table: entries))
    }

    var body: some View {
        let entries = PaletteReadout.entries(table)
        return CellText(Self.text(table), rows: TypeRows.label,
                        ink: Color(srgb8: PaletteReadout.isComplete(entries)
                                   ? Ink.ink : Ink.ledGhost))
            .accessibilityLabel("Palette energy \(Self.text(table))")
    }
}

/// PhaseStrip — FACE / BAND / SOLID tile composition.
///
/// ⚠ NOT YET FED. The composition is a function of the live solve's
/// role posterior (`DepthMixture` t over the rung-16 cells), and
/// neither manager publishes it: the contract's `LiveComposition`
/// (face/band/solid summing to 1) is unwritten. Rather than invent a
/// number — which would be a naked constant wearing a widget's
/// clothes — the strip renders its own no-evidence face, exactly as
/// the palette does before the first solve. WG5 requires all twelve
/// to be PLACED; it does not require this one to lie.
struct PhaseStripWidget: View {
    static let footprint = Widget.phaseStrip.spec
    /// face / band / solid, each in 0...1 and summing to ≤ 1. Empty
    /// (the default) is the no-evidence state.
    var composition: (face: Double, band: Double, solid: Double)?

    var body: some View {
        let spec = Self.footprint
        return CellSprite(cols: spec.w, rows: spec.h, cellPt: Lattice.gifPx) { c, _ in
            guard let composition else { return Ink.ledGhost }
            let faceCells = Int((composition.face * Double(spec.w)).rounded())
            let bandCells = Int((composition.band * Double(spec.w)).rounded())
            if c < faceCells { return Ink.ink }
            if c < faceCells + bandCells { return Ink.accent }
            return Ink.ledGhost
        }
        .accessibilityLabel(composition == nil
            ? "Phase composition, not yet published"
            : "Phase composition")
    }
}
