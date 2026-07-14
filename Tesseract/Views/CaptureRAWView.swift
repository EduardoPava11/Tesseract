// CaptureRAWView.swift
// Tesseract
//
// Rear-camera Bayer RAW burst UI. Live preview, shutter, Delta-t slider,
// AirDrop-ready share sheet. Lives alongside the existing front-camera GIF
// flow; ContentView switches between them via a segmented control.

@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct CaptureRAWView: View {
    @StateObject private var manager = RAWCaptureManager()
    @State private var lastSharedBurst: RAWBurst?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewLayerView(previewLayer: manager.previewLayer)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topHUD
                Spacer()
                bottomControls
            }

            // Shown on top of everything if the rear camera couldn't be
            // opened (simulator, permission denied, unsupported device, …).
            // Without this, configure() quietly lands in .error and the
            // preview layer just sits frozen black.
            if case let .error(msg) = manager.state {
                errorOverlay(msg)
            }
        }
        .onAppear {
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
        .onChange(of: manager.state) { _, newState in
            if case let .done(burst) = newState,
               lastSharedBurst != burst {
                lastSharedBurst = burst
                presentShareSheet(for: burst)
            }
        }
    }

    /// Directly present UIActivityViewController on the key window's root.
    /// Mirrors `ContentView.shareGIF` — the SwiftUI `.sheet`-wrapped variant
    /// was presenting a blank UIActivityViewController on iOS 26.
    private func presentShareSheet(for burst: RAWBurst) {
        let controller = UIActivityViewController(
            activityItems: burst.shareItems,
            applicationActivities: nil
        )
        controller.popoverPresentationController?.sourceView = UIView()

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        // Walk to the frontmost presented controller so we don't try to present
        // on a VC that already has a sheet up.
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
    }

    private func errorOverlay(_ msg: String) -> some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.yellow.opacity(0.8))
                Text("Rear camera unavailable")
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

    // MARK: - Top HUD

    private var topHUD: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("RAW")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(.white)
                Text(stateLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Text("48 MP · Bayer DNG")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            deltaSlider
            shutterRow
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .background(
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var deltaSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("delta t")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(String(format: "%3.0f ms", manager.deltaMs))
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(.white)
            }
            Slider(value: $manager.deltaMs, in: 200...1000, step: 1)
                .tint(.white.opacity(0.8))
            Text("≥200 ms · ISP recovery")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private var shutterRow: some View {
        HStack(spacing: 24) {
            if case let .done(burst) = manager.state {
                packageSummary(burst)
            } else {
                Spacer()
            }
            shutterButton
            Spacer()
        }
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
        case .capturing, .waitingDelta, .packaging: return .red
        case .ready, .done:                         return .white
        default:                                    return .white.opacity(0.3)
        }
    }

    private func packageSummary(_ burst: RAWBurst) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("package ready")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Text("\(burst.sensorWidth)×\(burst.sensorHeight)")
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(.white)
            Button("share / airdrop") {
                presentShareSheet(for: burst)
            }
            .font(.system(.caption2, design: .monospaced))
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.2))
            .foregroundStyle(.white)
        }
    }

    // MARK: - State helpers

    private var canShoot: Bool {
        switch manager.state {
        case .ready, .done: return true
        default:            return false
        }
    }

    private var stateLabel: String {
        switch manager.state {
        case .idle:                 return "initializing"
        case .configuring:          return "configuring camera"
        case .ready:                return "ready"
        case .capturing(let l):     return "capturing \(l)…"
        case .waitingDelta:         return "waiting Δt…"
        case .packaging:            return "packaging"
        case .done(let b):          return "done · \(b.sensorWidth)×\(b.sensorHeight)"
        case .error(let msg):       return "error: \(msg)"
        }
    }
}

// MARK: - Preview layer

private struct CameraPreviewLayerView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewContainer {
        let v = PreviewContainer()
        v.attach(previewLayer)
        return v
    }

    func updateUIView(_ uiView: PreviewContainer, context: Context) {
        uiView.attach(previewLayer)
    }
}

/// Hosts an externally-owned AVCaptureVideoPreviewLayer. The manager owns the
/// layer (like ROTAS) so it survives view teardown/recreate cycles.
private final class PreviewContainer: UIView {
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

