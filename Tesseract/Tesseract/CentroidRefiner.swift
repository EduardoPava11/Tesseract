// CentroidRefiner.swift
// Tesseract
//
// PASS 2 — face-weighted centroid refinement, CPU reference.
// Port of spec/quantization/CentroidRefine.hs (WL1-WL5); design in
// docs/REFINE-PASSES.md. The Metal reduction and the ANE fused graph
// must match THIS implementation (parity harness), and this
// implementation must match the spec's exact Rational trajectories.
//
// Pass 1 (the spine) fixed the index stream; this pass refines only the
// RECONSTRUCTION of each palette entry by K fixed proximal steps:
//
//   r⁰ = c (canonical center)
//   r^{k+1} = r^k + η·( a·(m − r^k) − b·(r^k − c) ),   b = μ·(1 − a)
//
// a = mean face mass of the entry's pixels (LIVE: TrueDepth depth,
// 1 = near; FACE: the ARKit anatomical signal in the same slot).
// Zero face mass ⇒ the entry provably never moves (WL3): the
// background keeps the canonical spine, the face earns diversity.
//
// K is FIXED — the ANE forbids data-dependent trip counts, and a fixed
// schedule is what makes the trace complete provenance (WL5).

import Foundation
import simd

// ════════════════════════════════════════════════════════════════
// § 1. THE KERNEL ABI — single Swift authority
// ════════════════════════════════════════════════════════════════

/// The accumulator contract shared with Refine.metal. The kernel
/// static_asserts the same numbers — a divergence fails the Metal
/// compile instead of silently corrupting sums.
enum RefineKernelABI {
    static let entries = 256
    /// uints per (frame, entry) slot: [wSum, w·r, w·g, w·b, count, 3×pad]
    static let slotStride = 8
    static let wSumSlot = 0
    static let wrSlot = 1
    static let wgSlot = 2
    static let wbSlot = 3
    static let countSlot = 4
    /// Fixed-point scale, 2¹⁶ — must equal kScale in Refine.metal.
    static let scale: Float = 65536
}

// ════════════════════════════════════════════════════════════════
// § 2. Q16 — fixed point AS A TYPE
// ════════════════════════════════════════════════════════════════

/// A quantity in 2¹⁶ fixed point. The bit-exact CPU/GPU parity rests
/// on every contribution being quantized identically and summed as
/// integers (integer addition commutes — order-independent). Making
/// the representation a type means "forgot the scale" or "mixed a raw
/// float with a quantized sum" is a compile error, not a convention.
struct Q16: Equatable {
    private(set) var raw: UInt64

    static let zero = Q16(raw: 0)

    init(raw: UInt64) { self.raw = raw }

    /// The ONLY Float→Q16 path: x·2¹⁶, round-to-nearest-even — the
    /// EXACT ops (and order) Refine.metal performs with MTL_FAST_MATH
    /// disabled. Callers pass the finished product (e.g. w·r) so the
    /// multiply order stays in their hands, mirrored by the kernel.
    init(quantizing x: Float) {
        raw = UInt64((x * RefineKernelABI.scale).rounded(.toNearestOrEven))
    }

    static func += (lhs: inout Q16, rhs: Q16) { lhs.raw += rhs.raw }

    /// Exact: raw/2¹⁶ is dyadic and raw < 2⁵³, so this Double is the
    /// true value — safe to divide downstream with a single rounding.
    var doubleValue: Double { Double(raw) / Double(RefineKernelABI.scale) }
}

// ════════════════════════════════════════════════════════════════
// § 3. SCHEDULE — invariants enforced at the boundary
// ════════════════════════════════════════════════════════════════

struct RefineSchedule {
    let eta: Float          // step size η
    let mu: Float           // pull strength μ
    let iterations: Int     // K — fixed, never data-dependent

    init(eta: Float = 0.5, mu: Float = 0.5, iterations: Int = 8) {
        precondition(eta > 0 && mu >= 0 && iterations >= 1,
                     "degenerate refine schedule")
        // WL2 monotonicity (and the in-cell inertness of the clamp)
        // require η·(a+b) ≤ 1 for all a ∈ [0,1]; max(a+b) = max(1, μ).
        precondition(eta * Swift.max(1, mu) <= 1,
                     "η·max(1,μ) must be ≤ 1 or WL2 monotonicity is lost")
        self.eta = eta
        self.mu = mu
        self.iterations = iterations
    }

    static let canonical = RefineSchedule()
}

// ════════════════════════════════════════════════════════════════
// § 4. RESULTS — provenance that carries its own parameters
// ════════════════════════════════════════════════════════════════

