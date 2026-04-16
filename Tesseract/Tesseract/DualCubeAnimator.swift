// DualCubeAnimator.swift
// Tesseract
//
// Two GIFs side by side, playing in sync at 20fps.
// Each GIF is a POINT in the gene's dimensional space.
// The user sees two options — two ways the NN interprets the capture.
//
// When the cube rotates to a new face:
//   1. The OLD GIF keeps playing in the new orientation (no freeze)
//   2. The NN recomputes in the background
//   3. A curtain effect reveals the NEW GIF row-by-row
//      in the direction of the rotation
//
// The curtain: a moving boundary (row or column) slides across.
// Pixels above the boundary = new GIF. Below = old GIF.
// This creates a smooth reveal that follows the rotation direction.

import Foundation
import Combine

/// Drives two synchronized GIF cubes with curtain reveal on rotation.
@MainActor
class DualCubeAnimator: ObservableObject {

    // ── Display State ──

    /// Front frames playing in sync
    @Published var frameA: [UInt8] = []   // front face for cube A
    @Published var frameB: [UInt8] = []   // front face for cube B
    /// Side projection frames (spatiotemporal Y×T)
    @Published var sideFrameA: [UInt8] = []
    @Published var sideFrameB: [UInt8] = []
    /// Top projection frames (spatiotemporal X×T)
    @Published var topFrameA: [UInt8] = []
    @Published var topFrameB: [UInt8] = []
    @Published var frameIndex: Int = 0
    @Published var totalFrames: Int = 64
    @Published var isPlaying: Bool = true

    /// Curtain reveal progress: 0 = all old, 1 = all new
    @Published var curtainProgress: Float = 1.0

    /// Curtain direction: which way the new GIF slides in
    @Published var curtainDirection: CurtainDirection = .none

    /// Rotation state
    @Published var rotation = CubeRotation()

    // ── Cubes ──

    /// Two cubes = two points in gene space
    var cubeA: VoxelCube
    var cubeB: VoxelCube

    /// Gene A and Gene B — two different aesthetic interpretations
    var geneA: GeneWeights
    var geneB: GeneWeights

    /// Frames before NN update (for curtain blend)
    var oldFramesA: [[UInt8]] = []
    var newFramesA: [[UInt8]] = []
    var oldFramesB: [[UInt8]] = []
    var newFramesB: [[UInt8]] = []

    /// Cached side/top projections (recomputed only on cube/gene change, not per frame)
    private var cachedSideA: [[UInt8]] = []
    private var cachedSideB: [[UInt8]] = []
    private var cachedTopA: [[UInt8]] = []
    private var cachedTopB: [[UInt8]] = []

    /// Rebuild side/top caches (call when cubes change, NOT per frame)
    func rebuildProjectionCaches() {
        cachedSideA = cubeA.sliceAll(axis: .x)
        cachedSideB = cubeB.sliceAll(axis: .x)
        cachedTopA = cubeA.sliceAll(axis: .y)
        cachedTopB = cubeB.sliceAll(axis: .y)
    }

    /// Which axis was last dominant
    private var lastAxis: SliceAxis = .z

    /// Timer for 20fps sync
    private var timer: Timer?

    // ── Init ──

    init(cubeA: VoxelCube, cubeB: VoxelCube,
         geneA: GeneWeights = .defaultWeights(),
         geneB: GeneWeights = .defaultWeights()) {
        self.cubeA = cubeA
        self.cubeB = cubeB
        self.geneA = geneA
        self.geneB = geneB

        let framesA = cubeA.sliceAll(axis: .z)
        let framesB = cubeB.sliceAll(axis: .z)
        self.newFramesA = framesA
        self.newFramesB = framesB
        self.oldFramesA = framesA
        self.oldFramesB = framesB
        self.totalFrames = framesA.count

        if let f = framesA.first { self.frameA = f }
        if let f = framesB.first { self.frameB = f }

        // Cache side/top projections once at init
        rebuildProjectionCaches()
    }

    // ── Playback (20fps, synced) ──

