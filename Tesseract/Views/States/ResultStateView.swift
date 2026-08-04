// ResultStateView.swift
// Tesseract
//
// CameraState.done — the exported GIF at full focus with its Birkhoff
// measure, plus Share / Keep / Retake.

import SwiftUI

struct ResultStateView: View {
    let gifData: Data
    let measure: BirkhoffMeasure
    let onAgain: () -> Void
    let onShare: () -> Void

    enum KeepState { case idle, saving, saved, failed }
    @State private var keepState: KeepState = .idle

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // The GIF — full focus, 256×256 nearest-neighbor
            GIFPlayerView(data: gifData)
                .frame(width: 256, height: 256)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .white.opacity(0.05), radius: 20)

            // Birkhoff measure of the exported GIF
            HStack(spacing: 16) {
                resultMetric("M", String(format: "%.0f", measure.beauty))
                resultMetric("O", String(format: "%.0f", measure.order))
                resultMetric("C", String(format: "%.2f", measure.complexity))
                resultMetric("dim", String(format: "%.1f", measure.manifoldDim))
                resultMetric("col", "\(measure.colorsUsed)")
            }
            .padding(.top, 16)

            Spacer()

            // Share + Keep — the two actions that matter
            HStack(spacing: 12) {
                Button(action: onShare) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: Capsule())
                }

                Button(action: keep) {
                    HStack(spacing: 8) {
                        Image(systemName: keepIcon)
                        Text(keepLabel)
                    }
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white.opacity(keepState == .saved ? 0.6 : 1))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .disabled(keepState == .saving || keepState == .saved)
            }
            .padding(.bottom, 16)

            // Retake — subtle
            Button(action: onAgain) {
                Text("Retake")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.bottom, 48)
        }
    }

    private var keepIcon: String {
        switch keepState {
        case .idle: return "square.and.arrow.down"
        case .saving: return "ellipsis"
        case .saved: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var keepLabel: String {
        switch keepState {
        case .idle: return "Keep"
        case .saving: return "Saving"
        case .saved: return "Kept"
        case .failed: return "Retry"
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

    private func resultMetric(_ label: String, _ value: String) -> some View {
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
