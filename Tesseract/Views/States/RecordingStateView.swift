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
        VStack(spacing: 16) {
            Spacer()

            if let cgImage = camera.previewImage {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 256, height: 256)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text("\(frame) / \(total)")
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(.white)

            ProgressView(value: Double(frame) / Double(total))
                .tint(.white)
                .padding(.horizontal, 48)

            Text(String(format: "%.1fs", Double(frame) / 20.0))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()
        }
    }
}