/// The refined table plus its complete push/pull provenance, INCLUDING
/// the schedule that produced it — a trace that doesn't know its own
/// K/η/μ is provenance with a hole in it.
struct RefinedPalette {
    /// 256 entries, each clamped to its lattice cell in BYTE space
    /// (cell k occupies bytes [k·64, k·64+63] — round() near the upper
    /// cell edge would otherwise cross into the next cell and break
    /// re-quantization idempotence).
    let table: [(UInt8, UInt8, UInt8)]

    /// Per-entry face mass a_i ∈ [0,1] (0 for empty entries).
    let faceMass: [Float]

    /// Per-entry, per-step displacement vectors. Empty array = the
    /// entry never moved (zero face mass or no pixels) — WL3 lets the
    /// trace compress background entries to nothing.
    let deltas: [[SIMD3<Float>]]

    /// The schedule this palette was refined under.
    let schedule: RefineSchedule

    /// 768-byte GIF Global Color Table of the refined entries.
    var gifColorTable: Data {
        var data = Data(capacity: 768)
        for (r, g, b) in table { data.append(r); data.append(g); data.append(b) }
        return data
    }

    /// Compact provenance for the GIF comment extension. Moved entries
    /// only (WL3 compression); full per-step deltas stay in memory.
    /// Derived from self — palette and trace cannot disagree.
    var traceComment: String {
        let moved = deltas.indices.filter { !deltas[$0].isEmpty }
        var lines = ["TRACE v1 K=\(schedule.iterations) eta=\(schedule.eta) mu=\(schedule.mu) moved=\(moved.count)/256"]
        for i in moved {
            let total = deltas[i].reduce(SIMD3<Float>.zero, +)
            lines.append(String(format: "e%03d a=%.2f d=(%+.4f,%+.4f,%+.4f)",
                                i, faceMass[i], total.x, total.y, total.z))
        }
        return lines.joined(separator: " | ")
    }

    /// The identity refinement: canonical table, nothing moved.
    static let canonical = RefinedPalette(
        table: TesseractPalette.table,
        faceMass: Array(repeating: 0, count: RefineKernelABI.entries),
        deltas: Array(repeating: [], count: RefineKernelABI.entries),
        schedule: .canonical
    )
}

/// Stage-A output in Q16 fixed point. Integer accumulation makes the
/// fold ORDER-INDEPENDENT: the Metal kernel (any thread scheduling) and
/// the CPU loop must agree bit-for-bit — the parity contract is
/// equality, not tolerance. Dyadic inputs (the spec's synthetic) pass
/// through exactly.
struct RefineAccumulation: Equatable {
    var wSumQ = [Q16](repeating: .zero, count: RefineKernelABI.entries)
    var wrQ = [Q16](repeating: .zero, count: RefineKernelABI.entries)
    var wgQ = [Q16](repeating: .zero, count: RefineKernelABI.entries)
    var wbQ = [Q16](repeating: .zero, count: RefineKernelABI.entries)
    var count = [UInt64](repeating: 0, count: RefineKernelABI.entries)
}

// ════════════════════════════════════════════════════════════════
// § 5. THE REFINER
// ════════════════════════════════════════════════════════════════

enum CentroidRefiner {

    /// Weight sanitation shared by both fold paths: NaN → 0, clamp [0,1].
    @inline(__always)
    static func sanitizedWeight(_ raw: Float) -> Float {
        raw.isFinite ? min(1, max(0, raw)) : 0
    }

    /// Stage A on the CPU: the weighted fold in fixed point.
    static func stageA(frames: [QuantizedFrame]) -> RefineAccumulation {
        var acc = RefineAccumulation()
        for frame in frames {
            guard let rgb = frame.rawRGB else { continue }
            let indices = frame.paletteIndices
            let depths = frame.depths
            for p in indices.indices {
                let i = Int(indices[p])
                let w = sanitizedWeight(depths[p])
                let (r, g, b) = rgb[p]
                acc.wSumQ[i] += Q16(quantizing: w)
                acc.wrQ[i] += Q16(quantizing: w * r)
                acc.wgQ[i] += Q16(quantizing: w * g)
                acc.wbQ[i] += Q16(quantizing: w * b)
                acc.count[i] += 1
            }
        }
        return acc
    }

    /// Refine the palette against recorded frames. Frames without
    /// rawRGB (preview frames) are skipped; if none carry it, the
    /// result is the canonical identity.
    static func refine(frames: [QuantizedFrame],
                       schedule: RefineSchedule = .canonical) -> RefinedPalette {
        stageB(stageA(frames: frames), schedule: schedule)
    }

