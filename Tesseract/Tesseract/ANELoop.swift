// ANELoop.swift
// Tesseract
//
// L3 of the ANE-loop plan (docs/ane-loop-design.md; spec
// spec/neural/ANELoop.hs AL1–AL8; prototype nn/ane-loop/). The
// fixed-K exchange loop: K sweeps × 64 Gauss–Seidel stages over
// 4096 independent 4×4×4 spacetime blocks, descending the phase
// objective F = D_16 + D_32 + D_64 (PP1's kernel) monotonically
// (AL4). One fused dispatch for the whole capture; the exact CPU
// twin below is the law — the engine must agree up to score
// near-ties (fp16, XP2 pattern; the objective value agrees to ~5
// digits, measured in the prototype gate).
//
// CONSUMER (ruling R3, additive + flag-gated): refineFarBlocks
// rearranges the far background's σ-half indices by descent on F.
// Only FULLY-FAR blocks (every voxel at coverage ≥ 31/32) are
// refined — face and band pixels are byte-untouched, so DY6's band
// laws hold verbatim. Inert blocks are frozen EXACTLY by y := q0:
// zero error makes every exchange cost +curvature·‖δ‖² > 0, so the
// graph rejects them without needing a mask input.
//
// Candidates per block: the 8 most-occupied distinct ground colors
// of the block's current assignment (8 = 2³, one per sub-cell of
// the block — combinatorial, not tuned), padded by repetition.
// Per-block centering on the target mean: ΔF is shift-invariant,
// and centering buys fp16 resolution (the DyadAssign lesson).

import CoreML
import Foundation
import Metal

enum ANELoop {

    static let blockSide = 4                       // 4×4×4 spacetime block
    static let blockVoxels = 64                    // = TL9 samplesPerJudgment
    static let candidateCount = 8                  // 2³ sub-cells per block
    static let sweeps = 4                          // prototype K; A-series pin owed
    /// AL7: reciprocal block volumes — the exchange's exact curvature.
    static let curvature = 1.0 + 1.0 / 8.0 + 1.0 / 64.0

    // Local raster order inside a block: v = x + 4·(y + 4·t).
    @inline(__always) static func localXYT(_ v: Int) -> (Int, Int, Int) {
        (v % blockSide, (v / blockSide) % blockSide, v / (blockSide * blockSide))
    }

    /// Membership of each voxel's 2-cell (8 voxel indices), fixed.
    static let cell2Members: [[Int]] = (0..<blockVoxels).map { v in
        let (x, y, t) = localXYT(v)
        return (0..<blockVoxels).filter { w in
            let (xw, yw, tw) = localXYT(w)
            return (x / 2, y / 2, t / 2) == (xw / 2, yw / 2, tw / 2)
        }
    }

    // MARK: - The exact CPU twin (the law; spec sweep verbatim)

    /// K Gauss–Seidel sweeps over one block. State is the chosen
    /// candidate INDEX per voxel; colors resolve through `cand`.
    /// Ties keep the current color (fixed points are stable, AL4).
    static func sweepBlockCPU(
        q0: [Int], y: [(Double, Double, Double)],
        cand: [(Double, Double, Double)], k: Int
    ) -> [Int] {
        var q = q0
        for _ in 0..<k {
            for v in 0..<blockVoxels {
                // e = chosen − target; the three mean terms of ΔF.
                func e(_ i: Int) -> (Double, Double, Double) {
                    let c = cand[q[i]]
                    return (c.0 - y[i].0, c.1 - y[i].1, c.2 - y[i].2)
                }
                let ev = e(v)
                var m2 = (0.0, 0.0, 0.0)
                for w in cell2Members[v] {
                    let ew = e(w); m2.0 += ew.0; m2.1 += ew.1; m2.2 += ew.2
                }
                m2 = (m2.0 / 8, m2.1 / 8, m2.2 / 8)
                var m4 = (0.0, 0.0, 0.0)
                for w in 0..<blockVoxels {
                    let ew = e(w); m4.0 += ew.0; m4.1 += ew.1; m4.2 += ew.2
                }
                m4 = (m4.0 / 64, m4.1 / 64, m4.2 / 64)
                let g = (ev.0 + m2.0 + m4.0, ev.1 + m2.1 + m4.1, ev.2 + m2.2 + m4.2)
                let qv = cand[q[v]]
                var best = 0.0                      // ΔF of staying put
                var bestIdx = q[v]
                for (ci, c) in cand.enumerated() {
                    let d = (c.0 - qv.0, c.1 - qv.1, c.2 - qv.2)
                    let df = 2 * (g.0 * d.0 + g.1 * d.1 + g.2 * d.2)
                           + curvature * (d.0 * d.0 + d.1 * d.1 + d.2 * d.2)
                    if df < best {                  // strict decrease only;
                        best = df; bestIdx = ci     // ties keep the earlier
                    }                               // (fixed points stable)
                }
                q[v] = bestIdx
            }
        }
        return q
    }

