// DualGIFExploreView.swift
// Tesseract
//
// STACKED vertical layout: GIF A on top, GIF B below.
// Each GIF at 256×256 (64px at 4× nearest-neighbor) with
// orthographic projection strips: top = 256×4, side = 4×256.
// Frame scrubber, comparative stats, sparklines.

import SwiftUI

// ════════════════════════════════════════════════════════════════
// § 1. SINGLE GIF FRAME (palette indices → 256×256 image)
// ════════════════════════════════════════════════════════════════

struct GIFFrameImage: View {
    let indices: [UInt8]
    let size: CGFloat
    let buildImage: ([UInt8]) -> CGImage?

    var body: some View {
        if !indices.isEmpty, let cgImage = buildImage(indices) {
            Image(decorative: cgImage, scale: 1.0)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.05))
                .frame(width: size, height: size)
        }
    }
}

// ════════════════════════════════════════════════════════════════
// § 2. PROJECTION STRIP (256×4 top or 4×256 side)
//
// Shows a spatiotemporal slice with a frame indicator line.
// Top strip: 64×64 displayed at 256pt × 4pt (X × Time)
// Side strip: 64×64 displayed at 4pt × 256pt (Y × Time)
// ════════════════════════════════════════════════════════════════

struct ProjectionStrip: View {
    let indices: [UInt8]
    let frameIndex: Int
    let isHorizontal: Bool   // true = top (256×4), false = side (4×256)
    let length: CGFloat      // 256pt (matches GIF dimension)
    let thickness: CGFloat   // 4pt
    let buildImage: ([UInt8]) -> CGImage?

    var body: some View {
        ZStack {
            if !indices.isEmpty, let cgImage = buildImage(indices) {
                Image(decorative: cgImage, scale: 1.0)
                    .interpolation(.none)
                    .resizable()
                    .frame(
                        width: isHorizontal ? length : thickness,
                        height: isHorizontal ? thickness : length
                    )
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.03))
                    .frame(
                        width: isHorizontal ? length : thickness,
                        height: isHorizontal ? thickness : length
                    )
            }

            // Frame indicator line
            let frac = CGFloat(frameIndex) / 63.0
            if isHorizontal {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 1, height: thickness)
                        .position(x: frac * geo.size.width, y: geo.size.height / 2)
                }
                .frame(width: length, height: thickness)
            } else {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: thickness, height: 1)
                        .position(x: geo.size.width / 2, y: frac * geo.size.height)
                }
                .frame(width: thickness, height: length)
            }
        }
    }
}

// ════════════════════════════════════════════════════════════════
// § 3. SPARKLINE
// ════════════════════════════════════════════════════════════════

struct SparklineView: View {
    let values: [Float]
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            if values.count > 1 {
                let maxV = values.max() ?? 1
                let minV = values.min() ?? 0
                let range = max(maxV - minV, 0.001)
                Path { path in
                    for (i, v) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((v - minV) / range))
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, lineWidth: 1)
            }
        }
        .frame(height: height)
    }
}

// ════════════════════════════════════════════════════════════════
// § 4. STAT ROW (label + A value + B value)
// ════════════════════════════════════════════════════════════════

struct StatRow: View {
    let label: String
    let valueA: String
    let valueB: String

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 56, alignment: .leading)
            Spacer()
            Text("A:\(valueA)")
                .foregroundStyle(.cyan.opacity(0.6))
            Spacer()
            Text("B:\(valueB)")
                .foregroundStyle(.orange.opacity(0.6))
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(.white.opacity(0.4))
    }
}

// ════════════════════════════════════════════════════════════════
// § 5. SINGLE GIF PANEL (GIF + top strip + side strip + label)
// ════════════════════════════════════════════════════════════════

struct GIFPanel: View {
    let cube: VoxelCube
    let frameIndex: Int
    let label: String
    let buildImage: ([UInt8]) -> CGImage?

    private let gifSize: CGFloat = 256
    private let stripThickness: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            // Top strip: X×Time at center row (y=32)
            HStack(spacing: 0) {
                // Spacer for side strip alignment
                Color.clear.frame(width: stripThickness, height: stripThickness)

                ProjectionStrip(
                    indices: cube.slice(axis: .y, depth: 32),
                    frameIndex: frameIndex,
                    isHorizontal: true,
                    length: gifSize,
                    thickness: stripThickness,
                    buildImage: buildImage
                )
            }

