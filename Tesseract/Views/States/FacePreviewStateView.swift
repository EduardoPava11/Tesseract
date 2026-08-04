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

    var body: some View {
        ZStack(alignment: .topLeading) {
            BirkhoffGauge(measure: camera.previewMeasure).place(GridLayout.gauge)
            quantizedPreview.place(GridLayout.preview)
            faceDot.place(GridLayout.faceDot)
            captureInfoLine.place(GridLayout.captureInfo)
            PaletteSwatchView().place(GridLayout.palette)
            recordButton.place(GridLayout.record)
        }
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
