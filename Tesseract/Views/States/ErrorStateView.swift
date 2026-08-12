// ErrorStateView.swift
// Tesseract
//
// Error — two-register voice (2026-08-09): a terse all-caps headline
// plus one lowercase sentence that explains the connection, per the
// permission-UX guidance (never a bare unexplained failure). RETRY is
// optional — terminal states (missing hardware) render no dead action.
// Open Settings appears when the failure is a permission denial
// (Retry can never succeed until the user flips the toggle).
// Region-placed (GridLayout.errorScene); shared by LIVE and FACE.

import SwiftUI

struct ErrorStateView: View {
    /// All-caps headline register (e.g. "CAMERA OFF").
    let message: String
    /// Lowercase explanatory register; wrapped into the errMsg region.
    var detail: String? = nil
    /// nil ⇒ terminal state: no RETRY button is rendered.
    var onRetry: (() -> Void)? = nil
    var showsSettings: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            CellText(message, rows: TypeRows.body, ink: Color(srgb8: Ink.reject))
                .place(GridLayout.errTitle)
            if let detail {
                detailLines(detail).place(GridLayout.errMsg)
            }
            if let onRetry {
                Button(action: onRetry) {
                    CellFrameButton(title: "RETRY", tick: 1,
                                    cols: GridLayout.errRetry.w, rows: GridLayout.errRetry.h)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry")
                .place(GridLayout.errRetry)
            }
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

    // CellText is single-line; word-wrap the detail to the region.
    private func detailLines(_ text: String) -> some View {
        VStack(spacing: Lattice.pt(2)) {
            ForEach(Array(Self.wrap(text, width: Self.wrapColumns).enumerated()), id: \.offset) { _, line in
                CellText(line, rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    /// Wrap width in characters, derived from the errMsg region and
    /// the label register's ACTUAL monospace advance (measured via
    /// CellText's raster — no font-metric guesses; line pass).
    static let wrapColumns: Int = {
        guard let one = CellText.snap("0", rows: TypeRows.label) else { return 36 }
        let advancePt = one.size.width * Lattice.pt(1)
        return max(8, Int((Lattice.gif(GridLayout.errMsg.w) / advancePt).rounded(.down)))
    }()

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
