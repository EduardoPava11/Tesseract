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

        // The NN processes each frame of the current projection.
        // For now: use the gene CPU forward pass.
        // In production: Metal geneForward kernel for real-time.
        cube.updateForView(axis: axis) { [gene] frame, depth in
            // Each pixel in the frame → gene forward → new palette index
            let frameCount = VoxelCube.size
            let frameNorm: Float = frameCount > 1 ? Float(depth) / Float(frameCount - 1) : 0

            var newFrame = frame
            for i in 0..<frame.count {
                // Build minimal input (approximate — full pyramid in production)
                var input = [Float](repeating: 0, count: GeneWeights.inputDim)

                // The existing palette index tells us the current (d,a,b,c)
                let idx = Int(frame[i])
                let d = idx / 64
                let a = (idx % 64) / 16
                let b = (idx % 16) / 4
                let c = idx % 4

                // Peak the histogram at the current level's bins
                // (approximate: in production, use actual block histograms)
                let rBin = min(13, a * 4 + 1)
                let gBin = min(13, b * 4 + 1)
                let bBin = min(13, c * 4 + 1)

                for scale in 0..<3 {
                    input[0 * 42 + scale * 14 + rBin] = 1.0  // R peaked
                    input[1 * 42 + scale * 14 + gBin] = 1.0  // G peaked
                    input[2 * 42 + scale * 14 + bBin] = 1.0  // B peaked
                }

                // Metadata
                input[126] = 0.5          // depth (unknown in side view)
                input[127] = frameNorm    // frame position
                input[128] = 144; input[129] = 36; input[130] = 9  // sample counts
                input[131] = 16  // depth samples
                for j in 132..<137 { input[j] = 1.0 }  // entropy (uniform)

                let (newIdx, _g) = gene.forward(input)
                newFrame[i] = newIdx
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
