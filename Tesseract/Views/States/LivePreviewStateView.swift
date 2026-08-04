// LivePreviewStateView.swift
// Tesseract
//
// CameraState.previewing — the main surface. Every widget occupies a
// proven GridRegion (GridLayout.captureScene) placed on the 100×218
// atom grid; the preview widget is EXACTLY the GIF (64 cells = 64
// pixels at 1 atom each). No hand positioning, no raw numbers.

import SwiftUI

struct LivePreviewStateView: View {
    @ObservedObject var camera: CameraManager

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
        ZStack {
            if let cgImage = camera.previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)  // nearest neighbor — pixel-perfect
                    .resizable()
                    .frame(width: Lattice.gif(TesseractLattice.previewCells),
                           height: Lattice.gif(TesseractLattice.previewCells))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        Text("64 × 64")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))
                    )
            }
            epochGridOverlay
        }
        .border(Color.white.opacity(0.15), width: 1)
    }

    // 4×4 epoch grid: one line every 16 cells (the epoch stride).
    private var epochGridOverlay: some View {
        Canvas { context, size in
            let lineColor = Color.white.opacity(0.06)
            let step = Lattice.gif(TesseractLattice.previewCells / 4)
            for i in 1..<4 {
                let x = step * CGFloat(i)
                var v = Path()
                v.move(to: CGPoint(x: x, y: 0))
                v.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(v, with: .color(lineColor), lineWidth: 0.5)
                var h = Path()
                h.move(to: CGPoint(x: 0, y: x))
                h.addLine(to: CGPoint(x: size.width, y: x))
                context.stroke(h, with: .color(lineColor), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Birkhoff Beauty Gauge

    private var birkhoffGauge: some View {
        VStack(spacing: Lattice.pt(2)) {
            if let m = camera.previewMeasure {
                HStack(spacing: Lattice.gif(3)) {
                    Text("M")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))

                    GeometryReader { geo in
                        let width = geo.size.width
                        let normalized = min(1, m.beauty / 600)  // scale to [0,1]
                        Rectangle()
                            .fill(.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Rectangle()
                                    .fill(.white.opacity(0.3 + Double(normalized) * 0.5))
                                    .frame(width: width * CGFloat(normalized))
                            }
                    }
                    .frame(height: Lattice.pt(2))

                    Text(String(format: "%.0f", m.beauty))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: Lattice.gif(11), alignment: .trailing)
                }

                HStack(spacing: Lattice.gif(4)) {
                    metricLabel("O", String(format: "%.0f", m.order))
                    metricLabel("C", String(format: "%.2f", m.complexity))
                    metricLabel("dim", String(format: "%.1f", m.manifoldDim))
                    metricLabel("col", "\(m.colorsUsed)")
                }
            } else {
                Text("M = O / C")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
    }

    private func metricLabel(_ label: String, _ value: String) -> some View {
        VStack(spacing: Lattice.pt(1)) {
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    // MARK: - R, G, B, D Channel Previews (4 × 12 cells + 3 × 2-cell gutters = 54)

    private var channelPreviews: some View {
        HStack(spacing: Lattice.gif(2)) {
            channelThumb(image: camera.previewR, label: "R", tint: .red)
            channelThumb(image: camera.previewG, label: "G", tint: .green)
            channelThumb(image: camera.previewB, label: "B", tint: .blue)
            channelThumb(image: camera.previewD, label: "D", tint: .white)
        }
    }

    private func channelThumb(image: CGImage?, label: String, tint: Color) -> some View {
        VStack(spacing: Lattice.pt(1)) {
            Group {
                if let img = image {
                    Image(decorative: img, scale: 1.0)
                        .interpolation(.none)
                        .resizable()
                } else {
                    Rectangle().fill(.gray.opacity(0.1))
                }
            }
            .frame(width: Lattice.gif(TesseractLattice.channelCells),
                   height: Lattice.gif(TesseractLattice.channelCells))
            .border(tint.opacity(0.4), width: 1)

            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(tint.opacity(0.6))
        }
    }

    // MARK: - Capture Info

    private var captureInfoLine: some View {
        let mode = CameraConfig.mode
        let step = CameraConfig.rgbCrop / mode.spatialSide
        return Text("\(mode.frameCount) frames  \(String(format: "%.1f", Double(mode.frameCount) / 20.0))s  \(step * step) px/blk")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
    }

    // MARK: - Record Button (18-cell footprint, 14-cell disc)

    private var recordButton: some View {
        Button(action: { camera.startRecording() }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: Lattice.gif(TesseractLattice.recordCells),
                           height: Lattice.gif(TesseractLattice.recordCells))
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: Lattice.gif(TesseractLattice.recordDiscCells),
                           height: Lattice.gif(TesseractLattice.recordDiscCells))
                // Tesseract glyph: nested squares, one atom apart
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.black.opacity(0.2), lineWidth: 1)
                    .frame(width: Lattice.gif(5), height: Lattice.gif(5))
                RoundedRectangle(cornerRadius: 2)
                    .stroke(.black.opacity(0.15), lineWidth: 1)
                    .frame(width: Lattice.gif(3), height: Lattice.gif(3))
                    .offset(x: Lattice.pt(2), y: -Lattice.pt(2)) // LINT-ALLOW-POSITION (glyph, not layout)
            }
        }
        .accessibilityLabel("Record 64 frames")
    }
}
