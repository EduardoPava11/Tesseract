// ContentView.swift
// Tesseract
//
// ONE SWITCH, ONE MACHINE. Every surface the app can show is a case of
// EditMachine.State (spec/ui/EditMachine.hs EM1–EM13, SM5 preserved:
// one scene per state). The LIVE/FACE difference has collapsed to
// which manager supplies (state, preview, table, frame) — the scene
// selection itself is mode-blind, which is the whole point of having
// a machine and is why this file is now one body instead of two.
//
// This file owns: the two capture managers, the camera-ownership
// handoff (AVCaptureSession ↔ ARSession — TrueDepth admits ONE
// owner), the widget arrangement the user owns, and share plumbing.
//
// ★ THE WATCHING SURFACE IS NOW A WIDGET SET, NOT A LAYOUT
// (spec/ui/WidgetGrid.hs). GridLayout.captureScene's three fixed
// claims are replaced by `WidgetSurfaceView` over a persisted
// `Arrangement`: preview, the 16×16 palette of the current frame, the
// timer, the 64-frame bar, the two coarse reads, and the controls —
// all on screen at once, all movable, all restored at launch.

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

    /// EM1's axis. ⚠ RULING R2 OWED: EditMachine.hs makes SHELVING
    /// home, and §4.6 of the port contract offers two lawful launch
    /// policies — land on the shelf, or take the existing
    /// `Shelving → Watching` edge immediately. This ships the second:
    /// launch lands on the CAMERA, because an empty shelf is a worse
    /// first contact than a live preview and because Daniel's brief
    /// for this pass is "on launch he must see the preview, the
    /// palette, a timer and the frame bar". It is POLICY on top of a
    /// lawful edge, not a machine change: no edge was added, and
    /// SHELVING stays one tap away on the SHELF widget.
    @State private var surface: EditMachine.Surface = .capture

    /// WG4 — the arrangement is a VALUE, restored at launch. Any
    /// corruption (missing, wrong schema, wrong shape, or an UNLAWFUL
    /// decode) lands on `.default`; `ArrangementStore` never throws
    /// and never partially migrates.
    @State private var arrangement: Arrangement = ArrangementStore.load()
    /// WG3/WG8 — while true, widgets take drag instead of taps.
    @State private var arranging = false

    var body: some View {
        ZStack {
            Color(srgb8: Ink.black).ignoresSafeArea()

            // THE GRID CANVAS: the exact 100×218 atom grid (400×872 pt)
            // centered in the live screen. Everything inside is either a
            // placed GridRegion or an atom-derived stack.
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    surfaceBody
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
                onArrange: {
                    // WG3 — ARRANGE is entered only from an
                    // INTERRUPTIBLE state (EM4: work is sacred).
                    guard machineState.interruptible else { return }
                    arranging = true
                    showSettings = false
                },
                onResetLayout: {
                    // The escape hatch lives on a STATIC region, never
                    // on a movable widget: no arrangement, however bad,
                    // can make reset unreachable.
                    ArrangementStore.reset()
                    arrangement = .default
                    arranging = false
                },
                onClose: { showSettings = false }
            )
        }
        // Launch → the camera configures at WAKING. NOT optional: the
        // CENTER STAGE gate fires at WAKING in both managers and every
        // refusal edge in EditMachine originates there, so deferring
        // the session until the user taps through would surface the
        // terminal NO CENTER STAGE refusal late and undermine the
        // store-level device gate (CLAUDE.md).
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

    // MARK: - The machine

    /// EM6/SM5 — the ONE word this frame speaks. Both managers map
    /// case for case, so the scene switch below never asks which mode
    /// it is in.
    private var machineState: EditMachine.State {
        switch appMode {
        case .live:
            return EditMachine.state(for: camera.state, surface: surface,
                                     hasPreview: camera.previewImage != nil)
        case .face:
            return EditMachine.state(for: faceCamera.state, surface: surface,
                                     hasPreview: faceCamera.previewImage != nil)
        }
    }

    /// Switching mid-capture would destroy an in-flight recording.
    /// The law lives in the machine (EM4, the half of SM3 that keeps):
    /// exactly WEAVING and SOLVING refuse interruption. EM5 is the
    /// half that bends — TUNING works AND may be left.
    private var modeSwitchAllowed: Bool { machineState.interruptible }

    /// The capture frame index — WEAVING's payload, zero elsewhere.
    private var captureFrame: Int {
        switch appMode {
        case .live:
            if case .recording(let f) = camera.state { return f }
        case .face:
            if case .recording(let f) = faceCamera.state { return f }
        }
        return 0
    }

    // MARK: - SM5: exactly one scene per state

    @ViewBuilder
    private var surfaceBody: some View {
        ZStack {
            Color(srgb8: Ink.black).ignoresSafeArea()

            switch machineState {
            case .waking:
                IdleStateView()

            case .shelving:
                // EM1 — the shelf, promoted out of the settings cover
                // and onto the machine. The library owns its own
                // canvas; inside the grid frame `gridCentered` is the
                // identity, so it places exactly as it always has.
                LibraryView(clock: clock, onClose: { surface = .capture })

            case .watching:
                instrumentSurface(.watching)

            case .weaving:
                // EM12: the same instruments, now counting. This is
                // where the timer and the 64-frame bar carry data.
                instrumentSurface(.weaving)

            case .solving:
                ProcessingStateView(progress: activeProgress,
                                    phase: activePhase,
                                    boards: appMode == .live ? camera.processBoards : nil,
                                    table: activeExportTable)

            // EM3/EM10 — the solve lands in the EDITOR, not on a dead
            // end. TUNING is where the capture is open; SEALED is the
            // commit. V1 renders the same artifact surface for both
            // (see the report: the dial-driven re-render is not built,
            // so TUNING today holds exactly one edit — the identity).
            case .tuning, .sealed:
                resultSurface

            case .refused(let refusal):
                errorState(refusal)
            }
        }
    }

    /// ★ THE INSTRUMENT SURFACE — the widget set, not a layout.
    ///
    /// EM12 (weave = watch + keep) applies to the SURFACE too, not
    /// only the encoder: WATCHING and WEAVING show the same
    /// instruments and differ in what the readouts are counting. That
    /// is why this takes the state rather than hard-coding `.watching`
    /// — `WidgetScene.widgets(for:)` already defined a `.weaving` set
    /// that nothing could reach.
    ///
    /// It also fixes the defect that made two of the four named
    /// widgets decorative: `captureFrame` is non-zero only in
    /// `.recording`, so a surface rendered exclusively in `.watching`
    /// showed "0.0s" and 0/64 for the whole life of the app, and the
    /// instant those readouts had data a SEPARATE RecordingStateView
    /// took the screen with its own second copy of the counter, the
    /// bar and the clock. One surface, two dispositions.
    private func instrumentSurface(_ state: EditMachine.State) -> some View {
        WidgetSurfaceView(
            state: state,
            previewImage: activePreview,
            midImage: appMode == .live ? camera.preview32 : faceCamera.preview32,
            coarseImage: appMode == .live ? camera.preview16 : faceCamera.preview16,
            paletteData: appMode == .live ? camera.liveFrameTable : faceCamera.liveFrameTable,
            frame: captureFrame,
            clock: clock,
            arrangement: $arrangement,
            arranging: $arranging,
            onShutter: {
                switch appMode {
                case .live: camera.startRecording()
                case .face: faceCamera.startRecording()
                }
            },
            onSettings: { showSettings = true },
            onShelf: { surface = .shelf })
    }

    // MARK: - Manager-blind readings

    private var activePreview: CGImage? {
        appMode == .live ? camera.previewImage : faceCamera.previewImage
    }
    private var activeProgress: Float {
        appMode == .live ? camera.processProgress : faceCamera.processProgress
    }
    private var activePhase: String {
        appMode == .live ? camera.processPhase : faceCamera.processPhase
    }
    /// The EXPORT solve's table — SOLVING's palette-being-born, which
    /// is a different publication from the surface's live table.
    private var activeExportTable: Data? {
        appMode == .live ? camera.liveTable : faceCamera.liveTable
    }
    private var activeGIF: (data: Data, measure: BirkhoffMeasure)? {
        let d = appMode == .live ? camera.gifData : faceCamera.gifData
        let m = appMode == .live ? camera.gifMeasure : faceCamera.gifMeasure
        guard let d, let m else { return nil }
        return (d, m)
    }

    /// EM10 — AGAIN returns to WATCHING through the capture axis. The
    /// capture itself is not yet retained across this step (the
    /// contract's G1), so "fork this moment again" is not offered.
    private func reshoot() {
        surface = .capture
        switch appMode {
        case .live: camera.state = .previewing
        case .face: faceCamera.state = .previewing
        }
    }

    private func restart() {
        surface = .capture
        switch appMode {
        case .live: camera.state = .idle; camera.start()
        case .face: faceCamera.state = .idle; faceCamera.start()
        }
    }

    // MARK: - TUNING / SEALED

    @ViewBuilder
    private var resultSurface: some View {
        if let gif = activeGIF {
            ResultStateView(
                gifData: gif.data,
                measure: gif.measure,
                onAgain: reshoot,
                onShare: { GIFSaver.presentShareSheet(gif.data) })
        } else {
            resultPlaceholder
        }
    }

    // Two-register error voice (2026-08-09): all-caps headline + one
    // lowercase sentence that explains the connection. The HEADLINE
    // is the machine's word (EM6); the three hardware refusals render
    // no RETRY (EM7: they are the machine's only terminals);
    // permission denials add Open Settings; a failed encode retries.
    @ViewBuilder
    private func errorState(_ refusal: EditMachine.Refusal) -> some View {
        let headline = EditMachine.State.refused(refusal).word
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
            // TERMINAL (EM7) — no RETRY.
            ErrorStateView(message: headline,
                           detail: "tesseract needs the Face ID camera, and this iPhone has none")
        case .noCenterStage:
            // The device-targeting gate (Daniel, 2026-08-12): the app is
            // for iPhones with the square-sensor Center Stage selfie
            // camera. No capability key exists, so the gate states the
            // requirement — TERMINAL (EM7), no RETRY.
            ErrorStateView(message: headline,
                           detail: "tesseract needs the center stage selfie camera of iPhone 17 or later")
        case .noFaceTracking:
            ErrorStateView(message: headline,
                           detail: "this device cannot track the ARKit face mesh")
        case .exportFailed:
            ErrorStateView(message: headline,
                           detail: "the GIF could not be encoded, record again",
                           onRetry: reshoot)
        case .unknown(let detail):
            // The second register is lowercase BY LAW — raw system
            // strings arrive Title-cased (line pass 2026-08-12).
            ErrorStateView(message: headline,
                           detail: detail.isEmpty
                               ? "something went wrong, try again"
                               : detail.lowercased(),
                           onRetry: restart)
        }
    }

    /// Defensive fallback for a landed capture without data — speaks
    /// the machine's refusal voice on the region-placed error scene
    /// instead of an off-machine, un-placed word (line pass).
    private var resultPlaceholder: some View {
        ErrorStateView(
            message: EditMachine.State.refused(.exportFailed).word,
            detail: "the GIF could not be encoded, record again",
            onRetry: reshoot)
    }

    // Share path: GIFSaver.presentShareSheet is the ONE implementation
    // (walks to the topmost presenter — covers the settings cover too).
}

#Preview {
    ContentView()
}
