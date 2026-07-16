// DNGCaptureView.swift
// Tesseract
//
// Rear-camera DNG mode UI, restored from archive/rear-rgbt RGBTBurstView
// and reworked for the streaming NN-debayer pipeline:
//   • rung picker (S ∈ {64, 256, 1024}) — sets DNGConfig.rung
//   • live binomial readout during capture (histogram vs B(S², 1/256))
//   • result view: GIF + Wasserstein λ-trajectory readout + stats caption
// The manager is owned by ContentView (mode exclusivity) and injected.

@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct DNGCaptureView: View {
    @ObservedObject var manager: DNGCaptureManager
    @State private var rung: DNGRung = DNGConfig.rung

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch manager.state {
            case .idle, .configuring:
                configuringView

            case .ready:
                readyView

            case .capturing(let frame):
                capturingView(frame: frame)

            case .processing(let progress, let phase):
                processingView(progress: progress, phase: phase)

            case .done(let result):
                doneView(result)

            case .error(let msg):
                errorOverlay(msg)
            }
        }
        .onAppear {
            rung = DNGConfig.rung
            switch manager.state {
            case .idle, .error: manager.configure()
            default: break
            }
        }
        // Teardown lives in ContentView's mode-exclusivity onChange.
    }

    // MARK: - Configuring

    private var configuringView: some View {
        VStack(spacing: 16) {
            Text("DNG")
                .font(.system(.title, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            ProgressView()
                .tint(.white)
            Text("configuring rear camera")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Ready (preview + rung picker + shutter)

    private var readyView: some View {
        ZStack {
            DNGPreviewLayerView(previewLayer: manager.previewLayer)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topHUD
                Spacer()
                rungPicker
                    .padding(.bottom, 16)
                shutterButton
                    .padding(.bottom, 48)
            }
        }
    }

    private var topHUD: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DNG")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(.white)
                Text("ready")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Text("rear · NN debayer → rung ladder")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var rungPicker: some View {
        VStack(spacing: 4) {
            Picker("Rung", selection: $rung) {
                ForEach(DNGRung.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .onChange(of: rung) { _, newRung in
                DNGConfig.rung = newRung
            }

            // Index-byte budget per burst: S² × 64 (why 1024 is the ceiling).
            Text("\(rung.side)² × 64 · \(byteLabel(rung.indexBytesPerBurst)) indices · GIF \(rung.side * rung.gifUpscale)²")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func byteLabel(_ bytes: Int) -> String {
        bytes >= 1 << 20
            ? String(format: "%.0f MB", Double(bytes) / Double(1 << 20))
            : String(format: "%.0f KB", Double(bytes) / Double(1 << 10))
    }

    private var shutterButton: some View {
        Button {
            Task { await manager.captureBurst() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(shutterFill)
                    .frame(width: 66, height: 66)
            }
        }
        .disabled(!canShoot)
        .opacity(canShoot ? 1 : 0.4)
    }

    private var shutterFill: Color {
        switch manager.state {
        case .capturing, .processing: return .red
        case .ready, .done:           return .white
        default:                      return .white.opacity(0.3)
        }
    }

    private var canShoot: Bool {
        if case .ready = manager.state { return true }
        return false
    }

    // MARK: - Capturing (n / 64 + live binomial readout)

    private func capturingView(frame: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Text("\(frame) / \(DNGCaptureManager.burstFrames)")
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.white)

            ProgressView(value: Double(frame) / Double(DNGCaptureManager.burstFrames))
                .tint(.white)
                .padding(.horizontal, 48)

            Text("~6s · one exposure · \(rung.side)² rung")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            binomialReadout
                .padding(.top, 8)

            Spacer()
        }
    }

    /// Live "colors in the binomial distribution": per-frame 256-bin
    /// histogram vs B(S², 1/256) as it streams off the debayer.
    private var binomialReadout: some View {
        VStack(spacing: 4) {
            if let b = manager.liveBinomial {
                Text("B(S², 1/256) · frame \(b.frame)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                HStack(spacing: 16) {
                    readoutValue("μ", String(format: "%.0f", b.expectedMean))
                    readoutValue("σ²ₑ", String(format: "%.0f", b.expectedVariance))
                    readoutValue("σ²ₒ", String(format: "%.0f", b.observedVariance))
                    readoutValue("×", String(format: "%.1f", b.varianceRatio))
                }
            } else {
                Text("binomial readout warming up")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
    }

    private func readoutValue(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Processing

    private func processingView(progress: Float, phase: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Text("DNG")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            VStack(spacing: 6) {
                ProgressView(value: Double(progress))
                    .tint(.white)
                    .padding(.horizontal, 48)

                Text(String(format: "%.0f%%", progress * 100))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))

                Text(phase)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    // MARK: - Done

    private func doneView(_ result: DNGResult) -> some View {
        VStack(spacing: 0) {
            GIFResultView(
                gifData: result.gifData,
                measure: result.measure,
                onAgain: { manager.retry() },
                onShare: { shareGIF(result.gifData) }
            )

            lambdaTrajectory(result.stats.lambdas)
                .padding(.bottom, 8)

            Text(statsCaption(result.stats))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 16)
        }
    }

    /// Tiny Wasserstein trajectory readout: the three barycentric weights
    /// λ = (λ₀, λ₃₂, λ₆₃) per frame, drawn as three polylines over the burst.
    private func lambdaTrajectory(_ lambdas: [SIMD3<Double>]) -> some View {
        VStack(spacing: 3) {
            Canvas { context, size in
                guard lambdas.count > 1 else { return }
                let colors: [Color] = [
                    .white.opacity(0.85), .white.opacity(0.5), .white.opacity(0.25)
                ]
                for comp in 0..<3 {
                    var path = Path()
                    for (i, l) in lambdas.enumerated() {
                        let x = size.width * CGFloat(i) / CGFloat(lambdas.count - 1)
                        let v = comp == 0 ? l.x : (comp == 1 ? l.y : l.z)
                        let y = size.height * (1 - CGFloat(v))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path, with: .color(colors[comp]), lineWidth: 1)
                }
            }
            .frame(width: 256, height: 40)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Text("λ₀ — λ₃₂ — λ₆₃  ·  W₁ barycentric trajectory")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private func statsCaption(_ s: DNGStats) -> String {
        let exposure = s.exposureSec > 0
            ? "1/\(Int((1.0 / s.exposureSec).rounded()))s"
            : "?s"
        let meanRatio = s.binomial.isEmpty
            ? 0
            : s.binomial.map(\.varianceRatio).reduce(0, +) / Double(s.binomial.count)
        return String(
            format: "S=%d · native %d² · binomial ×%.1f · ISO %d · %@ · burst %.1fs",
            s.rung.side, s.nativeSide, meanRatio, s.iso, exposure, s.burstDurationSec
        )
    }

    // MARK: - Error

    private func errorOverlay(_ msg: String) -> some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.yellow.opacity(0.8))
                Text("DNG burst unavailable")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.white)
                Text(msg)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Retry") {
                    manager.retry()
                }
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Share

    /// Directly present UIActivityViewController on the frontmost VC —
    /// SwiftUI .sheet was blank on iOS 26 (archive lesson).
    private func shareGIF(_ data: Data) {
        guard let url = GIFEncoder.saveToTempFile(data) else { return }
        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        controller.popoverPresentationController?.sourceView = UIView()

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
    }
}

// MARK: - Preview layer

private struct DNGPreviewLayerView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> DNGPreviewContainer {
        let v = DNGPreviewContainer()
        v.attach(previewLayer)
        return v
    }

    func updateUIView(_ uiView: DNGPreviewContainer, context: Context) {
        uiView.attach(previewLayer)
    }
}

/// Hosts an externally-owned AVCaptureVideoPreviewLayer. The manager owns
/// the layer so it survives view teardown/recreate cycles.
private final class DNGPreviewContainer: UIView {
    private weak var attached: AVCaptureVideoPreviewLayer?

    func attach(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard attached !== previewLayer else { return }
        attached?.removeFromSuperlayer()
        previewLayer.frame = bounds
        layer.addSublayer(previewLayer)
        attached = previewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attached?.frame = bounds
    }
}
