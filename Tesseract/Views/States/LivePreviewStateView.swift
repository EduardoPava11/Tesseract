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

    var body: some View {
        ZStack(alignment: .topLeading) {
            birkhoffGauge.place(GridLayout.gauge)
            quantizedPreview.place(GridLayout.preview)
            channelPreviews.place(GridLayout.channels)
            captureInfoLine.place(GridLayout.captureInfo)
            PaletteSwatchView().place(GridLayout.palette)
            recordButton.place(GridLayout.record)
        }
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

    // MARK: - Birkhoff Beauty Gauge (M = O / C, the spec quantity)

    private var birkhoffGauge: some View {
        VStack(spacing: Lattice.pt(2)) {
            if let m = camera.previewMeasure {
                HStack(spacing: Lattice.gif(2)) {
                    CellText("M", rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
                    beautyMeter(normalized: min(1, Double(m.beauty) / 600))
                    CellText(String(format: "%.0f", m.beauty), rows: TypeRows.label)
                }
                HStack(spacing: Lattice.gif(4)) {
                    metricLabel("O", String(format: "%.0f", m.order))
                    metricLabel("C", String(format: "%.2f", m.complexity))
                    metricLabel("dim", String(format: "%.1f", m.manifoldDim))
                    metricLabel("col", "\(m.colorsUsed)")
                }
            } else {
                CellText("M = O / C", rows: TypeRows.label,
                         ink: Color(srgb8: Ink.ledGhost))
            }
        }
    }

    // 30-atom lit-cells meter — the alpha gradient bar, now opaque ink.
    private func beautyMeter(normalized: Double) -> some View {
        let lit = max(0, min(30, Int((normalized * 30).rounded())))
        return CellSprite(cols: 30, rows: 1, cellPt: Lattice.gifPx) { c, _ in
            c < lit ? Ink.ink : Ink.ledGhost
        }
        .accessibilityHidden(true)
    }

    private func metricLabel(_ label: String, _ value: String) -> some View {
        VStack(spacing: Lattice.pt(1)) {
            CellText(value, rows: TypeRows.label)
            CellText(label, rows: TypeRows.micro, ink: Color(srgb8: Ink.ledGhost))
        }
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
