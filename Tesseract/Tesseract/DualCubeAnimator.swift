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

    /// Called on the main actor with each evaluated organism after an NN
    /// pass: (gene, beauty, descriptor, gifData, entropy). ContentView wires
    /// this to CameraManager.placeOrganism — feeds the MAP-Elites archive.
    var onOrganism: ((GeneWeights, Float, Descriptor, Data, EntropyFeedback) -> Void)?

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

            // Evaluate both organisms for the MAP-Elites archive
            let organismA = Self.evaluateOrganism(cube: localCubeA)
            let organismB = Self.evaluateOrganism(cube: localCubeB)

            await MainActor.run {
                self.cubeA = localCubeA
                self.cubeB = localCubeB
                self.statsA = sA
                self.statsB = sB
                self.pixelDiff = diff
                self.cubeVersion += 1
                if let o = organismA {
                    self.onOrganism?(gA, o.beauty, o.descriptor, o.gifData, o.entropy)
                }
                if let o = organismB {
                    self.onOrganism?(gB, o.beauty, o.descriptor, o.gifData, o.entropy)
                }
                logger.info("DualCubeAnimator: NN done. avgBeauty A=\(sA.avgBeauty) B=\(sB.avgBeauty) totalDiff=\(diffCount)/\(totalPixels)")
            }
        }
    }

    /// Score a cube as a MAP-Elites organism: overall Birkhoff beauty,
    /// entropy descriptor, and the export-grade GIF (256², fat voxels).
    nonisolated private static func evaluateOrganism(cube: VoxelCube)
        -> (beauty: Float, descriptor: Descriptor, gifData: Data, entropy: EntropyFeedback)? {
        let s = VoxelCube.size

        // Overall measure: per-frame-average palette counts (recomputeGIF pattern)
        var totalCounts = [Int](repeating: 0, count: 256)
        for idx in cube.voxels { totalCounts[Int(idx)] += 1 }
        let perFrame = totalCounts.map { $0 / s }
        let measure = BirkhoffMeasure(counts: perFrame)

        let entropy = EntropyMeasure.compute(paletteIndices: cube.voxels)
        let descriptor = Descriptor.from(entropy)

        let frames = (0..<s).map { cube.slice(axis: .z, depth: $0) }
        guard let data = GIFEncoder.encode(
            indexFrames: frames, side: s, measure: measure,
            upscale: CameraConfig.exportSide / s
        ) else { return nil }

        return (measure.beauty, descriptor, data, entropy)
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
