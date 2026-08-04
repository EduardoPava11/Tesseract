// ContentView.swift
// Tesseract
//
// Front-facing app: launch lands directly in the LIVE camera preview —
// no picker, no landing screen. The camera starts configuring on its
// session queue during the first body evaluation.
//
// UI is organized by state: each CameraState case renders exactly one
// view from Views/States/. This file only owns mode switching, camera
// ownership handoff (AVCaptureSession ↔ ARSession), and share plumbing.

import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var faceCamera = FaceCaptureManager()
    @StateObject private var dualAnimator = DualCubeAnimator(
        cubeA: VoxelCube(), cubeB: VoxelCube()
    )

    // Front-camera only: LIVE (TrueDepth depth) and FACE (ARKit mesh).
    enum AppMode: String, CaseIterable, Identifiable {
        case live = "LIVE"
        case face = "FACE"
        var id: String { rawValue }
    }
    @State private var appMode: AppMode = .live
    @State private var showEliteMap = false

    var body: some View {
        Group {
            switch appMode {
            case .live:
                liveBody
            case .face:
                FaceCaptureView(camera: faceCamera)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { modeBar }
        // Launch → LIVE preview immediately.
        .onAppear { camera.start() }
        // The TrueDepth camera admits ONE owner: AVCaptureSession (LIVE) and
        // ARSession (FACE) cannot coexist. On every mode change, fully stop
        // the other capture system SYNCHRONOUSLY before starting the new one.
        .onChange(of: appMode) { _, newMode in
            switch newMode {
            case .live:
                faceCamera.stop()   // release TrueDepth from ARKit first
                camera.start()
            case .face:
                camera.stop()       // release TrueDepth from AVFoundation first
                faceCamera.start()
            }
        }
    }

    // MARK: - Mode Bar (LIVE | FACE)

    /// Switching mid-capture would destroy an in-flight recording.
    private var modeSwitchAllowed: Bool {
        guard appMode == .live else { return true }
        switch camera.state {
        case .recording, .processing, .composing: return false
        default: return true
        }
    }

    private var modeBar: some View {
        HStack {
            Text("TESSERACT")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
            HStack(spacing: 4) {
                ForEach(AppMode.allCases) { mode in
                    Button {
                        guard mode != appMode else { return }
                        withAnimation(.easeInOut(duration: 0.15)) { appMode = mode }
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(mode == appMode ? 0.9 : 0.35))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(Color.white.opacity(mode == appMode ? 0.12 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!modeSwitchAllowed)
                    .accessibilityLabel("\(mode.rawValue) mode")
                    .accessibilityAddTraits(mode == appMode ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    // MARK: - LIVE: one view per CameraState

    private var liveBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .idle:
                IdleStateView()

            case .previewing:
                LivePreviewStateView(camera: camera)

            case .recording(let frame):
                RecordingStateView(camera: camera, frame: frame)

            case .processing:
                ProcessingStateView(camera: camera)

            case .dualExplore(let gen):
                DualExploreStateView(
                    camera: camera,
                    animator: dualAnimator,
                    generation: gen,
                    onShare: { shareCurrentGIF() }
                )

            case .composing:
                // Flash state — immediately transitions to refining
                ProgressView("Composing...")
                    .foregroundStyle(.white)

            case .refining(let alpha):
                RefiningStateView(
                    camera: camera,
                    animator: dualAnimator,
                    alpha: alpha,
                    onExport: { shareGIF($0) }
                )

            case .done:
                if let gifData = camera.gifData, let measure = camera.gifMeasure {
                    ResultStateView(
                        gifData: gifData,
                        measure: measure,
                        onAgain: { camera.state = .previewing },
                        onShare: { shareGIF(gifData) }
                    )
                } else {
                    resultPlaceholder
                }

            case .error(let msg):
                ErrorStateView(message: msg, onRetry: {
                    camera.state = .idle
                    camera.start()
                })
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsMapButton { eliteMapButton }
        }
        .fullScreenCover(isPresented: $showEliteMap) {
            EliteMapView(
                map: camera.eliteMap,
                version: camera.eliteVersion,
                onClose: { showEliteMap = false }
            )
        }
    }

    private var resultPlaceholder: some View {
        VStack(spacing: 16) {
            Text("GIF ready")
                .font(.system(.headline, design: .monospaced))
            Button("Again") { camera.state = .previewing }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Elite Map Access

    private var showsMapButton: Bool {
        switch camera.state {
        case .previewing, .dualExplore, .refining, .done: return true
        default: return false
        }
    }

    private var eliteMapButton: some View {
        Button { showEliteMap = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 10))
                Text("\(camera.eliteMap.coverage)/9")
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(camera.eliteMap.coverage > 0 ? 0.6 : 0.25))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06), in: Capsule())
            .padding(.trailing, 12)
            .padding(.top, 8)
        }
        .accessibilityLabel("Elite map, \(camera.eliteMap.coverage) of 9 cells explored")
    }

    // MARK: - Share

    private func shareGIF(_ data: Data) {
        guard let url = GIFEncoder.saveToTempFile(data) else { return }

        // Share just the GIF file — no text overlay
        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        // iPad popover anchor
        controller.popoverPresentationController?.sourceView = UIView()

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        root.present(controller, animated: true)
    }

    private func shareCurrentGIF() {
        if let gifData = camera.gifData {
            shareGIF(gifData)
        }
    }
}

#Preview {
    ContentView()
}
