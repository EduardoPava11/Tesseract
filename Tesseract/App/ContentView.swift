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
    /// THE one 20Hz chrome clock — drives every BEAT and heartbeat.
    @State private var clock = SurfaceClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Front-camera only: LIVE (TrueDepth depth) and FACE (ARKit mesh).
    enum AppMode: String, CaseIterable, Identifiable {
        case live = "LIVE"
        case face = "FACE"
        var id: String { rawValue }
    }
    @State private var appMode: AppMode = .live
    @State private var showSettings = false

    // SIMPLICITY DECREE (2026-08-09): launch shows the loading screen
    // until the first preview frame exists, then ONE surface — preview,
    // shutter, settings. No chrome, no mode pills, no gallery button.
    // Mode selection lives inside the settings cover.
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // THE GRID CANVAS: the exact 100×218 atom grid (400×872 pt)
            // centered in the live screen. Everything inside is either a
            // placed GridRegion or an atom-derived stack.
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Group {
                        switch appMode {
                        case .live:
                            liveBody
                        case .face:
                            faceBody
                        }
                    }
                    .frame(width: Lattice.gridWidthPt, height: Lattice.gridHeightPt)
                }
                .gridCentered(in: geo.size)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(
                appMode: $appMode,
                modeSwitchAllowed: modeSwitchAllowed,
                clock: clock,
                onClose: { showSettings = false }
            )
        }
        // Launch → LIVE preview immediately.
        .onAppear {
            clock.reduceMotion = reduceMotion
            clock.start()
            camera.start()
        }
        .onChange(of: reduceMotion) { _, rm in clock.reduceMotion = rm }
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

    /// Switching mid-capture would destroy an in-flight recording —
    /// guarded in BOTH modes (the FACE side was previously unguarded).
    private var modeSwitchAllowed: Bool {
        switch appMode {
        case .live:
            switch camera.state {
            case .recording, .processing, .composing: return false
            default: return true
            }
        case .face:
            switch faceCamera.state {
            case .recording, .processing: return false
            default: return true
            }
        }
    }

    // MARK: - LIVE: one view per CameraState

    private var liveBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .idle:
                IdleStateView()

            case .previewing:
                // Graceful arrival: hold the loading screen until the
                // first preview frame exists.
                if camera.previewImage == nil {
                    IdleStateView()
                } else {
                    LivePreviewStateView(camera: camera, clock: clock,
                                         onSettings: { showSettings = true })
                }

            case .recording(let frame):
                RecordingStateView(previewImage: camera.previewImage,
                                   frame: frame,
                                   total: CameraConfig.totalFrames)

            case .processing:
                ProcessingStateView(progress: camera.processProgress,
                                    phase: camera.processPhase,
                                    boards: camera.processBoards)

            case .dualExplore(let gen):
                DualExploreStateView(
                    camera: camera,
                    animator: dualAnimator,
                    generation: gen,
                    clock: clock
                )

            case .composing:
                // Flash state — immediately transitions to refining
                CellText("COMPOSING…", rows: TypeRows.label,
                         ink: Color(srgb8: Ink.ledGhost))

            case .refining(let alpha):
                RefiningStateView(
                    camera: camera,
                    animator: dualAnimator,
                    alpha: alpha,
                    clock: clock,
                    onExport: { GIFSaver.presentShareSheet($0) }
                )

            case .done:
                if let gifData = camera.gifData, let measure = camera.gifMeasure {
                    ResultStateView(
                        gifData: gifData,
                        measure: measure,
                        onAgain: { camera.state = .previewing },
                        onShare: { GIFSaver.presentShareSheet(gifData) }
                    )
                } else {
                    resultPlaceholder(onAgain: { camera.state = .previewing })
                }

            case .error(let msg):
                ErrorStateView(
                    message: msg,
                    onRetry: {
                        camera.state = .idle
                        camera.start()
                    },
                    showsSettings: msg == CameraManager.cameraDeniedMessage
                )
            }
        }
    }

    private func resultPlaceholder(onAgain: @escaping () -> Void) -> some View {
        VStack(spacing: Lattice.gif(4)) {
            CellText("GIF ready", rows: TypeRows.body)
            Button(action: onAgain) {
                CellFrameButton(icon: .retake(), title: "AGAIN", tick: 1,
                                cols: GridLayout.resultRetake.w,
                                rows: GridLayout.resultRetake.h)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retake")
        }
    }

    // MARK: - FACE: same shared state views, mapped from FaceCaptureState
    //
    // Lifecycle stays with .onChange(of: appMode) — the SOLE owner of the
    // AVCaptureSession ↔ ARSession handoff (TrueDepth admits one owner).
    // FACE .done → Again returns to .previewing (the ARSession never
    // paused during processing); error Retry does .idle then start().

    private var faceBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch faceCamera.state {
            case .idle:
                IdleStateView()

            case .previewing:
                if faceCamera.previewImage == nil {
                    IdleStateView()
                } else {
                    FacePreviewStateView(camera: faceCamera, clock: clock,
                                         onSettings: { showSettings = true })
                }

            case .recording(let frame):
                RecordingStateView(previewImage: faceCamera.previewImage,
                                   frame: frame,
                                   total: CameraConfig.totalFrames)

            case .processing:
                ProcessingStateView(progress: faceCamera.processProgress,
                                    phase: faceCamera.processPhase,
                                    boards: nil)

            case .done:
                if let gifData = faceCamera.gifData, let measure = faceCamera.gifMeasure {
                    ResultStateView(
                        gifData: gifData,
                        measure: measure,
                        onAgain: { faceCamera.state = .previewing },
                        onShare: { GIFSaver.presentShareSheet(gifData) }
                    )
                } else {
                    resultPlaceholder(onAgain: { faceCamera.state = .previewing })
                }

            case .error(let msg):
                ErrorStateView(
                    message: msg,
                    onRetry: {
                        faceCamera.state = .idle
                        faceCamera.start()
                    }
                )
            }
        }
    }

    // Elite-map gallery: parked with the A/B deprecation — EliteMapView
    // stays compiled but has no entry point on the simple surface.

    // Share path: GIFSaver.presentShareSheet is the ONE implementation
    // (walks to the topmost presenter — covers the settings cover too).
}

#Preview {
    ContentView()
}
