// LivePreviewStateView.swift
// Tesseract
//
// CameraState.previewing — the main surface. Every widget occupies a
// proven GridRegion (GridLayout.captureScene) placed on the 100×218
// atom grid; the preview widget is EXACTLY the GIF (64 cells = 64
// pixels at 1 atom each). No hand positioning, no raw numbers, no
// alpha — all chrome is opaque ink (CellMechanics).

import SwiftUI
import simd

struct LivePreviewStateView: View {
    @ObservedObject var camera: CameraManager
    let clock: SurfaceClock
    let onSettings: () -> Void

    // SIMPLICITY DECREE (2026-08-09): the surface is the preview, the
    // shutter, and the settings button — nothing else. The richer
    // widgets (gauge/channels/info/palette) survive below, unplaced.
    var body: some View {
        ZStack(alignment: .topLeading) {
            quantizedPreview.place(GridLayout.preview)
            recordButton.place(GridLayout.record)
            settingsButton.place(GridLayout.settingsButton)
        }
    }

    private var settingsButton: some View {
        Button(action: onSettings) {
            ZStack {
                ControlFrame(cols: GridLayout.settingsButton.w,
                             rows: GridLayout.settingsButton.h,
                             state: 0, tick: clock.tick,
                             reduceMotion: clock.reduceMotion)
                CellText("SET", rows: TypeRows.body,
                         ink: Color(srgb8: Ink.ledGhost))
            }
            .frame(width: Lattice.gif(GridLayout.settingsButton.w),
                   height: Lattice.gif(GridLayout.settingsButton.h))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    // MARK: - Quantized Preview (64 cells = the 64×64 GIF at 1 atom/px)

    private var quantizedPreview: some View {
        Group {
            if let cgImage = camera.previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)  // nearest neighbor — pixel-perfect
                    .resizable()
                    .frame(width: Lattice.gif(TesseractLattice.previewCells),
                           height: Lattice.gif(TesseractLattice.previewCells))
            } else {
                ZStack {
                    Color(srgb8: CellChecker.dark)
                    CellText("64 × 64", rows: TypeRows.label,
                             ink: Color(srgb8: Ink.ledGhost))
                }
                .frame(width: Lattice.gif(TesseractLattice.previewCells),
                       height: Lattice.gif(TesseractLattice.previewCells))
            }
        }
        .pixelFrame()
    }

    // MARK: - Record Button (BEAT ring; footprint = TesseractLattice.recordCells)

    // The ring band is the control's FACE: ghost between beats, lit ink
    // for 1 tick in 4 (CellMechanics BEAT) — suppressed under
    // reduce-motion by evaluating at tick 1 (provably beat-free).
    private var recordButton: some View {
        let treatment = CellMechanics.faceTreatment(
            state: 0, tick: clock.reduceMotion ? 1 : clock.tick)
        return Button(action: { camera.startRecording() }) {
            CellButton(state: .idle,
                       ringInk: treatment == 1 ? Ink.ink : Ink.ledGhost)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Record 64 frames")
    }
}
