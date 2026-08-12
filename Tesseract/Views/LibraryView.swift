// LibraryView.swift
// Tesseract
//
// The GIF archive (Daniel, 2026-08-10): review old GIFs and their
// color palettes. FullScreenCover, own canvas, region-placed
// (GridLayout.libraryScene). 3×3 grid of the latest nine archived
// captures (still thumbnails — nine playing GIFs would fight the
// chrome clock); tap one to see it PLAYING beside its 256-entry
// palette (GCT = frame 0's table for DYAD) and its role-law
// provenance line (m*, α, phases) read back from the file itself.

import SwiftUI

struct LibraryView: View {
    let clock: SurfaceClock
    let onClose: () -> Void

    @State private var urls: [URL] = []
    @State private var selected: URL?
    @State private var selectedData: Data?
    /// Thumbnails decoded ONCE per reload — the body re-evaluates at
    /// the 20 Hz chrome clock, and decoding nine GIF first-frames
    /// from disk per tick was 180 file opens a second (line pass P0).
    @State private var thumbs: [URL: CGImage] = [:]

    var body: some View {
        ZStack {
            Color(srgb8: Ink.black).ignoresSafeArea()
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    CellText("LIBRARY", rows: TypeRows.display)
                        .place(GridLayout.libTitle)

                    ForEach(Array(GridLayout.libCells.enumerated()), id: \.offset) { i, region in
                        tile(index: i).place(region)
                    }

                    if let data = selectedData {
                        GIFPlayerView(data: data)
                            .frame(width: Lattice.gif(GridLayout.libDetailGif.w),
                                   height: Lattice.gif(GridLayout.libDetailGif.h))
                            .pixelFrame()
                            .place(GridLayout.libDetailGif)
                        CellPalette(table: GIFLibrary.palette(of: data))
                            .place(GridLayout.libDetailPalette)
                        infoLines(data).place(GridLayout.libInfo)
                        shareButton(data).place(GridLayout.libShare)
                        deleteButton.place(GridLayout.libDelete)
                    } else if urls.isEmpty {
                        CellText("no gifs yet, record one",
                                 rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
                            .place(GridLayout.libInfo)
                    }

                    closeButton.place(GridLayout.libClose)
                }
                .gridCentered(in: geo.size)
            }
            .ignoresSafeArea()
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        urls = Array(GIFLibrary.list().prefix(9))
        thumbs = urls.reduce(into: [:]) { acc, url in
            acc[url] = GIFLibrary.thumbnail(of: url)
        }
        if let selected, !urls.contains(selected) {
            self.selected = nil
            selectedData = nil
        }
        if selected == nil, let first = urls.first {
            select(first)
        }
    }

    private func select(_ url: URL) {
        selected = url
        selectedData = try? Data(contentsOf: url)
    }

    // MARK: - Tiles (bracket-faced stills, 16-cell content in 20-cell claim)

    @ViewBuilder private func tile(index: Int) -> some View {
        if index < urls.count {
            let url = urls[index]
            Button(action: { select(url) }) {
                ZStack {
                    Group {
                        if let thumb = thumbs[url] {
                            Image(decorative: thumb, scale: 1.0)
                                .interpolation(.none)
                                .resizable()
                        } else {
                            Color(srgb8: Ink.void)
                        }
                    }
                    .frame(width: Lattice.gif(16), height: Lattice.gif(16))
                    ControlBrackets(side: 16,
                                    state: url == selected ? 1 : 0,
                                    tick: clock.tick,
                                    reduceMotion: clock.reduceMotion)
                }
                .frame(width: Lattice.gif(20), height: Lattice.gif(20))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("GIF \(index + 1) of \(urls.count)")
            .accessibilityAddTraits(url == selected ? .isSelected : [])
        } else {
            Color(srgb8: Ink.void)
                .frame(width: Lattice.gif(16), height: Lattice.gif(16))
                .frame(width: Lattice.gif(20), height: Lattice.gif(20))
        }
    }

    // MARK: - Detail

    private func infoLines(_ data: Data) -> some View {
        let mixture = GIFLibrary.mixtureLine(of: data) ?? "no role-law provenance"
        return VStack(alignment: .leading, spacing: Lattice.pt(2)) {
            CellText("\(data.count / 1024) kb · \(selected?.lastPathComponent ?? "")",
                     rows: TypeRows.micro, ink: Color(srgb8: Ink.ledGhost))
            CellText(Self.fit(mixture, rows: TypeRows.micro,
                              toCells: GridLayout.libInfo.w),
                     rows: TypeRows.micro, ink: Color(srgb8: Ink.ledGhost))
        }
    }

    /// Truncate to the widest prefix whose RASTER fits the region —
    /// measured through CellText's own snap, no font-metric guesses
    /// (line pass: the full mixture line overflowed the grid).
    static func fit(_ text: String, rows: Int, toCells cells: Int) -> String {
        let maxPt = Lattice.gif(cells)
        var t = text
        while t.count > 1,
              let mask = CellText.snap(t, rows: rows),
              mask.size.width * Lattice.pt(1) > maxPt {
            t = String(t.dropLast(max(1, t.count / 8)))
        }
        return t
    }

    private func shareButton(_ data: Data) -> some View {
        Button(action: { GIFSaver.presentShareSheet(data) }) {
            CellFrameButton(icon: .share(), title: "SHARE", tick: 1,
                            cols: GridLayout.libShare.w, rows: GridLayout.libShare.h)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share GIF")
    }

    private var deleteButton: some View {
        Button {
            if let selected {
                GIFLibrary.delete(selected)
                self.selected = nil
                selectedData = nil
                reload()
            }
        } label: {
            CellFrameButton(title: "DELETE", tick: 1,
                            cols: GridLayout.libDelete.w, rows: GridLayout.libDelete.h,
                            ink: Ink.reject)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete GIF")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            ZStack {
                ControlFrame(cols: GridLayout.libClose.w, rows: GridLayout.libClose.h,
                             state: 0, tick: clock.tick, reduceMotion: clock.reduceMotion)
                CellText("DONE", rows: TypeRows.body, ink: Color(srgb8: Ink.ink))
            }
            .frame(width: Lattice.gif(GridLayout.libClose.w),
                   height: Lattice.gif(GridLayout.libClose.h))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
    }
}
