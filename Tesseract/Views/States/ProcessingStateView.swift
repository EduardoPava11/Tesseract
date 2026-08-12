// ProcessingStateView.swift
// Tesseract
//
// Processing — progress + live Go board visualization, region-placed
// (GridLayout.processingScene). Data-driven so LIVE and FACE share it;
// FACE passes boards: nil and the boards region renders empty.

import SwiftUI
import simd

struct ProcessingStateView: View {
    let progress: Float
    let phase: String
    let boards: GoBoards?
    /// The palette being created — per-frame DYAD table (nil until the
    /// palette pass begins, or for non-dyad looks).
    var table: Data? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The machine's word (SM1): after capture the grid keeps
            // talking — SOLVING, with the palette being born below.
            CellText(SurfaceMachine.State.solving.word, rows: TypeRows.body,
                     ink: Color(srgb8: Ink.ledGhost))
                .place(GridLayout.procTitle)
            boardsRow.place(GridLayout.procBoards)
            CellPalette(table: table).place(GridLayout.procPalette)
            progressBar.place(GridLayout.procBar)
            CellText(String(format: "%.0f%%", progress * 100), rows: TypeRows.counter)
                .place(GridLayout.procPct)
            CellText(phase, rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
                .place(GridLayout.procPhase)
        }
    }

    // 3 boards of 19 atoms + labels; empty (FACE) leaves the region blank.
    @ViewBuilder private var boardsRow: some View {
        if let boards {
            HStack(spacing: Lattice.gif(2)) {
                goBoard(boards.rg, label: "R/G", tintA: Ink.chanR, tintB: Ink.chanG)
                goBoard(boards.gb, label: "G/B", tintA: Ink.chanG, tintB: Ink.chanB)
                goBoard(boards.br, label: "B/R", tintA: Ink.chanB, tintB: Ink.chanR)
            }
        }
    }

    // One Go cell = one atom (19 cells = 19 atoms = 76pt), opaque inks.
    private func goBoard(_ board: GoBoard, label: String,
                         tintA: SIMD3<UInt8>, tintB: SIMD3<UInt8>) -> some View {
        VStack(spacing: Lattice.pt(1)) {
            CellSprite(cols: GoBoard.size, rows: GoBoard.size, cellPt: Lattice.gifPx) { x, y in
                switch board[x, y] {
                case .black: tintA
                case .white: tintB
                case .empty: CellChecker.dark
                }
            }
            .pixelFrame()
            CellText(label, rows: TypeRows.micro, ink: Color(srgb8: Ink.ledGhost))
        }
        .accessibilityHidden(true)
    }

    private var progressBar: some View {
        let lit = max(0, min(64, Int((Double(progress) * 64).rounded())))
        return CellSprite(cols: 64, rows: 2, cellPt: Lattice.gifPx) { c, _ in
            c < lit ? Ink.ink : Ink.ledGhost
        }
        .accessibilityLabel("Processing \(Int(progress * 100)) percent")
    }
}
