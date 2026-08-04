// DualExploreStateView.swift
// Tesseract
//
// CameraState.dualExplore(generation) — Phase 1 of the three-phase
// interaction. Two GIFs (gene A / gene B), swipes steer both genes,
// long-press composes, tap shares.

import SwiftUI

struct DualExploreStateView: View {
    @ObservedObject var camera: CameraManager
    @ObservedObject var animator: DualCubeAnimator
    let generation: Int
    let onShare: () -> Void

    var body: some View {
        DualGIFExploreView(
            animator: animator,
            generation: generation,
            buildImage: { camera.buildPreviewImage(indices: $0) },
            onTapA: onShare,
            onTapB: onShare,
            onLongPressA: { camera.compose(order: .aIntoB) },
            onLongPressB: { camera.compose(order: .bIntoA) }
        )
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
}
