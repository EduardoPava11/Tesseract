// VoxelCube.swift
// Tesseract
//
// Port of spec/algebra/Cube.hs: the GIF as a 64³ voxel object.
//
// The cube holds 262,144 voxels. Each voxel has a palette index.
// Three projections slice the cube into 64-frame GIFs:
//   Front (x,y sliced by z) → normal GIF playback
//   Side  (y,z sliced by x) → spatiotemporal Y×T
//   Top   (x,z sliced by y) → spatiotemporal X×T
//
// Rotation changes which projection is active.
// The NN updates voxels for the current view.
// The GIF adapts to how you look at it.

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. THE CUBE
// ════════════════════════════════════════════════════════════════

/// 64³ voxel cube. Flat storage: voxels[z * 64 * 64 + y * 64 + x]
struct VoxelCube {
    static let size = 64
    static let totalVoxels = size * size * size  // 262,144

    /// Flat storage: palette indices [0..255]
    var voxels: [UInt8]

    init() {
        voxels = [UInt8](repeating: 0, count: VoxelCube.totalVoxels)
    }

    /// Build from captured frames (front projection: z = frame index)
    init(frames: [[UInt8]]) {
        voxels = [UInt8](repeating: 0, count: VoxelCube.totalVoxels)
        let s = VoxelCube.size
        for z in 0..<min(s, frames.count) {
            let frame = frames[z]
            for y in 0..<s {
                for x in 0..<s {
                    let pixelIdx = y * s + x
                    guard pixelIdx < frame.count else { continue }
                    self[x, y, z] = frame[pixelIdx]
                }
            }
        }
    }

    /// Access voxel at (x, y, z)
    subscript(x: Int, y: Int, z: Int) -> UInt8 {
        get { voxels[z * VoxelCube.size * VoxelCube.size + y * VoxelCube.size + x] }
        set { voxels[z * VoxelCube.size * VoxelCube.size + y * VoxelCube.size + x] = newValue }
    }
}

// ════════════════════════════════════════════════════════════════
// § 2. PROJECTIONS
// ════════════════════════════════════════════════════════════════

/// Which axis to slice through (the "time" axis of the resulting GIF)
enum SliceAxis {
    case z   // Front: (x,y) frames, z = time → normal GIF
    case x   // Side:  (y,z) frames, x = column → spatiotemporal
    case y   // Top:   (x,z) frames, y = row → spatiotemporal
}

extension VoxelCube {

    /// Extract one 64×64 frame by slicing at a given depth along the axis.
    /// Returns flat array of 4096 palette indices.
    func slice(axis: SliceAxis, depth: Int) -> [UInt8] {
        let s = VoxelCube.size
        var frame = [UInt8](repeating: 0, count: s * s)

        for b in 0..<s {
            for a in 0..<s {
                let (x, y, z): (Int, Int, Int)
                switch axis {
                case .z: (x, y, z) = (a, b, depth)     // Front: a=x, b=y
                case .x: (x, y, z) = (depth, a, b)     // Side: a=y, b=z
                case .y: (x, y, z) = (a, depth, b)     // Top: a=x, b=z
                }
                frame[b * s + a] = self[x, y, z]
            }
        }
        return frame
    }

    /// Extract all 64 frames for a given projection → a GIF sequence
    func sliceAll(axis: SliceAxis) -> [[UInt8]] {
        (0..<VoxelCube.size).map { slice(axis: axis, depth: $0) }
    }
}

// ════════════════════════════════════════════════════════════════
// § 3. ROTATION STATE
// ════════════════════════════════════════════════════════════════

/// Rotation state: which face is the user looking at?
struct CubeRotation {
    /// Angle around Y-axis in radians (left/right rotation)
    var angleY: Float = 0

    /// Angle around X-axis in radians (up/down rotation)
    var angleX: Float = 0

    /// Which slice axis is dominant (closest face)?
    var dominantAxis: SliceAxis {
        // Normalize to [0, 2π)
        let ny = ((angleY.truncatingRemainder(dividingBy: 2 * .pi)) + 2 * .pi)
            .truncatingRemainder(dividingBy: 2 * .pi)

        // Check X-axis rotation first (up/down)
        let nx = ((angleX.truncatingRemainder(dividingBy: 2 * .pi)) + 2 * .pi)
            .truncatingRemainder(dividingBy: 2 * .pi)

        // If rotated significantly around X, top face is dominant
        if nx > .pi / 4 && nx < 3 * .pi / 4 { return .y }
        if nx > 5 * .pi / 4 && nx < 7 * .pi / 4 { return .y }

        // Otherwise, Y-axis rotation determines front vs side
        if ny > .pi / 4 && ny < 3 * .pi / 4 { return .x }      // side
        if ny > 5 * .pi / 4 && ny < 7 * .pi / 4 { return .x }  // other side
        return .z  // front (or back)
    }

    /// Blend factor: how much we're transitioning between faces (0=settled, 1=crossover)
    var blendFactor: Float {
        let within = (angleY.truncatingRemainder(dividingBy: .pi / 2)) / (.pi / 2)
        let norm = abs(within)
        return norm < 0.5 ? norm * 2 : (1 - norm) * 2
    }

    /// Is the current view reversed? (back face = front played backwards)
    var isReversed: Bool {
        let ny = ((angleY.truncatingRemainder(dividingBy: 2 * .pi)) + 2 * .pi)
            .truncatingRemainder(dividingBy: 2 * .pi)
        return ny > .pi / 2 && ny < 3 * .pi / 2
    }
}

// ════════════════════════════════════════════════════════════════
// § 4. THE UPDATE: NN re-processes for the current view
//
// When the dominant axis changes, the NN re-computes the voxels
// visible in the new projection. This is the core animation:
// the GIF CHANGES as the user rotates the cube.
//
// updateForView: extract current face's frames → NN processes →
// write back into the cube → display updates.
// ════════════════════════════════════════════════════════════════

extension VoxelCube {

    /// Update voxels for a given projection using a processing function.
    /// The function takes a frame (64×64 palette indices) + depth index
    /// and returns updated palette indices.
    mutating func updateForView(
        axis: SliceAxis,
        process: (_ frame: [UInt8], _ depth: Int) -> [UInt8]
    ) {
        let s = VoxelCube.size
        for depth in 0..<s {
            let oldFrame = slice(axis: axis, depth: depth)
            let newFrame = process(oldFrame, depth)

            // Write back
            for b in 0..<s {
                for a in 0..<s {
                    let (x, y, z): (Int, Int, Int)
                    switch axis {
                    case .z: (x, y, z) = (a, b, depth)
                    case .x: (x, y, z) = (depth, a, b)
                    case .y: (x, y, z) = (a, depth, b)
                    }
                    self[x, y, z] = newFrame[b * s + a]
                }
            }
        }
    }
}

// ════════════════════════════════════════════════════════════════
// § 5. PLAYBACK: extract current GIF from the cube
// ════════════════════════════════════════════════════════════════

extension VoxelCube {

    /// Get the current GIF frames based on rotation state.
    /// If reversed (back face), frames play backwards.
    func currentGIF(rotation: CubeRotation) -> [[UInt8]] {
        let axis = rotation.dominantAxis
        var frames = sliceAll(axis: axis)
        if rotation.isReversed {
            frames.reverse()
        }
        return frames
    }
}
