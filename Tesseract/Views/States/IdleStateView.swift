// IdleStateView.swift
// Tesseract
//
// CameraState.idle — camera is configuring on the session queue.
// This screen should only be visible for the first few hundred ms.

import SwiftUI

struct IdleStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("TESSERACT")
                .font(.system(.title, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Text("4⁴ = 256")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
            ProgressView()
                .tint(.white)
                .padding(.top, 8)
            Text("initializing camera...")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        }
    }
}
