// RefiningStateView.swift
// Tesseract
//
// CameraState.refining(alpha) — Phase 3, region-placed
// (GridLayout.refiningScene). Single composite GIF in a bracket face;
// rotation gesture adjusts α; tap re-encodes at the on-screen gene/α
// (brackets go BUSY while encoding — the control language expressing
// the export honestly) and then shares.

import SwiftUI

struct RefiningStateView: View {
    @ObservedObject var camera: CameraManager
    @ObservedObject var animator: DualCubeAnimator
    let alpha: Float
    let clock: SurfaceClock
    let onExport: (Data) -> Void

    @State private var exporting = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            composite.place(GridLayout.refineGif)
            CellText("α = \(String(format: "%.2f", alpha))", rows: TypeRows.body)
                .place(GridLayout.alphaReadout)
            hints.place(GridLayout.refHints)
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
    }

    // The composite frame inside a bracket face: idle BEAT invites the
    // tap; BUSY (reject red) while the export re-encodes.
    private var composite: some View {
        ZStack(alignment: .topLeading) {
            ControlBrackets(side: TesseractLattice.previewCells,
                            state: exporting ? 2 : 0,
                            tick: clock.tick, reduceMotion: clock.reduceMotion)
            compositeFrame
                .frame(width: Lattice.gif(64), height: Lattice.gif(64))
                .padding(.top, Lattice.gif(2))
                .padding(.leading, Lattice.gif(2))
        }
        .frame(width: Lattice.gif(68), height: Lattice.gif(68))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !exporting else { return }
            exporting = true
            // Re-encodes at the on-screen gene/α, THEN shares — the old
            // path shared the pre-steering gifData.
            camera.exportCurrent { data in
                exporting = false
                onExport(data)
            }
        }
        .accessibilityLabel("Export composite GIF")
    }

    @ViewBuilder private var compositeFrame: some View {
        let refineFrame = animator.cubeA.slice(axis: .z, depth: animator.frameIndex)
        if !refineFrame.isEmpty, let image = camera.buildPreviewImage(indices: refineFrame) {
            Image(decorative: image, scale: 1.0)
                .interpolation(.none)
                .resizable()
        } else {
            Color(srgb8: CellChecker.dark)
        }
    }

    private var hints: some View {
        HStack(spacing: Lattice.gif(4)) {
            CellText("↺ base", rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
            CellText("tap export", rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
            CellText("other ↻", rows: TypeRows.label, ink: Color(srgb8: Ink.ledGhost))
        }
    }
}