    func startPlayback() {
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                self.advanceFrame()
            }
        }
    }

    func stopPlayback() {
        isPlaying = false
        timer?.invalidate()
    }

    private func advanceFrame() {
        guard totalFrames > 0 else { return }
        frameIndex = (frameIndex + 1) % totalFrames

        // Blend old and new frames based on curtain progress
        if curtainProgress >= 1.0 {
            // Curtain complete: show new frames directly
            frameA = newFramesA.indices.contains(frameIndex) ? newFramesA[frameIndex] : []
            frameB = newFramesB.indices.contains(frameIndex) ? newFramesB[frameIndex] : []
            // Side/top from CACHED projections (not recomputed per frame)
            sideFrameA = cachedSideA.indices.contains(frameIndex) ? cachedSideA[frameIndex] : []
            sideFrameB = cachedSideB.indices.contains(frameIndex) ? cachedSideB[frameIndex] : []
            topFrameA = cachedTopA.indices.contains(frameIndex) ? cachedTopA[frameIndex] : []
            topFrameB = cachedTopB.indices.contains(frameIndex) ? cachedTopB[frameIndex] : []
        } else {
            // Curtain in progress: blend row-by-row
            frameA = blendWithCurtain(
                old: oldFramesA.indices.contains(frameIndex) ? oldFramesA[frameIndex] : [],
                new: newFramesA.indices.contains(frameIndex) ? newFramesA[frameIndex] : []
            )
            frameB = blendWithCurtain(
                old: oldFramesB.indices.contains(frameIndex) ? oldFramesB[frameIndex] : [],
                new: newFramesB.indices.contains(frameIndex) ? newFramesB[frameIndex] : []
            )
            // Advance curtain
            curtainProgress += 1.0 / 20.0  // reveal over ~1 second (20 frames)
            curtainProgress = min(1.0, curtainProgress)
        }
    }

    // ── Curtain Blend ──

    /// Blend old and new frames with a sliding boundary.
    /// The boundary moves in the curtain direction.
    private func blendWithCurtain(old: [UInt8], new: [UInt8]) -> [UInt8] {
        let s = VoxelCube.size
        guard old.count == s * s, new.count == s * s else { return new }

        var result = old
        let boundary = Int(curtainProgress * Float(s))

        switch curtainDirection {
        case .left:
            // New pixels slide in from the right
            for y in 0..<s {
                for x in (s - boundary)..<s {
                    result[y * s + x] = new[y * s + x]
                }
            }
        case .right:
            // New pixels slide in from the left
            for y in 0..<s {
                for x in 0..<boundary {
                    result[y * s + x] = new[y * s + x]
                }
            }
        case .up:
            // New pixels slide in from the bottom
            for y in (s - boundary)..<s {
                for x in 0..<s {
                    result[y * s + x] = new[y * s + x]
                }
            }
        case .down:
            // New pixels slide in from the top
            for y in 0..<boundary {
                for x in 0..<s {
                    result[y * s + x] = new[y * s + x]
                }
            }
        case .none:
            return new
        }
        return result
    }

    // ── Rotation ──

    /// User dragged: update rotation, trigger NN if face changed
    func rotate(deltaX: Float, deltaY: Float) {
        rotation.angleY += deltaX * 0.01
        rotation.angleX += deltaY * 0.01

        let newAxis = rotation.dominantAxis

        if newAxis != lastAxis {
            // Face changed → start curtain reveal
            curtainDirection = curtainDirectionFrom(oldAxis: lastAxis, newAxis: newAxis, deltaX: deltaX, deltaY: deltaY)
            curtainProgress = 0

            // Save old frames (they keep playing during NN compute)
            oldFramesA = newFramesA
            oldFramesB = newFramesB

            // Immediately slice the old voxels in the new orientation
            // (this is fast — just re-indexing, no NN)
            newFramesA = cubeA.sliceAll(axis: newAxis)
            newFramesB = cubeB.sliceAll(axis: newAxis)
            totalFrames = newFramesA.count

            // Trigger NN update in background
            recomputeInBackground(axis: newAxis)

            lastAxis = newAxis
        }
    }

    /// Determine curtain slide direction from the rotation gesture
    private func curtainDirectionFrom(oldAxis: SliceAxis, newAxis: SliceAxis,
                                       deltaX: Float, deltaY: Float) -> CurtainDirection {
        if abs(deltaX) > abs(deltaY) {
            return deltaX > 0 ? .left : .right
        } else {
            return deltaY > 0 ? .up : .down
        }
    }

    // ── NN Background Update ──

    /// Re-process voxels for the new view. Runs on a background thread.
    /// When done, updates newFrames → curtain reveals the result.
    private func recomputeInBackground(axis: SliceAxis) {
        let gA = geneA
        let gB = geneB
        var localCubeA = cubeA
        var localCubeB = cubeB

        Task.detached(priority: .userInitiated) {
            // NN forward pass on both cubes
            localCubeA.updateForView(axis: axis) { frame, depth in
                Self.processFrame(frame: frame, depth: depth, totalFrames: VoxelCube.size, gene: gA)
            }
            localCubeB.updateForView(axis: axis) { frame, depth in
                Self.processFrame(frame: frame, depth: depth, totalFrames: VoxelCube.size, gene: gB)
            }

            let framesA = localCubeA.sliceAll(axis: axis)
            let framesB = localCubeB.sliceAll(axis: axis)

            await MainActor.run {
                self.cubeA = localCubeA
                self.cubeB = localCubeB
                self.newFramesA = framesA
                self.newFramesB = framesB
                self.rebuildProjectionCaches()  // rebuild side/top after NN update
            }
        }
    }

    /// Process one frame using the gene (CPU path)
    nonisolated private static func processFrame(
        frame: [UInt8], depth: Int, totalFrames: Int, gene: GeneWeights
    ) -> [UInt8] {
        let frameNorm: Float = totalFrames > 1 ? Float(depth) / Float(totalFrames - 1) : 0
        var newFrame = frame

        for i in 0..<frame.count {
            let idx = Int(frame[i])
            let d = idx / 64
            let a = (idx % 64) / 16
            let b = (idx % 16) / 4
            let c = idx % 4

            var input = [Float](repeating: 0, count: GeneWeights.inputDim)
            let rBin = min(13, a * 4 + 1)
            let gBin = min(13, b * 4 + 1)
            let bBin = min(13, c * 4 + 1)

            for scale in 0..<3 {
                input[0 * 42 + scale * 14 + rBin] = 1.0
                input[1 * 42 + scale * 14 + gBin] = 1.0
                input[2 * 42 + scale * 14 + bBin] = 1.0
            }
            input[126] = 0.5; input[127] = frameNorm
            input[128] = 144; input[129] = 36; input[130] = 9; input[131] = 16
            for j in 132..<137 { input[j] = 1.0 }

            let (newIdx, _) = gene.forward(input)
            newFrame[i] = newIdx
        }
        return newFrame
    }
}

// ── Curtain Direction ──

enum CurtainDirection {
    case left, right, up, down, none
}