    /// Cached GPU driver — pipeline state built once per process.
    /// Safety: RefineAccumulator is immutable after init and Metal
    /// queues/pipelines are documented thread-safe; every dispatch uses
    /// per-call buffers only.
    nonisolated(unsafe) private static let gpu = RefineAccumulator()

    /// Production entry point: GPU Stage A when Metal is available,
    /// CPU fold otherwise. The two are BIT-IDENTICAL (see
    /// MetalRefineParityTests), so path choice can never change output.
    static func refineAuto(frames: [QuantizedFrame],
                           schedule: RefineSchedule = .canonical) -> RefinedPalette {
        if let acc = gpu?.stageA(frames: frames) {
            return stageB(acc, schedule: schedule)
        }
        return refine(frames: frames, schedule: schedule)
    }

    /// Stage B: K push/pull steps per entry. Consumes Stage-A
    /// accumulation from EITHER path (CPU fold or Metal kernel).
    static func stageB(_ acc: RefineAccumulation,
                       schedule: RefineSchedule = .canonical) -> RefinedPalette {
        var table = [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0),
                                            count: RefineKernelABI.entries)
        var faceMass = [Float](repeating: 0, count: RefineKernelABI.entries)
        var allDeltas = [[SIMD3<Float>]](repeating: [],
                                         count: RefineKernelABI.entries)

        for i in 0..<RefineKernelABI.entries {
            let coord = TesseractCoord(index: UInt8(i))
            let c = coord.sRGB                                 // canonical center

            // Q16 → Double is exact (see Q16.doubleValue), so each of
            // these divisions rounds exactly once — deterministic on
            // both fold paths.
            let a: Float = acc.count[i] > 0
                ? Float(acc.wSumQ[i].doubleValue / Double(acc.count[i]))
                : 0
            faceMass[i] = a

            // WL3: zero face mass (or empty entry) ⇒ constant trace.
            guard a > 0, acc.wSumQ[i] != .zero else {
                table[i] = coord.sRGB8
                continue
            }

            let wSum = acc.wSumQ[i].doubleValue
            let m = SIMD3<Float>(                              // empirical mean
                Float(acc.wrQ[i].doubleValue / wSum),
                Float(acc.wgQ[i].doubleValue / wSum),
                Float(acc.wbQ[i].doubleValue / wSum))
            let b = schedule.mu * (1 - a)                      // pull gain
            var r = c
            var deltas: [SIMD3<Float>] = []
            deltas.reserveCapacity(schedule.iterations)

            for _ in 0..<schedule.iterations {
                let push: SIMD3<Float> = a * (m - r)
                let pull: SIMD3<Float> = b * (r - c)
                let step: SIMD3<Float> = schedule.eta * (push - pull)
                let next = clampToCell(r + step, coord: coord)
                deltas.append(next - r)
                r = next
            }

            table[i] = bytesInCell(r, coord: coord)
            allDeltas[i] = deltas
        }

        return RefinedPalette(table: table, faceMass: faceMass,
                              deltas: allDeltas, schedule: schedule)
    }

    // MARK: - Cell containment (WL1, in both spaces)

    /// Clamp a continuous color into its lattice cell [lvl/4, (lvl+1)/4).
    /// Inert under the canonical schedule when the mean is in-cell
    /// (WL1), but LOAD-BEARING in production: dithered pixels can pull
    /// the empirical mean outside the entry's own cell.
    private static func clampToCell(_ v: SIMD3<Float>, coord: TesseractCoord) -> SIMD3<Float> {
        func clamp1(_ x: Float, _ lvl: UInt8) -> Float {
            let lo = Float(lvl) / 4
            let hi = (Float(lvl + 1) / 4).nextDown   // half-open cell, exactly
            return min(max(x, lo), hi)
        }
        return SIMD3(clamp1(v.x, coord.a), clamp1(v.y, coord.b), clamp1(v.z, coord.c))
    }

    /// 8-bit quantization that cannot cross the byte-cell boundary:
    /// cell k owns bytes [k·64, k·64+63]. round(x·255) near the upper
    /// cell edge would land on (k+1)·64 and re-quantize to the wrong
    /// index — clamp in byte space closes that.
    private static func bytesInCell(_ v: SIMD3<Float>, coord: TesseractCoord) -> (UInt8, UInt8, UInt8) {
        func byte1(_ x: Float, _ lvl: UInt8) -> UInt8 {
            let raw = Int(round(x * 255))
            let lo = Int(lvl) * 64
            let hi = lo + 63
            return UInt8(min(max(raw, lo), hi))
        }
        return (byte1(v.x, coord.a), byte1(v.y, coord.b), byte1(v.z, coord.c))
    }
}
