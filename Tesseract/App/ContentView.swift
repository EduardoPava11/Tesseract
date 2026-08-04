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
    @State private var showEliteMap = false

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
                            FaceCaptureView(camera: faceCamera)
                        }
                    }
                    .frame(width: Lattice.gridWidthPt, height: Lattice.gridHeightPt)

                    CellText("TESSERACT", rows: TypeRows.label,
                             ink: Color(srgb8: Ink.ledGhost))
                        .place(GridLayout.wordmark)
                    modePill(.live).place(GridLayout.modeLive)
                    modePill(.face).place(GridLayout.modeFace)

                    if appMode == .live && showsMapButton {
                        eliteMapButton.place(GridLayout.eliteButton)
                    }
                }
                .gridCentered(in: geo.size)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showEliteMap) {
            EliteMapView(
                map: camera.eliteMap,
                version: camera.eliteVersion,
                onClose: { showEliteMap = false }
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
    private var modeSwitchAllowed: Bool {
        guard appMode == .live else { return true }
        switch camera.state {
        case .recording, .processing, .composing: return false
        default: return true
        }
    }

    /// A mode pill on its own 20×11-cell claim. Selected = accent ring +
    /// lit label; unselected = ControlFrame (ghost, BEAT invitation);
    /// disabled mid-capture = checker face.
    private func modePill(_ mode: AppMode) -> some View {
        let selected = mode == appMode
        let region = mode == .live ? GridLayout.modeLive : GridLayout.modeFace
        return Button {
            guard mode != appMode, modeSwitchAllowed else { return }
            appMode = mode
        } label: {
            ZStack {
                if selected {
                    CellSprite(cols: region.w, rows: region.h, cellPt: Lattice.gifPx) { c, r in
                        (c == 0 || c == region.w - 1 || r == 0 || r == region.h - 1)
                            ? Ink.accent : nil
                    }
                } else {
                    ControlFrame(cols: region.w, rows: region.h,
                                 state: modeSwitchAllowed ? 0 : 3,
                                 tick: clock.tick, reduceMotion: clock.reduceMotion)
                }
                CellText(mode.rawValue, rows: TypeRows.label,
                         ink: Color(srgb8: selected ? Ink.ink : Ink.ledGhost))
            }
            .frame(width: Lattice.gif(region.w), height: Lattice.gif(region.h))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!modeSwitchAllowed)
        .accessibilityLabel("\(mode.rawValue) mode")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - LIVE: one view per CameraState

    private var liveBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.state {
            case .idle:
                IdleStateView()

            case .previewing:
                LivePreviewStateView(camera: camera, clock: clock)

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
                    generation: gen
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
                    resultPlaceholder
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

    private var resultPlaceholder: some View {
        VStack(spacing: Lattice.gif(4)) {
            CellText("GIF ready", rows: TypeRows.body)
            Button { camera.state = .previewing } label: {
                CellFrameButton(icon: .retake(), title: "AGAIN", tick: 1,
                                cols: GridLayout.resultRetake.w,
                                rows: GridLayout.resultRetake.h)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retake")
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
        let ink = camera.eliteMap.coverage > 0 ? Ink.ink : Ink.ledGhost
        return Button { showEliteMap = true } label: {
            ZStack {
                ControlFrame(cols: GridLayout.eliteButton.w, rows: GridLayout.eliteButton.h,
                             state: 0, tick: clock.tick, reduceMotion: clock.reduceMotion)
                HStack(spacing: Lattice.pt(2)) {
                    CellIcon.grid3x3(ink: ink)
                    CellText("\(camera.eliteMap.coverage)/9", rows: TypeRows.label,
                             ink: Color(srgb8: ink))
                }
            }
            .frame(width: Lattice.gif(GridLayout.eliteButton.w),
                   height: Lattice.gif(GridLayout.eliteButton.h))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Elite map, \(camera.eliteMap.coverage) of 9 cells explored")
    }

    // Share path: GIFSaver.presentShareSheet is the ONE implementation
    // (walks to the topmost presenter — covers the elite-map cover too).
}

#Preview {
    ContentView()
}
