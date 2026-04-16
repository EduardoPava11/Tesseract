// CubeGIFView.swift
// Tesseract
//
// A 64³ GIF rendered as a 3D cube using pure SwiftUI.
// Front face = current GIF frame. Side/top = spatiotemporal projections.
// rotation3DEffect gives the 3D perspective. No SceneKit, no RealityKit.
//
// The cube IS the GIF. Rotating it reveals how time is encoded.

import SwiftUI

/// A GIF displayed as a 3D cube with front, right, and top faces.
/// Each face is a different projection of the VoxelCube data.
struct CubeGIFView: View {

    /// Palette indices for the three visible faces
    let frontFrame: [UInt8]
    let sideFrame: [UInt8]
    let topFrame: [UInt8]

    /// Rotation state (from user drag gesture)
    let rotationY: Double    // radians, horizontal drag
    let rotationX: Double    // radians, vertical drag

    /// Display size (one face side length)
    let size: CGFloat

    /// Convert palette indices → displayable image
    let buildImage: ([UInt8]) -> CGImage?

    /// Label shown below the cube
    var label: String = ""

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // ── Front face ──
                // Visible when facing the user (rotationY ≈ 0)
                faceImage(frontFrame)
                    .rotation3DEffect(
                        .radians(rotationY),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .center,
                        anchorZ: -size / 2,
                        perspective: 0.4
                    )
                    .opacity(frontOpacity)

                // ── Right face ──
                // Visible when rotated right (rotationY > 0)
                faceImage(sideFrame)
                    .rotation3DEffect(
                        .radians(rotationY + .pi / 2),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: .leading,
                        anchorZ: 0,
                        perspective: 0.4
                    )
                    .opacity(sideOpacity)

                // ── Top face ──
                // Visible when rotated up (rotationX < 0)
                faceImage(topFrame)
                    .rotation3DEffect(
                        .radians(rotationX - .pi / 2),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .top,
                        anchorZ: 0,
                        perspective: 0.4
                    )
                    .opacity(topOpacity)

                // ── Wireframe edges (subtle) ──
                cubeWireframe
            }
            .frame(width: size, height: size)

            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    // ── Face rendering ──

    @ViewBuilder
    private func faceImage(_ indices: [UInt8]) -> some View {
        if !indices.isEmpty, let cgImage = buildImage(indices) {
            Image(decorative: cgImage, scale: 1.0)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.05))
                .frame(width: size, height: size)
        }
    }

    // ── Opacity: only show faces that are actually visible ──

    private var frontOpacity: Double {
        let angle = abs(rotationY.truncatingRemainder(dividingBy: 2 * .pi))
        // Front is visible when angle < π/2 or > 3π/2
        if angle < .pi / 2 || angle > 3 * .pi / 2 { return 1.0 }
        return 0.0
    }

    private var sideOpacity: Double {
        let angle = rotationY.truncatingRemainder(dividingBy: 2 * .pi)
        // Side visible when rotated significantly
        return min(1.0, max(0, abs(angle) / 0.4 - 0.5))
    }

    private var topOpacity: Double {
        let angle = rotationX.truncatingRemainder(dividingBy: 2 * .pi)
        return min(1.0, max(0, abs(angle) / 0.4 - 0.5))
    }

    // ── Wireframe: subtle cube edges ──

    private var cubeWireframe: some View {
        ZStack {
            // Front face border
            RoundedRectangle(cornerRadius: 2)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
                .frame(width: size, height: size)
                .rotation3DEffect(
                    .radians(rotationY),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    anchorZ: -size / 2,
                    perspective: 0.4
                )
        }
        .allowsHitTesting(false)
    }
}

// ── Preview ──

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 40) {
            CubeGIFView(
                frontFrame: [],
                sideFrame: [],
                topFrame: [],
                rotationY: 0.3,
                rotationX: -0.1,
                size: 180,
                buildImage: { _ in nil },
                label: "A"
            )
            CubeGIFView(
                frontFrame: [],
                sideFrame: [],
                topFrame: [],
                rotationY: 0.3,
                rotationX: -0.1,
                size: 180,
                buildImage: { _ in nil },
                label: "B"
            )
        }
    }
}
