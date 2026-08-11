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

    enum KeepState { case idle, saving, saved, denied, failed }
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

            // Second register (2026-08-09): one lowercase line explaining
            // a KEEP outcome the button label alone cannot.
            if let note = keepNote {
                CellText(note, rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
                    .place(GridLayout.resultNote)
            }
        }
    }

    private var keepNote: String? {
        switch keepState {
        case .denied: return "photos off, allow adding in Settings"
        case .failed: return "the GIF did not save, try again"
        default: return nil
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
        case .denied: return "gearshape"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var keepLabel: String {
        switch keepState {
        case .idle: return "KEEP"
        case .saving: return "…"
        case .saved: return "KEPT"
        // "ALLOW" (not "SETTINGS"): fits the body register in the
        // 22-cell button; the resultNote line explains it opens Settings.
        case .denied: return "ALLOW"
        case .failed: return "RETRY"
        }
    }

    private func keep() {
        // Denied is only fixable in Settings — the button becomes the
        // deep link (RETRY could never succeed; NN/g permission pattern).
        // Reset to idle so a return from Settings offers KEEP again.
        if keepState == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            keepState = .idle
            return
        }
        keepState = .saving
        let data = gifData
        Task {
            switch await GIFSaver.saveToPhotos(data) {
            case .saved: keepState = .saved
            case .denied: keepState = .denied
            case .failed: keepState = .failed
            }
        }
    }
}
