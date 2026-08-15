// SettingsView.swift
// Tesseract
//
// The settings surface (fullScreenCover, its own canvas —
// GridLayout.settingsScene). Per the simplicity decree: CAMERA
// (LIVE TrueDepth / FACE mesh) plus the two toggles (BLEED, MIRROR,
// persisted through ExportSettings — the same values GIFMachine
// reads at export time). The LOOK radio is gone: DYAD per-frame
// palettes are the law (Daniel's decree, 2026-08-12), not a choice.

import SwiftUI

struct SettingsView: View {
    @Binding var appMode: ContentView.AppMode
    let modeSwitchAllowed: Bool
    let clock: SurfaceClock
    /// WG3 — enter ARRANGE mode on the widget surface.
    let onArrange: () -> Void
    /// WG4 ★ — the escape hatch. It lives HERE, on a static region,
    /// and never on a movable widget: no arrangement, however bad,
    /// can make reset unreachable, because reset is not in the
    /// arrangement.
    let onResetLayout: () -> Void
    let onClose: () -> Void

    @State private var settings = ExportSettings.load()
    @State private var showLibrary = false

    var body: some View {
        ZStack {
            Color(srgb8: Ink.black).ignoresSafeArea()
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    CellText("SETTINGS", rows: TypeRows.display)
                        .place(GridLayout.setTitle)

                    CellText("CAMERA", rows: TypeRows.label,
                             ink: Color(srgb8: Ink.ledGhost))
                        .place(GridLayout.setModeLabel)
                    modeRow(.live, region: GridLayout.setModeLive)
                        .place(GridLayout.setModeLive)
                    modeRow(.face, region: GridLayout.setModeFace)
                        .place(GridLayout.setModeFace)

                    toggleRow(title: "BLEED", value: settings.bleed,
                              region: GridLayout.toggleBleed) {
                        settings.bleed.toggle(); settings.save()
                    }
                    .place(GridLayout.toggleBleed)
                    toggleRow(title: "MIRROR", value: settings.mirror,
                              region: GridLayout.toggleMirror) {
                        settings.mirror.toggle(); settings.save()
                    }
                    .place(GridLayout.toggleMirror)

                    libraryButton.place(GridLayout.setLibrary)
                    actionRow(title: "ARRANGE", region: GridLayout.setArrange,
                              enabled: true, action: onArrange)
                        .place(GridLayout.setArrange)
                    actionRow(title: "RESET LAYOUT", region: GridLayout.setResetLayout,
                              enabled: true, action: onResetLayout)
                        .place(GridLayout.setResetLayout)

                    CellText("KEPT FOR RE-EDITING", rows: TypeRows.label,
                             ink: Color(srgb8: Ink.ledGhost))
                        .place(GridLayout.setStorageLabel)
                    storageRow.place(GridLayout.setStorage)

                    closeButton.place(GridLayout.setClose)
                }
                .gridCentered(in: geo.size)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView(clock: clock, onClose: { showLibrary = false })
        }
    }

    // ── ★ THE MEMORY, ON THE SURFACE (2026-08-14) ────────────────
    //
    // FORM FOLLOWS FUNCTION. The app's function grew a third phase
    // this session: it CAPTURES, it RETAINS, and it EDITS. Capture
    // and edit both speak on the surface; retention did not, and it
    // is the one that spends the user's storage — about a megabyte a
    // capture, forever, so that a moment stays re-editable. A cost
    // the user pays and cannot see is the same silence the 2026-08-14
    // decree bans in the engine, one layer up: nothing fails, so
    // nothing gets decided.
    //
    // Three numbers, in the same voice the result scene uses, so the
    // block reads as part of the app rather than a diagnostic bolted
    // on: what is held, what one more costs, and how many moments
    // that is. `CubeStore.totalBytes()` already existed for this and
    // had no reader.
    private var storageRow: some View {
        let held = CubeStore.totalBytes()
        let per = CubeStore.bytesPerCapture()
        let moments = per > 0 ? held / per : 0
        return HStack(spacing: Lattice.gif(6)) {
            storageMetric(mib(held), "HELD")
            storageMetric(mib(per), "EACH")
            storageMetric("\(moments)", "MOMENTS")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mib(held)) megabytes kept for re-editing, "
                            + "\(mib(per)) per capture, \(moments) moments")
    }

    private func storageMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: Lattice.pt(1)) {
            CellText(value, rows: TypeRows.label)
            CellText(label, rows: TypeRows.micro, ink: Color(srgb8: Ink.ledGhost))
        }
    }

    private func mib(_ bytes: Int) -> String {
        String(format: "%.1f", Double(bytes) / (1024 * 1024))
    }

    private var libraryButton: some View {
        Button(action: { showLibrary = true }) {
            ZStack {
                ControlFrame(cols: GridLayout.setLibrary.w, rows: GridLayout.setLibrary.h,
                             state: 0, tick: clock.tick, reduceMotion: clock.reduceMotion)
                CellText("LIBRARY", rows: TypeRows.body, ink: Color(srgb8: Ink.ink))
            }
            .frame(width: Lattice.gif(GridLayout.setLibrary.w),
                   height: Lattice.gif(GridLayout.setLibrary.h))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("GIF library")
    }

    /// A plain action row in the settings voice — the same face
    /// algebra as LIBRARY, so the three rows read as one block.
    private func actionRow(title: String, region: GridRegion,
                           enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                ControlFrame(cols: region.w, rows: region.h,
                             state: enabled ? 0 : 3,
                             tick: clock.tick, reduceMotion: clock.reduceMotion)
                CellText(title, rows: TypeRows.body,
                         ink: Color(srgb8: enabled ? Ink.ink : Ink.ledGhost))
            }
            .frame(width: Lattice.gif(region.w), height: Lattice.gif(region.h))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }

    // MARK: - Rows (the mode-pill vocabulary: accent ring = selected)

    private func selectionRing(_ region: GridRegion, selected: Bool, enabled: Bool) -> some View {
        Group {
            if selected {
                CellSprite(cols: region.w, rows: region.h, cellPt: Lattice.gifPx) { c, r in
                    (c == 0 || c == region.w - 1 || r == 0 || r == region.h - 1)
                        ? Ink.accent : nil
                }
            } else {
                ControlFrame(cols: region.w, rows: region.h,
                             state: enabled ? 0 : 3,
                             tick: clock.tick, reduceMotion: clock.reduceMotion)
            }
        }
    }

    private func modeRow(_ mode: ContentView.AppMode, region: GridRegion) -> some View {
        let selected = mode == appMode
        return Button {
            guard mode != appMode, modeSwitchAllowed else { return }
            appMode = mode
        } label: {
            ZStack {
                selectionRing(region, selected: selected, enabled: modeSwitchAllowed)
                CellText(mode.rawValue, rows: TypeRows.body,
                         ink: Color(srgb8: selected ? Ink.ink : Ink.ledGhost))
            }
            .frame(width: Lattice.gif(region.w), height: Lattice.gif(region.h))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!modeSwitchAllowed)
        .accessibilityLabel("\(mode.rawValue) camera")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleRow(title: String, value: Bool, region: GridRegion,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                ControlFrame(cols: region.w, rows: region.h, state: 0,
                             tick: clock.tick, reduceMotion: clock.reduceMotion)
                CellText("\(title) \(value ? "ON" : "OFF")", rows: TypeRows.body,
                         ink: Color(srgb8: value ? Ink.ink : Ink.ledGhost))
            }
            .frame(width: Lattice.gif(region.w), height: Lattice.gif(region.h))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(value ? "on" : "off")")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            ZStack {
                ControlFrame(cols: GridLayout.setClose.w, rows: GridLayout.setClose.h,
                             state: 0, tick: clock.tick, reduceMotion: clock.reduceMotion)
                CellText("DONE", rows: TypeRows.body, ink: Color(srgb8: Ink.ink))
            }
            .frame(width: Lattice.gif(GridLayout.setClose.w),
                   height: Lattice.gif(GridLayout.setClose.h))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
    }
}
