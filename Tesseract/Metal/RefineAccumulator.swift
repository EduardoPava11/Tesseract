// RefineAccumulator.swift
// Tesseract
//
// Metal driver for Stage A of pass-2 refinement (Refine.metal).
// Produces a RefineAccumulation BIT-IDENTICAL to
// CentroidRefiner.stageA — the parity test asserts ==, not ≈.
// Stage B (the K push/pull steps) is shared: both paths feed
// CentroidRefiner.stageB.
//
// Layout, stride, and scale come from RefineKernelABI (the single
// Swift authority); Refine.metal static_asserts the same numbers.
//
// This is deliberately NOT part of MetalPipeline: it runs once per
// capture after recording, not per frame, and owns no persistent
// textures — a small, self-contained dispatch.

import Foundation
import Metal

final class RefineAccumulator {

    /// A frame that is PROVEN to carry raw RGB — the optional is
    /// discharged once, at extraction, instead of force-unwrapped later.
    private struct FrameSlice {
        let indices: [UInt8]
        let rgb: [(Float, Float, Float)]
        let depths: [Float]
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let state: MTLComputePipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let fn = library.makeFunction(name: "refineAccumulate"),
              let state = try? device.makeComputePipelineState(function: fn)
        else { return nil }
        self.device = device
        self.queue = queue
        self.state = state
    }

    /// Run the fold on the GPU. Frames without rawRGB are skipped
    /// (same contract as the CPU reference). Returns nil on any Metal
    /// failure — callers fall back to CentroidRefiner.stageA, which is
    /// bit-identical, so the fallback is invisible.
    func stageA(frames: [QuantizedFrame]) -> RefineAccumulation? {
        let usable: [FrameSlice] = frames.compactMap { frame in
            guard let rgb = frame.rawRGB else { return nil }
            return FrameSlice(indices: frame.paletteIndices,
                              rgb: rgb, depths: frame.depths)
        }
        guard !usable.isEmpty else { return RefineAccumulation() }

        let frameCount = usable.count
        let pixels = usable[0].indices.count
        guard usable.allSatisfy({ $0.indices.count == pixels
                               && $0.rgb.count == pixels
                               && $0.depths.count == pixels }) else { return nil }

        // Flatten inputs.
        var indices = [UInt8](); indices.reserveCapacity(frameCount * pixels)
        var rgb = [Float](); rgb.reserveCapacity(frameCount * pixels * 3)
        var weights = [Float](); weights.reserveCapacity(frameCount * pixels)
        for slice in usable {
            indices.append(contentsOf: slice.indices)
            for (r, g, b) in slice.rgb { rgb.append(r); rgb.append(g); rgb.append(b) }
            weights.append(contentsOf: slice.depths)
        }

        let slotCount = frameCount * RefineKernelABI.entries * RefineKernelABI.slotStride
        guard
            let indexBuf = device.makeBuffer(bytes: indices, length: indices.count),
            let rgbBuf = device.makeBuffer(bytes: rgb, length: rgb.count * 4),
            let weightBuf = device.makeBuffer(bytes: weights, length: weights.count * 4),
            let accumBuf = device.makeBuffer(length: slotCount * 4,
                                             options: .storageModeShared)
        else { return nil }
        memset(accumBuf.contents(), 0, slotCount * 4)

        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else { return nil }
        var ppf = UInt32(pixels)
        enc.setComputePipelineState(state)
        enc.setBuffer(indexBuf, offset: 0, index: 0)
        enc.setBuffer(rgbBuf, offset: 0, index: 1)
        enc.setBuffer(weightBuf, offset: 0, index: 2)
        enc.setBuffer(accumBuf, offset: 0, index: 3)
        enc.setBytes(&ppf, length: 4, index: 4)

        let wpt = min(state.maxTotalThreadsPerThreadgroup, 256)
        enc.dispatchThreads(
            MTLSize(width: pixels, height: frameCount, depth: 1),
            threadsPerThreadgroup: MTLSize(width: wpt, height: 1, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { return nil }

        // Combine per-frame uint32 partials in UInt64/Q16 — fixed
        // order, deterministic, overflow-free (per-frame sums < 2²⁸).
        var acc = RefineAccumulation()
        let slots = accumBuf.contents().bindMemory(to: UInt32.self, capacity: slotCount)
        for f in 0..<frameCount {
            for e in 0..<RefineKernelABI.entries {
                let s = (f * RefineKernelABI.entries + e) * RefineKernelABI.slotStride
                acc.wSumQ[e] += Q16(raw: UInt64(slots[s + RefineKernelABI.wSumSlot]))
                acc.wrQ[e] += Q16(raw: UInt64(slots[s + RefineKernelABI.wrSlot]))
                acc.wgQ[e] += Q16(raw: UInt64(slots[s + RefineKernelABI.wgSlot]))
                acc.wbQ[e] += Q16(raw: UInt64(slots[s + RefineKernelABI.wbSlot]))
                acc.count[e] += UInt64(slots[s + RefineKernelABI.countSlot])
            }
        }
        return acc
    }
}
