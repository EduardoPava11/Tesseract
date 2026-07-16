// FaceCaptureView.swift
// Tesseract
//
// FACE mode UI: live quantized preview of the ARKit anatomical cadence.
// idle → previewing → recording (n/64) → processing → done (GIFResultView).
// Full ARSession teardown in onDisappear — the TrueDepth camera must be
// free before the LIVE mode's AVCaptureSession starts.

import SwiftUI

struct FaceCaptureView: View {
    @ObservedObject var camera: FaceCaptureManager

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
        .onDisappear { camera.stop() }  // full ARSession teardown
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 16) {
            Text("FACE")
                .font(.system(.title, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Text("anatomical cadence")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
            ProgressView()
                .tint(.white)
                .padding(.top, 8)
            Text("initializing face tracking...")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        }
    }

    // MARK: - Live Preview

    private var previewView: some View {
        VStack(spacing: 0) {
            Spacer()

            quantizedPreview
                .padding(.horizontal, 24)

            faceIndicator
                .padding(.top, 12)

            Spacer()

            recordButton
                .padding(.bottom, 48)
        }
    }

    private var quantizedPreview: some View {
        ZStack {
            // Glass border
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .frame(
                    width: CGFloat(CameraConfig.displaySize + 8),
                    height: CGFloat(CameraConfig.displaySize + 8)
                )

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
                        Text("\(CameraConfig.outputSize) × \(CameraConfig.outputSize)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))
                    )
            }
        }
    }

    // MARK: - Face Indicator

    private var faceIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(camera.faceDetected ? Color.green.opacity(0.8) : Color.white.opacity(0.15))
                .frame(width: 6, height: 6)
            Text(camera.faceDetected ? "face" : "no face")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(camera.faceDetected ? 0.6 : 0.3))
        }
    }

    // MARK: - Record Button (nested-squares house style)

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

    // MARK: - Recording

    private func recordingView(frame: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()

            if let cgImage = camera.previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(
                        width: CGFloat(CameraConfig.displaySize),
                        height: CGFloat(CameraConfig.displaySize)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text("\(frame) / \(CameraConfig.totalFrames)")
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.white)

            ProgressView(value: Double(frame) / Double(CameraConfig.totalFrames))
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
        VStack(spacing: 20) {
            Spacer()

            Text("FACE")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            VStack(spacing: 6) {
                ProgressView(value: Double(camera.processProgress))
                    .tint(.white)
                    .padding(.horizontal, 48)

                Text(String(format: "%.0f%%", camera.processProgress * 100))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))

                Text(camera.processPhase)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
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

    // MARK: - Share

    private func shareGIF(_ data: Data) {
        guard let url = GIFEncoder.saveToTempFile(data) else { return }

        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        controller.popoverPresentationController?.sourceView = UIView()

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        root.present(controller, animated: true)
    }
}
