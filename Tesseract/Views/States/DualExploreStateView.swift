// DualExploreStateView.swift
// Tesseract
//
// CameraState.dualExplore(generation) — Phase 1 of the three-phase
// interaction, region-placed (GridLayout.dualExploreScene). Two
// bracket-faced panels (gene A / gene B), swipes steer both genes,
// long-press composes (brackets invert while arming), tap shares the
// tapped panel's export-grade GIF. Cell scrubber + comparative stats.

import SwiftUI

struct DualExploreStateView: View {
    @ObservedObject var camera: CameraManager
    @ObservedObject var animator: DualCubeAnimator
    let generation: Int
    let clock: SurfaceClock

    @State private var pressingA = false
    @State private var pressingB = false

    /// Tap shares the tapped PANEL's export-grade GIF (refreshed by every
    /// NN pass); camera.gifData covers only the pre-first-reprocess window.
    private func share(_ export: Data?) {
        if let data = export ?? camera.gifData {
            GIFSaver.presentShareSheet(data)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            panel(cube: animator.cubeA, pressing: $pressingA,
                  onTap: { share(animator.exportA) },
                  onLongPress: { camera.compose(order: .aIntoB) })
                .place(GridLayout.panelA)

            panel(cube: animator.cubeB, pressing: $pressingB,
                  onTap: { share(animator.exportB) },
                  onLongPress: { camera.compose(order: .bIntoA) })
                .place(GridLayout.panelB)

            scrubber.place(GridLayout.scrubber)
            statsBlock.place(GridLayout.stats)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let speed = sqrt(pow(value.velocity.width, 2) + pow(value.velocity.height, 2))
                    if speed > 500 {
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if abs(dx) > abs(dy) {
                            camera.dualSwipe(dx < 0 ? .left : .right)
                        } else {
                            camera.dualSwipe(dy < 0 ? .up : .down)
                        }
                    }
                }
        )
        .onAppear {
            let cube = camera.buildVoxelCube()
            animator.cubeA = cube
            animator.cubeB = cube
            animator.geneA = camera.geneA
            animator.geneB = camera.geneB
            animator.onOrganism = { gene, beauty, descriptor, gifData, entropy in
                camera.placeOrganism(gene: gene, beauty: beauty, descriptor: descriptor,
                                     gifData: gifData, entropy: entropy)
            }
            animator.startPlayback()
        }
        // Each swipe mutates camera.geneA/B and bumps generation — sync the
        // animator and re-run the NN so the swipe actually produces new GIFs.
        .onChange(of: generation) { _, _ in
            animator.geneA = camera.geneA
            animator.geneB = camera.geneB
            animator.reprocessCubes(axis: .z)
        }
        .onDisappear { animator.stopPlayback() }
    }

    private func panel(cube: VoxelCube, pressing: Binding<Bool>,
                       onTap: @escaping () -> Void,
                       onLongPress: @escaping () -> Void) -> some View {
        ExplorePanel(cube: cube, frameIndex: animator.frameIndex,
                     state: pressing.wrappedValue ? 1 : 0,
                     clock: clock,
                     buildImage: { camera.buildPreviewImage(indices: $0) })
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.5, perform: onLongPress,
                                onPressingChanged: { pressing.wrappedValue = $0 })
    }

    // MARK: - Scrubber (64-atom cell slider, detent per frame)

    private var scrubber: some View {
        CellSlider(
            value: Binding(
                get: { Double(animator.frameIndex) },
                set: { animator.scrub(to: Int($0)) }
            ),
            range: 0...63,
            step: 1,
            tint: Ink.ink,
            cols: 64,
            cell: Lattice.gifPx,
            onEnded: { animator.endScrub() }
        )
        .accessibilityLabel("Frame scrubber")
    }

    // MARK: - Comparative stats + sparklines + hint

    private var statsBlock: some View {
        let f = animator.frameIndex
        return VStack(spacing: Lattice.pt(2)) {
            HStack(spacing: 0) {
                CellText("frame \(f + 1)/\(VoxelCube.size)", rows: TypeRows.micro,
                         ink: Color(srgb8: Ink.ledGhost))
                Spacer(minLength: 0)
                CellText("gen \(generation)", rows: TypeRows.micro,
                         ink: Color(srgb8: Ink.ledGhost))
            }
            CellStatRow(label: "beauty",
                        valueA: fmt(animator.statsA.beauty, at: f),
                        valueB: fmt(animator.statsB.beauty, at: f))
            CellStatRow(label: "entropy",
                        valueA: fmt(animator.statsA.entropy, at: f),
                        valueB: fmt(animator.statsB.entropy, at: f))
            CellStatRow(label: "colors",
                        valueA: fmtInt(animator.statsA.colorsUsed, at: f),
                        valueB: fmtInt(animator.statsB.colorsUsed, at: f))
            if animator.pixelDiff.indices.contains(f) {
                let diff = animator.pixelDiff[f]
                let total = VoxelCube.size * VoxelCube.size
                let pct = Float(diff) / Float(total) * 100
                CellText("diff \(diff)/\(total) (\(String(format: "%.1f", pct))%)",
                         rows: TypeRows.micro, ink: Color(srgb8: Ink.ledGhost))
            }
            HStack(spacing: Lattice.pt(2)) {
                CellText("A", rows: TypeRows.micro, ink: Color(srgb8: Ink.tintA))
                CellSparkline(values: animator.statsA.beauty, tint: Ink.tintA, rows: 4)
            }
            HStack(spacing: Lattice.pt(2)) {
                CellText("B", rows: TypeRows.micro, ink: Color(srgb8: Ink.tintB))
                CellSparkline(values: animator.statsB.beauty, tint: Ink.tintB, rows: 4)
            }
            CellText("↑↓←→ steer · hold compose · tap share", rows: TypeRows.micro,
                     ink: Color(srgb8: Ink.ledGhost))
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
