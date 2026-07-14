// DualCubeAnimator.swift
// Tesseract
//
// Drives two flat GIFs side-by-side at 20fps with frame scrubbing.
// Each GIF is a different NN interpretation of the same captured data.
// Computes per-frame stats (beauty, entropy, colors, motion, diff).
//
// On startup: immediately runs the NN for both genes so A ≠ B from frame 1.

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.tesseract.app", category: "DualCubeAnimator")

@MainActor
class DualCubeAnimator: ObservableObject {

    // ── Playback ──

    @Published var frameIndex: Int = 0
    @Published var isScrubbing: Bool = false
    @Published var isPlaying: Bool = true

    // ── Stats ──

    @Published var statsA: GIFFrameStats = .empty
    @Published var statsB: GIFFrameStats = .empty
    @Published var pixelDiff: [Int] = []

    // ── Cube version (bumped when NN finishes) ──

    @Published var cubeVersion: Int = 0

    // ── Cubes + Genes ──

    var cubeA: VoxelCube
    var cubeB: VoxelCube
    var geneA: GeneWeights
    var geneB: GeneWeights

    private var timer: Timer?

    // ── Init ──

    init(cubeA: VoxelCube, cubeB: VoxelCube,
         geneA: GeneWeights = .defaultWeights(),
         geneB: GeneWeights = .defaultWeights()) {
        self.cubeA = cubeA
        self.cubeB = cubeB
        self.geneA = geneA
        self.geneB = geneB
    }

    // ── Playback ──

    func startPlayback() {
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying, !self.isScrubbing else { return }
                self.frameIndex = (self.frameIndex + 1) % VoxelCube.size
            }
        }

        // Run NN immediately so A and B diverge from frame 1
        reprocessCubes(axis: .z)
    }

    func stopPlayback() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    // ── Scrubbing ──

    func scrub(to frame: Int) {
        isScrubbing = true
        frameIndex = max(0, min(VoxelCube.size - 1, frame))
    }

    func endScrub() {
        isScrubbing = false
    }

    // ── NN Reprocessing ──

    func reprocessCubes(axis: SliceAxis) {
        logger.info("DualCubeAnimator: reprocessing cubes (axis=\(String(describing: axis)))")
        let gA = geneA
        let gB = geneB
        var localCubeA = cubeA
        var localCubeB = cubeB

        Task.detached(priority: .userInitiated) {
            localCubeA.updateForView(axis: axis) { frame, depth in
                Self.processFrame(frame: frame, depth: depth, totalFrames: VoxelCube.size, gene: gA)
            }
            localCubeB.updateForView(axis: axis) { frame, depth in
                Self.processFrame(frame: frame, depth: depth, totalFrames: VoxelCube.size, gene: gB)
            }

            // Compute stats on background thread
            let sA = GIFStatsComputer.compute(cube: localCubeA)
            let sB = GIFStatsComputer.compute(cube: localCubeB)
            let diff = GIFStatsComputer.computeDiff(cubeA: localCubeA, cubeB: localCubeB)

            // Count how many pixels changed
            let totalPixels = VoxelCube.size * VoxelCube.size * VoxelCube.size
            let diffCount = diff.reduce(0, +)

            await MainActor.run {
                self.cubeA = localCubeA
                self.cubeB = localCubeB
                self.statsA = sA
                self.statsB = sB
                self.pixelDiff = diff
                self.cubeVersion += 1
                logger.info("DualCubeAnimator: NN done. avgBeauty A=\(sA.avgBeauty) B=\(sB.avgBeauty) totalDiff=\(diffCount)/\(totalPixels)")
            }
        }
    }

    /// Process one frame via the residual pipeline.
    nonisolated private static func processFrame(
        frame: [UInt8], depth: Int, totalFrames: Int, gene: GeneWeights
    ) -> [UInt8] {
        let s = VoxelCube.size
        guard frame.count == s * s else { return frame }

        let rgb: [(Float, Float, Float)] = frame.map { idx in
            let a = Float((Int(idx) % 64) / 16)
            let b = Float((Int(idx) % 16) / 4)
            let c = Float(Int(idx) % 4)
            return ((a + 0.5) / 4.0, (b + 0.5) / 4.0, (c + 0.5) / 4.0)
        }

        let depths = [Float](repeating: 0.5, count: s * s)
        let pyramids = BlockPyramid.computeAll(
            rgb: rgb, depths: depths,
            frameIndex: depth, totalFrames: totalFrames
        )

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
}
