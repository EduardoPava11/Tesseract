// ProcessingStateView.swift
// Tesseract
//
// CameraState.processing — progress bar + live Go board visualization
// (3 boards: R/G, G/B, B/R territory).

import SwiftUI

struct ProcessingStateView: View {
    @ObservedObject var camera: CameraManager

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("TESSERACT")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            // Go board visualization (3 boards: R/G, G/B, B/R)
            if let boards = camera.processBoards {
                HStack(spacing: 8) {
                    goBoardView(board: boards.rg, label: "R/G", tintA: .red, tintB: .green)
                    goBoardView(board: boards.gb, label: "G/B", tintA: .green, tintB: .blue)
                    goBoardView(board: boards.br, label: "B/R", tintA: .blue, tintB: .red)
                }
                .padding(.horizontal, 16)
            } else {
                // Placeholder before first frame analyzed
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.05))
                            .frame(width: 100, height: 100)
                    }
                }
            }

            // Progress bar
            VStack(spacing: 6) {
                ProgressView(value: Double(camera.processProgress))
                    .tint(.white)
                    .padding(.horizontal, 48)

                Text(String(format: "%.0f%%", camera.processProgress * 100))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))

                Text(camera.processPhase)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    // MARK: - Go Board Visualization

    private func goBoardView(board: GoBoard, label: String, tintA: Color, tintB: Color) -> some View {
        VStack(spacing: 2) {
            // 19×19 grid rendered as pixels
            Canvas { context, size in
                let cellSize = size.width / CGFloat(GoBoard.size)
                for y in 0..<GoBoard.size {
                    for x in 0..<GoBoard.size {
                        let stone = board[x, y]
                        let color: Color = switch stone {
                        case .black: tintA.opacity(0.8)
                        case .white: tintB.opacity(0.8)
                        case .empty: .gray.opacity(0.15)
                        }
                        let rect = CGRect(
                            x: CGFloat(x) * cellSize,
                            y: CGFloat(y) * cellSize,
                            width: cellSize, height: cellSize
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )

            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}
