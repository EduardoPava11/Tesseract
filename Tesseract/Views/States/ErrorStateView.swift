// ErrorStateView.swift
// Tesseract
//
// Error — Retry always; Open Settings when the failure is a permission
// denial (Retry can never succeed until the user flips the toggle).
// Region-placed (GridLayout.errorScene); shared by LIVE and FACE.

import SwiftUI

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void
    var showsSettings: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            CellText("ERROR", rows: TypeRows.body, ink: Color(srgb8: Ink.reject))
                .place(GridLayout.errTitle)
            messageLines.place(GridLayout.errMsg)
            Button(action: onRetry) {
                CellFrameButton(title: "RETRY", tick: 1,
                                cols: GridLayout.errRetry.w, rows: GridLayout.errRetry.h)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry")
            .place(GridLayout.errRetry)
            if showsSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    CellFrameButton(title: "SETTINGS", tick: 1,
                                    cols: GridLayout.errSettings.w, rows: GridLayout.errSettings.h)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Settings")
                .place(GridLayout.errSettings)
            }
        }
    }

    // CellText is single-line; word-wrap the message to the region.
    private var messageLines: some View {
        VStack(spacing: Lattice.pt(2)) {
            ForEach(Array(Self.wrap(message, width: 36).enumerated()), id: \.offset) { _, line in
                CellText(line, rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }

    static func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
