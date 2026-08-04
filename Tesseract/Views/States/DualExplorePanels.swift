// DualExplorePanels.swift
// Tesseract
//
// The dual-explore panel: a 68×68-cell bracket-faced control whose
// content is the 64×64 GIF frame plus its two orthographic projection
// strips living IN the gutter ring (top = X×Time, left = Y×Time, each
// exactly 1 atom thick). Replaces CubeGIFView's GIFPanel. The bracket
// rect is the hit rect; pressed (long-press arming) inverts the face.

import SwiftUI
import simd

/// One explore panel. Footprint = 64 + 2·(gutter 1 + bracket 1) = 68.
struct ExplorePanel: View {
    let cube: VoxelCube
    let frameIndex: Int
    /// Ordinal into CellMechanics.controlStates (0 idle · 1 pressed).
    let state: Int
    let clock: SurfaceClock
    let buildImage: ([UInt8]) -> CGImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ControlBrackets(side: TesseractLattice.previewCells, state: state,
                            tick: clock.tick, reduceMotion: clock.reduceMotion)

            // Top gutter: X×Time slice (center row), 64×1 atoms.
            stripImage(cube.slice(axis: .y, depth: 32))
                .frame(width: Lattice.gif(64), height: Lattice.gif(1))
                .padding(.top, Lattice.gif(1))
                .padding(.leading, Lattice.gif(2))

            // Left gutter: Y×Time slice (center column), 1×64 atoms.
            stripImage(cube.slice(axis: .x, depth: 32))
                .frame(width: Lattice.gif(1), height: Lattice.gif(64))
                .padding(.top, Lattice.gif(2))
                .padding(.leading, Lattice.gif(1))

            // The frame itself: 64 cells at the atom.
            mainFrame
                .frame(width: Lattice.gif(64), height: Lattice.gif(64))
                .padding(.top, Lattice.gif(2))
                .padding(.leading, Lattice.gif(2))
        }
        .frame(width: Lattice.gif(68), height: Lattice.gif(68))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var mainFrame: some View {
        let indices = cube.slice(axis: .z, depth: frameIndex)
        if !indices.isEmpty, let cg = buildImage(indices) {
            Image(decorative: cg, scale: 1.0)
                .interpolation(.none)
                .resizable()
        } else {
            Color(srgb8: CellChecker.dark)
        }
    }

    @ViewBuilder private func stripImage(_ indices: [UInt8]) -> some View {
        if !indices.isEmpty, let cg = buildImage(indices) {
            Image(decorative: cg, scale: 1.0)
                .interpolation(.none)
                .resizable()
        } else {
            Color(srgb8: CellChecker.dark)
        }
    }
}

/// A per-frame series drawn as cells: one column per frame, the value's
/// row lit in `tint`. Replaces the stroked SparklineView.
struct CellSparkline: View {
    let values: [Float]
    let tint: SIMD3<UInt8>
    /// Height in text cells (2pt); width = one cell per value.
    var rows: Int = 8

    var body: some View {
        let maxV = values.max() ?? 1
        let minV = values.min() ?? 0
        let range = max(maxV - minV, 0.001)
        CellSprite(cols: max(1, values.count), rows: rows, cellPt: Lattice.pt(1)) { c, r in
            guard values.indices.contains(c) else { return nil }
            let norm = (values[c] - minV) / range
            let y = min(rows - 1, Int((1 - norm) * Float(rows - 1) + 0.5))
            return r == y ? tint : nil
        }
        .accessibilityHidden(true)
    }
}

/// Label + A value + B value in the gene tints.
struct CellStatRow: View {
    let label: String
    let valueA: String
    let valueB: String

    var body: some View {
        HStack(spacing: 0) {
            CellText(label, rows: TypeRows.micro, ink: Color(srgb8: Ink.ledGhost))
                .frame(width: Lattice.gif(14), alignment: .leading)
            Spacer(minLength: 0)
            CellText("A:\(valueA)", rows: TypeRows.micro, ink: Color(srgb8: Ink.tintA))
            Spacer(minLength: 0)
            CellText("B:\(valueB)", rows: TypeRows.micro, ink: Color(srgb8: Ink.tintB))
        }
    }
}
