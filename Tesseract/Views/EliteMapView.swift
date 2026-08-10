// EliteMapView.swift
// Tesseract
//
// The MAP-Elites gallery, placed on GridLayout.eliteMapScene (its own
// fullScreenCover canvas). A 3×3 grid over (temporal rhythm × color
// spread): each 20-cell claim is a bracket-faced control around a
// 16-atom first-frame thumbnail — selected = inverted brackets, empty
// = the disabled checker face. Only the selected cell animates
// (GIFPlayerView); per-cell beauty lives in the accessibility label
// and the detail metrics (badges over thumbnails would obscure
// content pixels, which the bracket law forbids).

import SwiftUI
import ImageIO

struct EliteMapView: View {
    let map: EliteMap
    let version: Int          // bumped by CameraManager on placement → re-render
    let onClose: () -> Void
    let clock: SurfaceClock

    @State private var selectedIndex: Int? = nil   // row * 3 + col

    private enum SaveState { case idle, saving, saved, failed }
    @State private var saveState: SaveState = .idle

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    header.place(GridLayout.eliteHeader)
                    colLabels.place(GridLayout.eliteColLabels)
                    rowLabel(0).place(GridLayout.eliteRowLabel0)
                    rowLabel(1).place(GridLayout.eliteRowLabel1)
                    rowLabel(2).place(GridLayout.eliteRowLabel2)

                    ForEach(0..<9, id: \.self) { i in
                        cellView(index: i).place(GridLayout.eliteCells[i])
                    }

                    if let cell = selectedCell {
                        detailPlayer(cell).place(GridLayout.eliteDetail)
                        detailMetrics(cell).place(GridLayout.eliteMetrics)
                        shareButton(cell).place(GridLayout.eliteShare)
                        keepButton(cell).place(GridLayout.eliteKeep)
                    } else {
                        CellText("tap a cell", rows: TypeRows.label,
                                 ink: Color(srgb8: Ink.ledGhost))
                            .place(GridLayout.eliteDetail)
                    }

                    closeButton.place(GridLayout.eliteClose)
                }
                .gridCentered(in: geo.size)
            }
            .ignoresSafeArea()
        }
    }

    private var selectedCell: EliteCell? {
        guard let i = selectedIndex else { return nil }
        return map.cells[i / 3][i % 3]
    }

    // MARK: - Header + axis labels

    private var header: some View {
        VStack(spacing: Lattice.pt(2)) {
            CellText("ELITE MAP", rows: TypeRows.body)
            CellText("\(map.coverage)/9 explored · rhythm × spread",
                     rows: TypeRows.micro, ink: Color(srgb8: Ink.ledGhost))
        }
    }

    private var colLabels: some View {
        HStack(spacing: Lattice.gif(2)) {
            ForEach(0..<3, id: \.self) { col in
                CellText(EliteMap.colLabels[col], rows: TypeRows.micro,
                         ink: Color(srgb8: Ink.ledGhost))
                    .frame(width: Lattice.gif(20))
            }
        }
    }

    private func rowLabel(_ row: Int) -> some View {
        CellText(EliteMap.rowLabels[row], rows: TypeRows.micro,
                 ink: Color(srgb8: Ink.ledGhost))
    }

    // MARK: - Gallery cells (20-cell bracket face, 16-atom thumbnail)

    private func cellView(index: Int) -> some View {
        let row = index / 3, col = index % 3
        let cell = map.cells[row][col]
        let isSelected = selectedIndex == index
        // idle brackets invite; selected = inverted; empty = checker.
        let state = cell == nil ? 3 : (isSelected ? 1 : 0)

        return Button {
            guard cell != nil else { return }
            selectedIndex = index
            saveState = .idle
        } label: {
            ZStack(alignment: .topLeading) {
                ControlBrackets(side: 16, state: state,
                                tick: clock.tick, reduceMotion: clock.reduceMotion)
                Group {
                    if let cell {
                        GIFFirstFrameView(data: cell.gifData)
                    } else {
                        Color(srgb8: CellChecker.dark)
                    }
                }
                .frame(width: Lattice.gif(16), height: Lattice.gif(16))
                .padding(.top, Lattice.gif(2))
                .padding(.leading, Lattice.gif(2))
            }
            .frame(width: Lattice.gif(20), height: Lattice.gif(20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            cell.map { "\(EliteMap.rowLabels[row]) \(EliteMap.colLabels[col]), beauty \(Int($0.beauty))" }
                ?? "\(EliteMap.rowLabels[row]) \(EliteMap.colLabels[col]), empty"
        )
    }

    // MARK: - Selected detail

    private func detailPlayer(_ cell: EliteCell) -> some View {
        GIFPlayerView(data: cell.gifData)
            .frame(width: Lattice.gif(44), height: Lattice.gif(44))
            .pixelFrame()
            .id(selectedIndex)   // force re-decode on selection change
    }

    private func detailMetrics(_ cell: EliteCell) -> some View {
        HStack(spacing: Lattice.gif(4)) {
            metric("M", String(format: "%.0f", cell.beauty))
            metric("rhythm", String(format: "%.2f", cell.descriptor.rhythm))
            metric("spread", String(format: "%.2f", cell.descriptor.spread))
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: Lattice.pt(1)) {
            CellText(value, rows: TypeRows.label)
            CellText(label, rows: TypeRows.micro, ink: Color(srgb8: Ink.ledGhost))
        }
    }

    private func shareButton(_ cell: EliteCell) -> some View {
        Button {
            GIFSaver.presentShareSheet(cell.gifData)
        } label: {
            CellFrameButton(icon: .share(), title: "SHARE", tick: 1,
                            cols: GridLayout.eliteShare.w, rows: GridLayout.eliteShare.h)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share GIF")
    }

    private func keepButton(_ cell: EliteCell) -> some View {
        Button {
            saveState = .saving
            let data = cell.gifData
            Task {
                // Unreachable surface (A/B deprecation): denied folds
                // into failed here; the shipped path is ResultStateView.
                let result = await GIFSaver.saveToPhotos(data)
                saveState = result == .saved ? .saved : .failed
            }
        } label: {
            CellFrameButton(symbol: saveSymbol, title: saveLabel,
                            state: saveState == .saving ? 2 : 0, tick: 1,
                            cols: GridLayout.eliteKeep.w, rows: GridLayout.eliteKeep.h,
                            ink: saveState == .saved ? Ink.accept : Ink.ink)
        }
        .buttonStyle(.plain)
        .disabled(saveState == .saving || saveState == .saved)
        .accessibilityLabel(saveLabel)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            CellFrameButton(title: "CLOSE", tick: 1,
                            cols: GridLayout.eliteClose.w, rows: GridLayout.eliteClose.h,
                            ink: Ink.ledGhost)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close elite map")
    }

    private var saveSymbol: String {
        switch saveState {
        case .idle: return "square.and.arrow.down"
        case .saving: return "ellipsis"
        case .saved: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var saveLabel: String {
        switch saveState {
        case .idle: return "KEEP"
        case .saving: return "…"
        case .saved: return "KEPT"
        case .failed: return "RETRY"
        }
    }
}

// MARK: - Static First Frame (cheap thumbnail — no animation decode)

/// Decodes only frame 0 of a GIF. The full GIFPlayerView decodes every
/// frame into UIImages; nine of those in a grid would be ~100 MB of
/// bitmaps, so grid cells stay static and only the selection animates.
struct GIFFirstFrameView: View {
    let data: Data

    var body: some View {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            Image(decorative: cgImage, scale: 1.0)
                .interpolation(.none)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
        } else {
            Color(srgb8: CellChecker.dark)
        }
    }
}