    // MARK: - The fused engine graph (one dispatch per capture)

    // Bundled as ANELoopModel.mlpackage (the "Model" suffix keeps
    // Xcode's generated class clear of this enum's name).
    nonisolated(unsafe) private static let model: MLModel? = loadModel("ANELoopModel")

    // The K=1 STREAMING unit (ANELoopK1Model.mlpackage): one sweep
    // per dispatch, for the B+E offset architecture — chained
    // dispatches with warm starts pick K_eff at runtime instead of
    // recompiling the graph. Bundled and benchmarked
    // (ANELoopBenchTests on the iPhone 17 Pro, the target hardware);
    // no runtime consumer until the device numbers pin the cadence.
    nonisolated(unsafe) private static let modelK1: MLModel? = loadModel("ANELoopK1Model")

    private static func loadModel(_ resource: String) -> MLModel? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mlmodelc")
        else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        return try? MLModel(contentsOf: url, configuration: config)
    }

    static var isAvailable: Bool { model != nil }
    static var isStreamingAvailable: Bool { modelK1 != nil }

    /// All 4096 blocks in one dispatch. Inputs are block-major
    /// [B, 64, 3] / [B, C, 3] Float32; returns the swept colors, or
    /// nil (callers fall back to the exact CPU twin).
    static func sweepANE(
        q0: [Float], y: [Float], cand: [Float], blockCount: Int
    ) -> [Float]? {
        guard let model,
              q0.count == blockCount * blockVoxels * 3,
              y.count == q0.count,
              cand.count == blockCount * candidateCount * 3 else { return nil }
        func array(_ values: [Float], _ shape: [NSNumber]) -> MLMultiArray? {
            guard let a = try? MLMultiArray(shape: shape, dataType: .float32)
            else { return nil }
            let p = a.dataPointer.bindMemory(to: Float.self, capacity: values.count)
            for i in 0..<values.count { p[i] = values[i] }
            return a
        }
        let b = NSNumber(value: blockCount)
        guard
            let qa = array(q0, [b, 64, 3]),
            let ya = array(y, [b, 64, 3]),
            let ca = array(cand, [b, NSNumber(value: candidateCount), 3]),
            let out = try? model.prediction(from: MLDictionaryFeatureProvider(
                dictionary: ["q0": qa, "y": ya, "cand": ca])),
            let name = out.featureNames.first,
            let result = out.featureValue(for: name)?.multiArrayValue
        else { return nil }
        let n = blockCount * blockVoxels * 3
        guard result.count == n else { return nil }
        let p = result.dataPointer.bindMemory(to: Float.self, capacity: n)
        return [Float](UnsafeBufferPointer(start: p, count: n))
    }

    // MARK: - The SIMT port (Metal; runtime K — AL9's running sums)

    // One GPU thread per block (AL2: no coupling ⇒ no sync). Unlike
    // the fused ANE graph, `sweeps` is a runtime argument — the
    // runtime-adaptive-K execution port for the B+E streaming
    // cadence. Kernel: Metal/ANELoop.metal (aneLoopSweepSIMT);
    // parity vs the CPU twin gated near-ties-only (XP2) by
    // ANELoopSIMTParityTests; timed by ANELoopBenchTests on the
    // iPhone 17 Pro.
    private static let simt:
        (queue: MTLCommandQueue, pipeline: MTLComputePipelineState)? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let fn = library.makeFunction(name: "aneLoopSweepSIMT"),
              let pipeline = try? device.makeComputePipelineState(function: fn)
        else { return nil }
        return (queue, pipeline)
    }()

    static var isSIMTAvailable: Bool { simt != nil }

    /// The exchange loop on the GPU: candidate INDICES in and out
    /// (no nearest-color recovery step), K picked at call time.
    /// Returns nil when Metal is unavailable (callers fall back).
    static func sweepSIMT(
        q0: [UInt8], y: [Float], cand: [Float],
        blockCount: Int, sweeps: Int
    ) -> [UInt8]? {
        guard let simt, sweeps >= 0,
              q0.count == blockCount * blockVoxels,
              y.count == blockCount * blockVoxels * 3,
              cand.count == blockCount * candidateCount * 3 else { return nil }
        let device = simt.pipeline.device
        guard
            let yBuf = y.withUnsafeBytes({ device.makeBuffer(
                bytes: $0.baseAddress!, length: $0.count) }),
            let cBuf = cand.withUnsafeBytes({ device.makeBuffer(
                bytes: $0.baseAddress!, length: $0.count) }),
            let qBuf = q0.withUnsafeBytes({ device.makeBuffer(
                bytes: $0.baseAddress!, length: $0.count) }),
            let commands = simt.queue.makeCommandBuffer(),
            let encoder = commands.makeComputeCommandEncoder()
        else { return nil }
        var k = UInt32(sweeps)
        var blocks = UInt32(blockCount)
        encoder.setComputePipelineState(simt.pipeline)
        encoder.setBuffer(yBuf, offset: 0, index: 0)
        encoder.setBuffer(cBuf, offset: 0, index: 1)
        encoder.setBuffer(qBuf, offset: 0, index: 2)
        encoder.setBytes(&k, length: MemoryLayout<UInt32>.size, index: 3)
        encoder.setBytes(&blocks, length: MemoryLayout<UInt32>.size, index: 4)
        let width = min(simt.pipeline.maxTotalThreadsPerThreadgroup, 64)
        encoder.dispatchThreads(
            MTLSize(width: blockCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed else { return nil }
        let p = qBuf.contents().bindMemory(to: UInt8.self, capacity: q0.count)
        return [UInt8](UnsafeBufferPointer(start: p, count: q0.count))
    }

    // MARK: - The flag-gated consumer (ruling R3)

    /// Rearrange the far background's indices by descent on F.
    /// - indexFrames: the post-dither DYAD cube (64 frames)
    /// - labs: the staged targets ŷ per frame
    /// - pulls: coverage t per pixel (far ⇔ t ≥ ceil)
    /// - tables: per-frame 768-byte LCTs (colors resolve here)
    /// Face and band pixels are byte-untouched; refined indices stay
    /// in the σ half. Deterministic; ANE with exact CPU fallback.
    static func refineFarBlocks(
        indexFrames: [[UInt8]],
        labs: [[OKLabColor]],
        pulls: [[Float]],
        tables: [Data],
        coverageCeil: Double,
        useANE: Bool = true
    ) -> [[UInt8]] {
        let frames = indexFrames.count
        guard frames > 0, frames % blockSide == 0 else { return indexFrames }
        let side = Int(Double(indexFrames[0].count).squareRoot())
        guard side % blockSide == 0,
              labs.count == frames, pulls.count == frames,
              tables.count == frames,
              tables.allSatisfy({ $0.count == 768 }) else { return indexFrames }

        let sb = side / blockSide, fb = frames / blockSide
        let blockCount = sb * sb * fb

        // Per-frame table labs (256 entries), resolved once.
        let tableLabs: [[OKLabColor]] = tables.map { t in
            (0..<256).map { i in
                let s = t.startIndex + 3 * i
                let rgb: (UInt8, UInt8, UInt8) = (t[s], t[s + 1], t[s + 2])
                return DyadPalette.oklab(fromSRGB8: rgb)
            }
        }

        // Gather blocks: fully-far blocks get real work; others are
        // frozen exactly (y := q0, candidates := {q0[0]} repeated).
        struct Block {
            var live = false
            var voxels: [(f: Int, p: Int)] = []      // cube addresses
            var candIdx: [Int] = []                  // σ indices (table)
            var q0: [Int] = []                       // candidate slot per voxel
        }
        var blocks = [Block](repeating: Block(), count: blockCount)
        var q0Flat = [Float](repeating: 0, count: blockCount * blockVoxels * 3)
        var yFlat = [Float](repeating: 0, count: blockCount * blockVoxels * 3)
        var candFlat = [Float](repeating: 0, count: blockCount * candidateCount * 3)

        for bi in 0..<blockCount {
            let bx = bi % sb, by = (bi / sb) % sb, bt = bi / (sb * sb)
            var blk = Block()
            var far = true
            var occupancy: [Int: Int] = [:]          // σ index → count
            for v in 0..<blockVoxels {
                let (lx, ly, lt) = localXYT(v)
                let f = bt * blockSide + lt
                let p = (by * blockSide + ly) * side + (bx * blockSide + lx)
                blk.voxels.append((f, p))
                let idx = Int(indexFrames[f][p])
                if Double(pulls[f][p]) < coverageCeil || idx < 128 { far = false }
                occupancy[idx, default: 0] += 1
            }
            blk.live = far
            if far {
                // Candidates: top-8 occupied σ indices (ties → lowest).
                var top = occupancy.sorted {
                    $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
                }.map(\.key)
                if top.count > candidateCount { top = Array(top.prefix(candidateCount)) }
                while top.count < candidateCount { top.append(top[top.count % max(1, occupancy.count)]) }
                blk.candIdx = top
                blk.q0 = blk.voxels.map { (f, p) in
                    top.firstIndex(of: Int(indexFrames[f][p])) ?? 0
                }
            }
            blocks[bi] = blk

            // Flat feeds, centered per block on the target mean.
            var center = (0.0, 0.0, 0.0)
            if blk.live {
                for (f, p) in blk.voxels {
                    let l = labs[f][p]
                    center.0 += l.l; center.1 += l.a; center.2 += l.b
                }
                center = (center.0 / 64, center.1 / 64, center.2 / 64)
            }
            for v in 0..<blockVoxels {
                let (f, p) = blk.voxels[v]
                let base = (bi * blockVoxels + v) * 3
                let shown = tableLabs[f][Int(indexFrames[f][p])]
                let q = blk.live
                    ? tableLabs[blk.voxels[v].f][blk.candIdx[blk.q0[v]]]
                    : shown
                q0Flat[base] = Float(q.l - (blk.live ? center.0 : 0))
                q0Flat[base + 1] = Float(q.a - (blk.live ? center.1 : 0))
                q0Flat[base + 2] = Float(q.b - (blk.live ? center.2 : 0))
                if blk.live {
                    let t = labs[f][p]
                    yFlat[base] = Float(t.l - center.0)
                    yFlat[base + 1] = Float(t.a - center.1)
                    yFlat[base + 2] = Float(t.b - center.2)
                } else {
                    // Frozen exactly: zero error rejects every exchange.
                    yFlat[base] = q0Flat[base]
                    yFlat[base + 1] = q0Flat[base + 1]
                    yFlat[base + 2] = q0Flat[base + 2]
                }
            }
            for c in 0..<candidateCount {
                let base = (bi * candidateCount + c) * 3
                if blk.live {
                    let col = tableLabs[blk.voxels[0].f][blk.candIdx[c]]
                    candFlat[base] = Float(col.l - center.0)
                    candFlat[base + 1] = Float(col.a - center.1)
                    candFlat[base + 2] = Float(col.b - center.2)
                } else {
                    candFlat[base] = q0Flat[bi * blockVoxels * 3]
                    candFlat[base + 1] = q0Flat[bi * blockVoxels * 3 + 1]
                    candFlat[base + 2] = q0Flat[bi * blockVoxels * 3 + 2]
                }
            }
        }

        // The loop: engine when whole-capture-shaped, else CPU twin.
        var chosen: [[Int]] = blocks.map(\.q0)
        var usedANE = false
        if useANE, blockCount == 4096,
           let swept = sweepANE(q0: q0Flat, y: yFlat, cand: candFlat,
                                blockCount: blockCount) {
            usedANE = true
            for bi in 0..<blockCount where blocks[bi].live {
                var out = [Int](repeating: 0, count: blockVoxels)
                for v in 0..<blockVoxels {
                    let base = (bi * blockVoxels + v) * 3
                    var bestC = 0
                    var bestD = Double.infinity
                    for c in 0..<candidateCount {
                        let cb = (bi * candidateCount + c) * 3
                        let d = pow(Double(swept[base]) - Double(candFlat[cb]), 2)
                              + pow(Double(swept[base + 1]) - Double(candFlat[cb + 1]), 2)
                              + pow(Double(swept[base + 2]) - Double(candFlat[cb + 2]), 2)
                        if d < bestD { bestD = d; bestC = c }
                    }
                    out[v] = bestC
                }
                chosen[bi] = out
            }
        }
        if !usedANE {
            for bi in 0..<blockCount where blocks[bi].live {
                let blk = blocks[bi]
                let y = blk.voxels.map { (f, p) -> (Double, Double, Double) in
                    let l = labs[f][p]; return (l.l, l.a, l.b)
                }
                let cand = blk.candIdx.map { i -> (Double, Double, Double) in
                    let c = tableLabs[blk.voxels[0].f][i]; return (c.l, c.a, c.b)
                }
                chosen[bi] = sweepBlockCPU(q0: blk.q0, y: y, cand: cand, k: sweeps)
            }
        }

        // Write back: refined far indices, everything else untouched.
        var out = indexFrames
        for bi in 0..<blockCount where blocks[bi].live {
            let blk = blocks[bi]
            for v in 0..<blockVoxels {
                let (f, p) = blk.voxels[v]
                out[f][p] = UInt8(blk.candIdx[chosen[bi][v]])
            }
        }
        return out
    }
}
