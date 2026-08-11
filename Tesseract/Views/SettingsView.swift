// SettingsView.swift
// Tesseract
//
// The settings surface (fullScreenCover, its own canvas —
// GridLayout.settingsScene). Two groups, per the simplicity decree:
// CAMERA (LIVE TrueDepth / FACE mesh) and LOOK (the 64³ machine's
// methods, radio, persisted through ExportSettings — the same value
// GIFMachine reads at export time).

import SwiftUI

struct SettingsView: View {
    @Binding var appMode: ContentView.AppMode
    let modeSwitchAllowed: Bool
    let clock: SurfaceClock
    let onClose: () -> Void

    @State private var settings = ExportSettings.load()
    @State private var showLibrary = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
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

                    CellText("LOOK", rows: TypeRows.label,
                             ink: Color(srgb8: Ink.ledGhost))
                        .place(GridLayout.setLookLabel)
                    lookRow(.dyad, title: "DYAD", region: GridLayout.lookDyad)
                        .place(GridLayout.lookDyad)
                    lookRow(.refined, title: "REFINE", region: GridLayout.lookRefine)
                        .place(GridLayout.lookRefine)
                    lookRow(.tesseract, title: "TESS", region: GridLayout.lookTess)
                        .place(GridLayout.lookTess)

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

    private func lookRow(_ look: ExportMethod, title: String, region: GridRegion) -> some View {
        let selected = look == settings.method
        return Button {
            settings.method = look
            settings.save()
        } label: {
            ZStack {
                selectionRing(region, selected: selected, enabled: true)
                CellText(title, rows: TypeRows.body,
                         ink: Color(srgb8: selected ? Ink.ink : Ink.ledGhost))
            }
            .frame(width: Lattice.gif(region.w), height: Lattice.gif(region.h))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) look")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
