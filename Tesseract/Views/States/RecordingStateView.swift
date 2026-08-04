// RecordingStateView.swift
// Tesseract
//
// CameraState.recording(frame) — live quantized preview + frame counter.

import SwiftUI

struct RecordingStateView: View {
    @ObservedObject var camera: CameraManager
    let frame: Int

    var body: some View {
        let total = CameraConfig.totalFrames
        VStack(spacing: Lattice.gif(4)) {
            Spacer()

            if let cgImage = camera.previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: Lattice.gif(64), height: Lattice.gif(64))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text("\(frame) / \(total)")
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.white)

            ProgressView(value: Double(frame) / Double(total))
                .tint(.white)
                .padding(.horizontal, Lattice.gif(12))

            Text(String(format: "%.1fs", Double(frame) / 20.0))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()
        }
    }
}
