// CubeAnimator.swift
// Tesseract
//
// The animation loop: rotation → re-slice → NN update → display.
//
// The user sees a GIF. They drag to rotate the cube.
// As the cube rotates, a new face becomes visible.
// The NN re-processes the voxels for the new face.
// The GIF changes — it adapts to how you look at it.
//
// The rotation IS the interaction.
// The voxel update IS the animation.
// The cube IS the memory.

import Foundation

/// Drives the cube rotation → NN update → GIF display loop.
@MainActor
class CubeAnimator: ObservableObject {

    // ── State ──

    @Published var rotation = CubeRotation()
    @Published var currentFrames: [[UInt8]] = []
    @Published var frameIndex: Int = 0
    @Published var isPlaying: Bool = true

    /// The voxel cube (262,144 palette indices)
    private(set) var cube: VoxelCube

    /// The gene that processes each view
    var gene: GeneWeights

    /// Which axis was last processed by the NN
    private var lastProcessedAxis: SliceAxis = .z

    /// Display timer (20fps)
    private var displayTimer: Timer?

    // ── Init ──

    init(cube: VoxelCube, gene: GeneWeights = .defaultWeights()) {
        self.cube = cube
        self.gene = gene
        self.currentFrames = cube.sliceAll(axis: .z)
    }

    // ── Playback ──

    func startPlayback() {
        isPlaying = true
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying, !self.currentFrames.isEmpty else { return }
                self.frameIndex = (self.frameIndex + 1) % self.currentFrames.count
            }
        }
    }

    func stopPlayback() {
        isPlaying = false
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // ── Rotation (from user gesture) ──

    /// User dragged: update rotation and check if view changed
    func rotate(deltaX: Float, deltaY: Float) {
        rotation.angleY += deltaX * 0.01   // horizontal drag → Y rotation
        rotation.angleX += deltaY * 0.01   // vertical drag → X rotation

        let newAxis = rotation.dominantAxis

        // If the dominant face changed, trigger NN update
        if newAxis != lastProcessedAxis {
            updateForCurrentView()
            lastProcessedAxis = newAxis
        }

        // Always re-extract current frames (even if axis didn't change,
        // the reversed flag might have changed)
        currentFrames = cube.currentGIF(rotation: rotation)
        frameIndex = frameIndex % max(1, currentFrames.count)
    }

    // ── NN Update ──

    /// Re-process voxels for the current dominant view.
    /// This is where the gene forward pass runs.
    /// The GIF changes because the voxels change.
    func updateForCurrentView() {
        let axis = rotation.dominantAxis

        // NN processes each frame via the REAL residual pipeline.
        // Reconstructs RGB from palette indices → builds BlockPyramids → residualQuantize.
        cube.updateForView(axis: axis) { [gene] frame, depth in
            let s = VoxelCube.size
            guard frame.count == s * s else { return frame }

            // Reconstruct approximate RGB from palette indices
            let rgb: [(Float, Float, Float)] = frame.map { idx in
                let a = Float((Int(idx) % 64) / 16)
                let b = Float((Int(idx) % 16) / 4)
                let c = Float(Int(idx) % 4)
                return ((a + 0.5) / 4.0, (b + 0.5) / 4.0, (c + 0.5) / 4.0)
            }

            // Build real pyramids
            let depths = [Float](repeating: 0.5, count: s * s)
            let pyramids = BlockPyramid.computeAll(
                rgb: rgb, depths: depths,
                frameIndex: depth, totalFrames: s
            )

            // Residual pipeline for each pixel
            var newFrame = frame
            for i in 0..<min(frame.count, pyramids.count) {
                let (idx, _) = residualQuantize(
                    gene: gene, pyramid: pyramids[i],
                    frameIndex: depth, mode: .training
                )
                newFrame[i] = idx
            }
            return newFrame
        }

        // Update displayed frames
        currentFrames = cube.currentGIF(rotation: rotation)
    }

    // ── Build from captured data ──

    /// Build a VoxelCube from the app's captured frames
    static func fromCapture(frames: [CapturedFrame]) -> VoxelCube {
        // First, quantize all frames using PerfectQuantizer
        let paletteFrames: [[UInt8]] = frames.map { frame in
            PerfectQuantizer.quantizeFrame(
                frameIndex: frame.index,
                rgb: frame.rgb,
                depths: frame.depths
            )
        }
        return VoxelCube(frames: paletteFrames)
    }
}
