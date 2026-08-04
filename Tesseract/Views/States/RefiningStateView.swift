// RefiningStateView.swift
// Tesseract
//
// CameraState.refining(alpha) — Phase 3. Single composite GIF;
// rotation gesture adjusts α, tap exports.

import SwiftUI

struct RefiningStateView: View {
    @ObservedObject var camera: CameraManager
    @ObservedObject var animator: DualCubeAnimator
    let alpha: Float
    let onExport: (Data) -> Void

    var body: some View {
        VStack(spacing: Lattice.gif(4)) {
            Spacer()

            // Composite GIF (the merged result of A+B or B+A)
            let refineFrame = animator.cubeA.slice(axis: .z, depth: animator.frameIndex)
            if !refineFrame.isEmpty,
               let image = camera.buildPreviewImage(indices: refineFrame) {
                Image(decorative: image, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: Lattice.gif(64), height: Lattice.gif(64))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // α indicator
            Text("α = \(String(format: "%.2f", alpha))")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))

            // Gesture hints
            HStack(spacing: Lattice.gif(6)) {
                Label("↺ base", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                Label("tap export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                Label("other ↻", systemImage: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()
        }
        .gesture(
            RotationGesture()
                .onChanged { angle in
                    let delta = Float(angle.radians) * 0.05
                    if delta > 0 {
                        camera.rotateCW(delta: abs(delta))
                    } else {
                        camera.rotateCCW(delta: abs(delta))
                    }
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    // Re-encodes at the on-screen gene/α, THEN shares —
                    // the old path shared the pre-steering gifData.
                    camera.exportCurrent { onExport($0) }
                }
        )
    }
}
