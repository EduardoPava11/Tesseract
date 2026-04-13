// ContentView.swift
// Tesseract
//
// State machine UI: idle → previewing → recording → result
// Preview shows EXACTLY what the GIF will look like:
//   64×64 tesseract-quantized, displayed at 256×256 (4× scale)

import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .idle:
                idleView

            case .previewing:
                previewView

            case .recording(let frame):
                recordingView(frame: frame)

            case .processing:
                processingView

            case .done:
                if let gifData = camera.gifData, let measure = camera.gifMeasure {
                    GIFResultView(
                        gifData: gifData,
                        measure: measure,
                        onAgain: { camera.state = .previewing },
                        onShare: { shareGIF(gifData) }
                    )
                } else {
                    resultPlaceholder
                }

            case .error(let msg):
                errorView(msg)
            }
        }
        .onAppear { camera.start() }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 16) {
            Text("TESSERACT")
                .font(.system(.title, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Text("4⁴ = 256")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
            ProgressView()
                .tint(.white)
                .padding(.top, 8)
            Text("initializing camera...")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        }
    }

    // MARK: - Live Preview (the main screen)

    private var previewView: some View {
        VStack(spacing: 0) {

            // Top: Birkhoff beauty gauge
            birkhoffGauge
                .padding(.top, 16)

            Spacer()

            // Center: 256×256 quantized preview (64×64 at 4× scale)
            quantizedPreview
                .padding(.horizontal, 24)

            // Depth zone indicator
            depthIndicator
                .padding(.top, 12)

            Spacer()

            // Bottom: Record button
            recordButton
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

        return Canvas { context, canvasSize in
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

    // MARK: - Depth Zone Indicator

    private var depthIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { level in
                let zone = camera.depthZones.first { Int($0.level) == level }
                let count = zone?.pixelCount ?? 0
                let fraction = Float(count) / 4096.0

                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(Double(fraction) * 0.8 + 0.05))
                    .frame(width: 56, height: 6)
                    .overlay(
                        Text(level == 0 ? "near" : level == 3 ? "far" : "")
                            .font(.system(size: 6, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                            .offset(y: 10)
                    )
            }
        }
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

    // MARK: - Recording View

    private func recordingView(frame: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()

            if let cgImage = camera.previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 256, height: 256)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text("\(frame) / 64")
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.white)

            ProgressView(value: Double(frame) / 64.0)
                .tint(.white)
                .padding(.horizontal, 48)

            Text(String(format: "%.1fs", Double(frame) / 20.0))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
            Text("quantizing tesseract...")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Share

    private func shareGIF(_ data: Data) {
        guard let url = GIFEncoder.saveToTempFile(data) else { return }

        // Build metadata string for the share text
        let stats: String
        if let m = camera.gifMeasure {
            stats = "Tesseract 4⁴ · M=\(String(format: "%.0f", m.beauty)) · dim=\(String(format: "%.1f", m.manifoldDim)) · \(m.colorsUsed)/256 colors · \(data.count / 1024)KB"
        } else {
            stats = "Tesseract 4⁴ · 64×64×64 · 20fps"
        }

        let controller = UIActivityViewController(
            activityItems: [url, stats],
            applicationActivities: nil
        )
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        root.present(controller, animated: true)
    }

    // MARK: - Result Placeholder

    private var resultPlaceholder: some View {
        VStack(spacing: 16) {
            Text("GIF ready")
                .font(.system(.headline, design: .monospaced))
            Button("Again") { camera.state = .previewing }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Text("error")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.red.opacity(0.7))
            Text(msg)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") { camera.state = .idle; camera.start() }
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - GIF Result View

struct GIFResultView: View {
    let gifData: Data
    let measure: BirkhoffMeasure
    let onAgain: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // The GIF — full focus, 256×256 nearest-neighbor
            GIFPlayerView(data: gifData)
                .frame(width: 256, height: 256)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .white.opacity(0.05), radius: 20)

            Spacer()

            // Share button — the only action that matters
            Button(action: onShare) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.bottom, 16)

            // Retake — subtle
            Button(action: onAgain) {
                Text("Retake")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.bottom, 48)
        }
    }
}

#Preview {
    ContentView()
}
