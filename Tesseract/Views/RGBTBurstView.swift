// RGBTBurstView.swift
// Tesseract
//
// Rear-camera RGBT burst UI: 64 sequential plain-Bayer RAW shots reduced
// in-callback → photon-time T pipeline → 64³ cube GIF at 256×256.
// Lives alongside the front-camera GIF flow and the 2-DNG RAW mode;
// ContentView switches between them.

@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct RGBTBurstView: View {
    @StateObject private var manager = RGBTCaptureManager()

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
            // FIRST: force the 64³ cube — the GIF-mode level picker may have
            // left CameraConfig in .inference (PerfectQuantizer /
            // QuantizedFrame / BinomialCadence all read the global).
            CameraConfig.mode = .training
            switch manager.state {
            case .idle, .error: manager.configure()
            default: break
            }
        }
        .onDisappear {
            // Full teardown — removes inputs/outputs so the next entry
            // reconfigures cleanly instead of failing canAddInput.
            manager.teardown()
        }
    }

    // MARK: - Configuring

    private var configuringView: some View {
        VStack(spacing: 16) {
            Text("RGBT")
                .font(.system(.title, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            ProgressView()
                .tint(.white)
            Text("configuring camera")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Ready (preview + shutter)

    private var readyView: some View {
        ZStack {
            RGBTPreviewLayerView(previewLayer: manager.previewLayer)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topHUD
                Spacer()
                shutterButton
                    .padding(.bottom, 48)
            }
        }
    }

    private var topHUD: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("RGBT")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(.white)
                Text("ready")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Text("rear · 64³ photon-time cube")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
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

    // MARK: - Capturing (n / 64)

    private func capturingView(frame: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Text("\(frame) / \(RGBTCaptureManager.burstFrames)")
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.white)

            ProgressView(value: Double(frame) / Double(RGBTCaptureManager.burstFrames))
                .tint(.white)
                .padding(.horizontal, 48)

            Text("~6s · one exposure, 64 shots")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()
        }
    }

    // MARK: - Processing

    private func processingView(progress: Float, phase: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Text("RGBT")
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

    private func doneView(_ result: RGBTResult) -> some View {
        VStack(spacing: 0) {
            GIFResultView(
                gifData: result.gifData,
                measure: result.measure,
                onAgain: { manager.retry() },
                onShare: { shareGIF(result.gifData) }
            )

            Text(statsCaption(result.stats))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 16)
        }
    }

    private func statsCaption(_ s: RGBTStats) -> String {
        let exposure = s.exposureSec > 0
            ? "1/\(Int((1.0 / s.exposureSec).rounded()))s"
            : "?s"
        return String(
            format: "σT μ=%.1e · floor %.0f%% · ISO %d · %@ · burst %.1fs",
            s.meanSigmaT, s.floorFraction * 100, s.iso, exposure, s.burstDurationSec
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
                Text("RGBT burst unavailable")
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
    /// copied from CaptureRAWView (SwiftUI .sheet was blank on iOS 26).
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

// Duplicated from CaptureRAWView (private there; the original is untouched).
private struct RGBTPreviewLayerView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> RGBTPreviewContainer {
        let v = RGBTPreviewContainer()
        v.attach(previewLayer)
        return v
    }

    func updateUIView(_ uiView: RGBTPreviewContainer, context: Context) {
        uiView.attach(previewLayer)
    }
}

/// Hosts an externally-owned AVCaptureVideoPreviewLayer. The manager owns
/// the layer so it survives view teardown/recreate cycles.
private final class RGBTPreviewContainer: UIView {
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
