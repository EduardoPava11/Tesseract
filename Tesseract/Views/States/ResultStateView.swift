// ResultStateView.swift
// Tesseract
//
// Done — the exported GIF at full focus with its Birkhoff measure,
// plus Share / Keep / Retake. Region-placed (GridLayout.resultScene);
// shared by LIVE and FACE.

import SwiftUI

struct ResultStateView: View {
    let gifData: Data
    let measure: BirkhoffMeasure
    let onAgain: () -> Void
    let onShare: () -> Void

    enum KeepState { case idle, saving, saved, failed }
    @State private var keepState: KeepState = .idle

    var body: some View {
        ZStack(alignment: .topLeading) {
            GIFPlayerView(data: gifData)
                .frame(width: Lattice.gif(TesseractLattice.previewCells),
                       height: Lattice.gif(TesseractLattice.previewCells))
                .pixelFrame()
                .place(GridLayout.resultGif)

            metricsRow.place(GridLayout.resultMetrics)

            Button(action: onShare) {
                CellFrameButton(icon: .share(), title: "SHARE", tick: 1,
                                cols: GridLayout.resultShare.w, rows: GridLayout.resultShare.h)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share GIF")
            .place(GridLayout.resultShare)

            Button(action: keep) {
                CellFrameButton(symbol: keepSymbol, title: keepLabel,
                                state: keepState == .saving ? 2 : 0, tick: 1,
                                cols: GridLayout.resultKeep.w, rows: GridLayout.resultKeep.h,
                                ink: keepState == .saved ? Ink.accept : Ink.ink)
            }
            .buttonStyle(.plain)
            .disabled(keepState == .saving || keepState == .saved)
            .accessibilityLabel(keepLabel)
            .place(GridLayout.resultKeep)

            Button(action: onAgain) {
                CellFrameButton(icon: .retake(), title: "AGAIN", tick: 1,
                                cols: GridLayout.resultRetake.w, rows: GridLayout.resultRetake.h,
                                ink: Ink.ledGhost)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retake")
            .place(GridLayout.resultRetake)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: Lattice.gif(4)) {
            metric("M", String(format: "%.0f", measure.beauty))
            metric("O", String(format: "%.0f", measure.order))
            metric("C", String(format: "%.2f", measure.complexity))
            metric("dim", String(format: "%.1f", measure.manifoldDim))
            metric("col", "\(measure.colorsUsed)")
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: Lattice.pt(1)) {
            CellText(value, rows: TypeRows.label)
            CellText(label, rows: TypeRows.micro, ink: Color(srgb8: Ink.ledGhost))
        }
    }

    private var keepSymbol: String {
        switch keepState {
        case .idle: return "square.and.arrow.down"
        case .saving: return "ellipsis"
        case .saved: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var keepLabel: String {
        switch keepState {
        case .idle: return "KEEP"
        case .saving: return "…"
        case .saved: return "KEPT"
        case .failed: return "RETRY"
        }
    }

    private func keep() {
        keepState = .saving
        let data = gifData
        Task {
            let ok = await GIFSaver.saveToPhotos(data)
            keepState = ok ? .saved : .failed
        }
    }
}
