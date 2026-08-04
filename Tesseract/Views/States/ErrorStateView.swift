// ErrorStateView.swift
// Tesseract
//
// CameraState.error — Retry always; Open Settings when the message is the
// camera-permission denial (Retry can never succeed until the user flips
// the toggle in Settings).

import SwiftUI

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("error")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.red.opacity(0.7))
            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                if message == CameraManager.cameraDeniedMessage {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