            HStack(spacing: 0) {
                // Side strip: Y×Time at center column (x=32)
                ProjectionStrip(
                    indices: cube.slice(axis: .x, depth: 32),
                    frameIndex: frameIndex,
                    isHorizontal: false,
                    length: gifSize,
                    thickness: stripThickness,
                    buildImage: buildImage
                )

                // Main GIF frame
                GIFFrameImage(
                    indices: cube.slice(axis: .z, depth: frameIndex),
                    size: gifSize,
                    buildImage: buildImage
                )
            }

            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 2)
        }
    }
}

// ════════════════════════════════════════════════════════════════
// § 6. FULL DUAL GIF EXPLORE VIEW (STACKED VERTICAL)
// ════════════════════════════════════════════════════════════════

struct DualGIFExploreView: View {
    @ObservedObject var animator: DualCubeAnimator
    let generation: Int
    let buildImage: ([UInt8]) -> CGImage?
    let onTapA: () -> Void
    let onTapB: () -> Void
    let onLongPressA: () -> Void
    let onLongPressB: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {

                // ── GIF A ──
                GIFPanel(
                    cube: animator.cubeA,
                    frameIndex: animator.frameIndex,
                    label: "A",
                    buildImage: buildImage
                )
                .onTapGesture(perform: onTapA)
                .onLongPressGesture(perform: onLongPressA)

                // ── GIF B ──
                GIFPanel(
                    cube: animator.cubeB,
                    frameIndex: animator.frameIndex,
                    label: "B",
                    buildImage: buildImage
                )
                .onTapGesture(perform: onTapB)
                .onLongPressGesture(perform: onLongPressB)

                // ── Frame scrubber ──
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { Double(animator.frameIndex) },
                            set: { animator.scrub(to: Int($0)) }
                        ),
                        in: 0...63,
                        step: 1,
                        onEditingChanged: { editing in
                            if !editing { animator.endScrub() }
                        }
                    )
                    .tint(.white.opacity(0.3))

                    HStack {
                        Text("frame \(animator.frameIndex + 1)/\(VoxelCube.size)")
                        Spacer()
                        Text("gen \(generation)")
                    }
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                }
                .padding(.horizontal, 20)

                // ── Comparative stats ──
                let f = animator.frameIndex
                VStack(spacing: 2) {
                    StatRow(
                        label: "beauty",
                        valueA: fmt(animator.statsA.beauty, at: f),
                        valueB: fmt(animator.statsB.beauty, at: f)
                    )
                    StatRow(
                        label: "entropy",
                        valueA: fmt(animator.statsA.entropy, at: f),
                        valueB: fmt(animator.statsB.entropy, at: f)
                    )
                    StatRow(
                        label: "colors",
                        valueA: fmtInt(animator.statsA.colorsUsed, at: f),
                        valueB: fmtInt(animator.statsB.colorsUsed, at: f)
                    )

                    if animator.pixelDiff.indices.contains(f) {
                        let diff = animator.pixelDiff[f]
                        let total = VoxelCube.size * VoxelCube.size
                        let pct = Float(diff) / Float(total) * 100
                        Text("diff: \(diff)/\(total) (\(String(format: "%.1f", pct))%)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 20)

                // ── Beauty sparklines ──
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        Text("A")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.5))
                            .frame(width: 10)
                        SparklineView(values: animator.statsA.beauty, color: .cyan, height: 18)
                    }
                    HStack(spacing: 4) {
                        Text("B")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(.orange.opacity(0.5))
                            .frame(width: 10)
                        SparklineView(values: animator.statsB.beauty, color: .orange, height: 18)
                    }
                }
                .padding(.horizontal, 20)

                Text("↑↓←→ steer · hold compose")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.15))
                    .padding(.bottom, 4)
            }
        }
    }

    private func fmt(_ values: [Float], at i: Int) -> String {
        guard values.indices.contains(i) else { return "-" }
        return String(format: "%.2f", values[i])
    }

    private func fmtInt(_ values: [Int], at i: Int) -> String {
        guard values.indices.contains(i) else { return "-" }
        return "\(values[i])"
    }
}
