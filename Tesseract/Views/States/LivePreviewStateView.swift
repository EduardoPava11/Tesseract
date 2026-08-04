// LivePreviewStateView.swift
// Tesseract
//
// CameraState.previewing — the main screen. Shows EXACTLY what the GIF
// will look like: 64×64 tesseract-quantized, displayed at 4× scale,
// with the Birkhoff gauge, R/G/B/D channel thumbs, level picker,
// palette swatch, and the record button.

import SwiftUI

struct LivePreviewStateView: View {
    @ObservedObject var camera: CameraManager

    var body: some View {
        VStack(spacing: 0) {

            // Top: Birkhoff beauty gauge
            birkhoffGauge
                .padding(.top, 16)

            Spacer()

            // Center: quantized preview (64×64 at 4× scale)
            quantizedPreview
                .padding(.horizontal, 24)

            // R, G, B, D channel previews
            channelPreviews
                .padding(.top, 12)

            Spacer()

            // Capture info: frames, duration, samples/block
            captureInfoLine
                .padding(.bottom, 8)

            // Palette swatch (16×16 = 256 colors) + Record button
            HStack(alignment: .center, spacing: 24) {
                PaletteSwatchView()

                recordButton

                // Balance spacing
                Color.clear.frame(width: 64, height: 64)
            }
            .padding(.bottom, 48)
        }
    }

    // MARK: - Quantized Preview (64×64 → 256×256)

    private var quantizedPreview: some View {
        ZStack {
            // Glass border
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .frame(
                    width: CGFloat(CameraConfig.displaySize + 8),
                    height: CGFloat(CameraConfig.displaySize + 8)
                )

            // The actual 64×64 image at 4× scale, nearest-neighbor
            if let cgImage = camera.previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)  // nearest neighbor — pixel-perfect
                    .resizable()
                    .frame(
                        width: CGFloat(CameraConfig.displaySize),
                        height: CGFloat(CameraConfig.displaySize)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(
                        width: CGFloat(CameraConfig.displaySize),
                        height: CGFloat(CameraConfig.displaySize)
                    )
                    .overlay(
                        Text("64 × 64")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))
                    )
            }

            // Grid overlay: 4×4 epoch grid (subtle)
            gridOverlay
        }
    }

    // MARK: - Grid Overlay (shows the 4⁴ structure)

    private var gridOverlay: some View {
        let size = CGFloat(CameraConfig.displaySize)
        let step = size / 4  // 4 divisions = tesseract axis levels

        return Canvas { context, _ in
            let lineColor = Color.white.opacity(0.06)
            // Vertical lines
            for i in 1..<4 {
                let x = step * CGFloat(i) + 4  // offset for border
                var path = Path()
                path.move(to: CGPoint(x: x, y: 4))
                path.addLine(to: CGPoint(x: x, y: size + 4))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }
            // Horizontal lines
            for i in 1..<4 {
                let y = step * CGFloat(i) + 4
                var path = Path()
                path.move(to: CGPoint(x: 4, y: y))
                path.addLine(to: CGPoint(x: size + 4, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
            }
        }
        .frame(
            width: CGFloat(CameraConfig.displaySize + 8),
            height: CGFloat(CameraConfig.displaySize + 8)
        )
        .allowsHitTesting(false)
    }

    // MARK: - Birkhoff Beauty Gauge

    private var birkhoffGauge: some View {
        VStack(spacing: 4) {
            if let m = camera.previewMeasure {
                HStack(spacing: 12) {
                    Text("M")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))

                    // Beauty bar
                    GeometryReader { geo in
                        let width = geo.size.width
                        let normalized = min(1, m.beauty / 600)  // scale to [0,1]
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.08))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.white.opacity(0.3 + Double(normalized) * 0.5))
                                    .frame(width: width * CGFloat(normalized))
                            }
                    }
                    .frame(height: 4)

                    Text(String(format: "%.0f", m.beauty))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 24)

                HStack(spacing: 16) {
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
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    // MARK: - R, G, B, D Channel Previews

    private var channelPreviews: some View {
        HStack(spacing: 4) {
            channelThumb(image: camera.previewR, label: "R", tint: .red)
            channelThumb(image: camera.previewG, label: "G", tint: .green)
            channelThumb(image: camera.previewB, label: "B", tint: .blue)
            channelThumb(image: camera.previewD, label: "D", tint: .white)
        }
    }

    private func channelThumb(image: CGImage?, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            if let img = image {
                Image(decorative: img, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(tint.opacity(0.4), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray.opacity(0.1))
                    .frame(width: 48, height: 48)
            }
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

    // MARK: - Record Button

    private var recordButton: some View {
        Button(action: { camera.startRecording() }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 58, height: 58)
                // Tesseract icon: nested squares
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.black.opacity(0.2), lineWidth: 1)
                    .frame(width: 20, height: 20)
                RoundedRectangle(cornerRadius: 2)
                    .stroke(.black.opacity(0.15), lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .offset(x: 3, y: -3)
            }
        }
    }
}
