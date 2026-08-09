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
                CellText("SET", rows: TypeRows.label,
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

    // MARK: - R, G, B, D Channel Previews (4 × 12 cells + 3 × 2-cell gutters = 54)

    private var channelPreviews: some View {
        HStack(spacing: Lattice.gif(2)) {
            channelThumb(image: camera.previewR, label: "R", tint: Ink.chanR)
            channelThumb(image: camera.previewG, label: "G", tint: Ink.chanG)
            channelThumb(image: camera.previewB, label: "B", tint: Ink.chanB)
            channelThumb(image: camera.previewD, label: "D", tint: Ink.chanD)
        }
    }

    private func channelThumb(image: CGImage?, label: String, tint: SIMD3<UInt8>) -> some View {
        VStack(spacing: Lattice.pt(1)) {
            Group {
                if let img = image {
                    Image(decorative: img, scale: 1.0)
                        .interpolation(.none)
                        .resizable()
                } else {
                    Color(srgb8: CellChecker.dark)
                }
            }
            .frame(width: Lattice.gif(TesseractLattice.channelCells),
                   height: Lattice.gif(TesseractLattice.channelCells))
            .border(Color(srgb8: tint), width: 1)

            CellText(label, rows: TypeRows.micro, ink: Color(srgb8: tint))
        }
    }

    // MARK: - Capture Info

    private var captureInfoLine: some View {
        let mode = CameraConfig.mode
        let step = CameraConfig.rgbCrop / mode.spatialSide
        return CellText(
            "\(mode.frameCount) frames  \(String(format: "%.1f", Double(mode.frameCount) / Double(CameraConfig.targetFPS)))s  \(step * step) px/blk",
            rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost)
        )
    }

    // MARK: - Record Button (18-cell footprint, 14-cell disc, BEAT ring)

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
