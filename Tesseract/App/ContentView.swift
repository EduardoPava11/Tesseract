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

    /// Switching mid-capture would destroy an in-flight recording.
    /// The law lives in the SURFACE MACHINE (SM3): work is sacred —
    /// exactly WEAVING and SOLVING refuse interruption.
    private var modeSwitchAllowed: Bool {
        switch appMode {
        case .live:
            return SurfaceMachine.state(
                for: camera.state,
                hasPreview: camera.previewImage != nil).interruptible
        case .face:
            return SurfaceMachine.state(
                for: faceCamera.state,
                hasPreview: faceCamera.previewImage != nil).interruptible
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
                                    boards: camera.processBoards,
                                    table: camera.liveTable)

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
                errorState(msg,
                           restart: { camera.state = .idle; camera.start() },
                           reshoot: { camera.state = .previewing })
            }
        }
    }

    // Two-register error voice (2026-08-09): all-caps headline + one
    // lowercase sentence that explains the connection. The HEADLINE
    // is the surface machine's word (SM1); terminal hardware gates
    // render no RETRY (SM4: they are the machine's only terminals);
    // permission denials add Open Settings; a failed encode retries
    // to .previewing (the session is still running).
    @ViewBuilder
    private func errorState(_ msg: String,
                            restart: @escaping () -> Void,
                            reshoot: @escaping () -> Void) -> some View {
        let refusal = SurfaceMachine.refusal(for: msg)
        let headline = SurfaceMachine.State.refused(refusal).word
        switch refusal {
        case .cameraOff:
            ErrorStateView(message: headline,
                           detail: "allow camera access in Settings to see the preview",
                           onRetry: restart,
                           showsSettings: true)
        case .noTrueDepth:
            // The gate: Tesseract does not run on non-TrueDepth iPhones
            // (Daniel, 2026-08-09). No capability key can hide the app
            // from these devices, so the gate states the requirement.
            ErrorStateView(message: headline,
                           detail: "tesseract needs the Face ID camera, and this iPhone has none")
        case .noFaceTracking:
            ErrorStateView(message: headline,
                           detail: "this device cannot track the ARKit face mesh")
        case .exportFailed:
            ErrorStateView(message: headline,
                           detail: "the GIF could not be encoded, record again",
                           onRetry: reshoot)
        case .unknown(let detail):
            ErrorStateView(message: headline, detail: detail, onRetry: restart)
        }
    }

    private func resultPlaceholder(onAgain: @escaping () -> Void) -> some View {
        VStack(spacing: Lattice.gif(4)) {
            CellText("NO GIF", rows: TypeRows.body)
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
                                    boards: nil,
                                    table: faceCamera.liveTable)

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
                errorState(msg,
                           restart: { faceCamera.state = .idle; faceCamera.start() },
                           reshoot: { faceCamera.state = .previewing })
            }
        }
    }

    // Share path: GIFSaver.presentShareSheet is the ONE implementation
    // (walks to the topmost presenter — covers the settings cover too).
}

#Preview {
    ContentView()
}
