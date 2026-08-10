// FacePreviewStateView.swift
// Tesseract
//
// FACE .previewing — the anatomical-cadence preview surface, placed on
// GridLayout.facePreviewScene. Same footprints as the LIVE capture
// scene (gauge / preview / info / palette / record); the channels row
// becomes the face-detected dot (nose = 1 signal has no R/G/B/D split).

import SwiftUI

struct FacePreviewStateView: View {
    @ObservedObject var camera: FaceCaptureManager
    let clock: SurfaceClock
    let onSettings: () -> Void

    // SIMPLICITY DECREE (2026-08-09): preview + shutter + settings,
    // nothing else (richer widgets survive below, unplaced).
    // Amendment (2026-08-09): the face dot appears transiently — each
    // face-found/lost transition shows it for 2s, then it cuts out
    // (a hard cut, not an alpha fade: the vocabulary has no opacity).
    @State private var dotVisible = false
    @State private var dotRevision = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            quantizedPreview.place(GridLayout.preview)
            recordButton.place(GridLayout.record)
            settingsButton.place(GridLayout.settingsButton)
            if dotVisible {
                faceDot.place(GridLayout.faceDot)
            }
        }
        .onChange(of: camera.faceDetected) { _, _ in
            dotVisible = true
            dotRevision += 1
        }
        .task(id: dotRevision) {
            guard dotVisible else { return }
            try? await Task.sleep(for: .seconds(2))
            dotVisible = false
        }
    }

    private var settingsButton: some View {
        Button(action: onSettings) {
            ZStack {
                ControlFrame(cols: GridLayout.settingsButton.w,
                             rows: GridLayout.settingsButton.h,
                             state: 0, tick: clock.tick,
                             reduceMotion: clock.reduceMotion)
                CellText("SET", rows: TypeRows.label,
                         ink: Color(srgb8: Ink.ledGhost))
            }
            .frame(width: Lattice.gif(GridLayout.settingsButton.w),
                   height: Lattice.gif(GridLayout.settingsButton.h))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    private var quantizedPreview: some View {
        Group {
            if let cgImage = camera.previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: Lattice.gif(TesseractLattice.previewCells),
                           height: Lattice.gif(TesseractLattice.previewCells))
            } else {
                ZStack {
                    Color(srgb8: CellChecker.dark)
                    CellText("64 × 64", rows: TypeRows.label,
                             ink: Color(srgb8: Ink.ledGhost))
                }
                .frame(width: Lattice.gif(TesseractLattice.previewCells),
                       height: Lattice.gif(TesseractLattice.previewCells))
            }
        }
        .pixelFrame()
    }

    // The anatomical signal indicator: accept-ink seal when a face is
    // tracked, ghost when not.
    private var faceDot: some View {
        HStack(spacing: Lattice.pt(3)) {
            CellIcon.seal(box: 6, ink: camera.faceDetected ? Ink.accept : Ink.ledGhost)
            CellText(camera.faceDetected ? "face" : "no face", rows: TypeRows.label,
                     ink: Color(srgb8: camera.faceDetected ? Ink.ink : Ink.ledGhost))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(camera.faceDetected ? "Face detected" : "No face detected")
    }

    private var captureInfoLine: some View {
        CellText("anatomical cadence  nose = 1  background = 0",
                 rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
    }

    // Same BEAT record button as LIVE (the shared control language).
    private var recordButton: some View {
        let treatment = CellMechanics.faceTreatment(
            state: 0, tick: clock.reduceMotion ? 1 : clock.tick)
        return Button(action: { camera.startRecording() }) {
            CellButton(state: .idle,
                       ringInk: treatment == 1 ? Ink.ink : Ink.ledGhost)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("Record 64 frames")
    }
}
