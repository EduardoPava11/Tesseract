// RecordingStateView.swift
// Tesseract
//
// Recording — live quantized preview + frame counter, region-placed
// (GridLayout.recordingScene). Data-driven so LIVE and FACE share it.

import SwiftUI

struct RecordingStateView: View {
    let previewImage: CGImage?
    let frame: Int
    let total: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            preview.place(GridLayout.preview)
            CellText("\(frame) / \(total)", rows: TypeRows.counter)
                .place(GridLayout.recCounter)
            progressBar.place(GridLayout.recProgress)
            // The machine's word (SM1) + elapsed time: WEAVING n.ns.
            CellText(EditMachine.State.weaving.word + " "
                     + String(format: "%.1fs", Double(frame) / Double(CameraConfig.targetFPS)),
                     rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
                .place(GridLayout.recTime)
        }
    }

    private var preview: some View {
        Group {
            if let cgImage = previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: Lattice.gif(TesseractLattice.previewCells),
                           height: Lattice.gif(TesseractLattice.previewCells))
            } else {
                Color(srgb8: Ink.void)
                    .frame(width: Lattice.gif(TesseractLattice.previewCells),
                           height: Lattice.gif(TesseractLattice.previewCells))
            }
        }
        .pixelFrame()
    }

    // 64×2-atom lit-cells bar — frame progress with no ProgressView.
    private var progressBar: some View {
        let lit = max(0, min(64, Int((Double(frame) / Double(max(1, total)) * 64).rounded())))
        return CellSprite(cols: 64, rows: 2, cellPt: Lattice.gifPx) { c, _ in
            c < lit ? Ink.ink : Ink.ledGhost
        }
        .accessibilityLabel("Recording, frame \(frame) of \(total)")
    }
}
