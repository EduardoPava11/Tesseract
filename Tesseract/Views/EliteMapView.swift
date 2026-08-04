// EliteMapView.swift
// Tesseract
//
// The MAP-Elites gallery: a 3×3 grid over (temporal rhythm × color spread),
// each cell holding the most beautiful organism found at that descriptor.
// Cells show a static first frame; selecting a cell plays its GIF with
// Share / Keep actions. Empty cells = unexplored aesthetic regions.

import SwiftUI
import ImageIO

struct EliteMapView: View {
    let map: EliteMap
    let version: Int          // bumped by CameraManager on placement → re-render
    let onClose: () -> Void

    @State private var selectedIndex: Int? = nil   // row * 3 + col

    private enum SaveState { case idle, saving, saved, failed }
    @State private var saveState: SaveState = .idle

    private let cellSize: CGFloat = 92
    private let labelWidth: CGFloat = 52

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 16)

                Spacer()

                grid

                Spacer()

                if let cell = selectedCell {
                    detail(cell)
                } else {
                    Text("tap a cell")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .frame(height: 260)
                }

                Spacer()

                Button(action: onClose) {
                    Text("close")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var selectedCell: EliteCell? {
        guard let i = selectedIndex else { return nil }
        return map.cells[i / 3][i % 3]
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("ELITE MAP")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Text("\(map.coverage)/9 explored · rhythm × spread")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - 3×3 Grid

    private var grid: some View {
        VStack(spacing: 4) {
            // Column labels (spread: mono → vivid)
            HStack(spacing: 4) {
                Color.clear.frame(width: labelWidth, height: 10)
                ForEach(0..<3, id: \.self) { col in
                    Text(EliteMap.colLabels[col])
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: cellSize)
                }
            }

            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 4) {
                    // Row label (rhythm: static → dynamic)
                    Text(EliteMap.rowLabels[row])
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: labelWidth, alignment: .trailing)

                    ForEach(0..<3, id: \.self) { col in
                        cellView(row: row, col: col)
                    }
                }
            }
        }
    }

    private func cellView(row: Int, col: Int) -> some View {
        let index = row * 3 + col
        let cell = map.cells[row][col]
        let isSelected = selectedIndex == index

        return Button {
            guard cell != nil else { return }
            selectedIndex = index
            saveState = .idle
        } label: {
            ZStack {
                if let cell {
                    GIFFirstFrameView(data: cell.gifData)
                        .frame(width: cellSize, height: cellSize)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    // Beauty badge
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(String(format: "%.0f", cell.beauty))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 2))
                                .padding(3)
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.03))
                        .frame(width: cellSize, height: cellSize)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.7) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            cell.map { "\(EliteMap.rowLabels[row]) \(EliteMap.colLabels[col]), beauty \(Int($0.beauty))" }
                ?? "\(EliteMap.rowLabels[row]) \(EliteMap.colLabels[col]), empty"
        )
    }

    // MARK: - Selected Detail

    private func detail(_ cell: EliteCell) -> some View {
        VStack(spacing: 10) {
            GIFPlayerView(data: cell.gifData)
                .frame(width: 176, height: 176)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .id(selectedIndex)   // force re-decode on selection change

            HStack(spacing: 16) {
                detailMetric("M", String(format: "%.0f", cell.beauty))
                detailMetric("rhythm", String(format: "%.2f", cell.descriptor.rhythm))
                detailMetric("spread", String(format: "%.2f", cell.descriptor.spread))
            }

            HStack(spacing: 12) {
                Button {
                    GIFSaver.presentShareSheet(cell.gifData)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Button {
                    saveState = .saving
                    let data = cell.gifData
                    Task {
                        let ok = await GIFSaver.saveToPhotos(data)
                        saveState = ok ? .saved : .failed
                    }
                } label: {
                    Label(saveLabel, systemImage: saveIcon)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(saveState == .saved ? 0.6 : 1))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .disabled(saveState == .saving || saveState == .saved)
            }
        }
        .frame(height: 260)
    }

    private var saveIcon: String {
        switch saveState {
        case .idle: return "square.and.arrow.down"
        case .saving: return "ellipsis"
        case .saved: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var saveLabel: String {
        switch saveState {
        case .idle: return "Keep"
        case .saving: return "Saving"
        case .saved: return "Kept"
        case .failed: return "Retry"
        }
    }

    private func detailMetric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
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
            Rectangle().fill(Color.gray.opacity(0.1))
        }
    }
}
