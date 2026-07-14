// GIFStats.swift
// Tesseract
//
// Per-frame statistics for a GIF (64 frames from a VoxelCube).
// Beauty, entropy, color diversity, motion delta — all computed
// from palette indices via existing BirkhoffMeasure and EntropyMeasure.

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. PER-GIF STATS (64 values each)
// ════════════════════════════════════════════════════════════════

struct GIFFrameStats {
    let beauty: [Float]       // BirkhoffMeasure.beauty per frame
    let entropy: [Float]      // EntropyMeasure.joint per frame
    let colorsUsed: [Int]     // unique palette entries per frame
    let motionDelta: [Int]    // pixels changed vs previous frame

    /// Average beauty across all frames
    var avgBeauty: Float {
        guard !beauty.isEmpty else { return 0 }
        return beauty.reduce(0, +) / Float(beauty.count)
    }

    /// Average entropy across all frames
    var avgEntropy: Float {
        guard !entropy.isEmpty else { return 0 }
        return entropy.reduce(0, +) / Float(entropy.count)
    }

    /// Average colors used across all frames
    var avgColors: Int {
        guard !colorsUsed.isEmpty else { return 0 }
        return colorsUsed.reduce(0, +) / colorsUsed.count
    }

    static let empty = GIFFrameStats(beauty: [], entropy: [], colorsUsed: [], motionDelta: [])
}

// ════════════════════════════════════════════════════════════════
// § 2. COMPUTATION
// ════════════════════════════════════════════════════════════════

enum GIFStatsComputer {

    /// Compute per-frame stats from a VoxelCube's front projection (axis .z).
    static func compute(cube: VoxelCube) -> GIFFrameStats {
        let s = VoxelCube.size
        var beauty = [Float]()
        var entropy = [Float]()
        var colors = [Int]()
        var motion = [Int]()

        beauty.reserveCapacity(s)
        entropy.reserveCapacity(s)
        colors.reserveCapacity(s)
        motion.reserveCapacity(s)

        var prevFrame: [UInt8]? = nil

        for z in 0..<s {
            let frame = cube.slice(axis: .z, depth: z)

            // Beauty
            let bm = BirkhoffMeasure(paletteIndices: frame)
            beauty.append(bm.beauty)

            // Entropy
            let em = EntropyMeasure.compute(paletteIndices: frame)
            entropy.append(em.joint)

            // Color diversity
            let unique = Set(frame).count
            colors.append(unique)

            // Motion delta (pixels differing from previous frame)
            if let prev = prevFrame {
                var diff = 0
                for i in 0..<frame.count {
                    if frame[i] != prev[i] { diff += 1 }
                }
                motion.append(diff)
            } else {
                motion.append(0)
            }

            prevFrame = frame
        }

        return GIFFrameStats(
            beauty: beauty,
            entropy: entropy,
            colorsUsed: colors,
            motionDelta: motion
        )
    }

    /// Per-frame pixel diff between two cubes (how many pixels differ at each frame).
    static func computeDiff(cubeA: VoxelCube, cubeB: VoxelCube) -> [Int] {
        let s = VoxelCube.size
        var diffs = [Int]()
        diffs.reserveCapacity(s)

        for z in 0..<s {
            let frameA = cubeA.slice(axis: .z, depth: z)
            let frameB = cubeB.slice(axis: .z, depth: z)
            var diff = 0
            for i in 0..<min(frameA.count, frameB.count) {
                if frameA[i] != frameB[i] { diff += 1 }
            }
            diffs.append(diff)
        }

        return diffs
    }
}
