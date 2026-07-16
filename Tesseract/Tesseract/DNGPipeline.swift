// DNGPipeline.swift
// Tesseract
//
// Pure CPU core of the rear-camera DNG streaming pipeline (steps 2-6).
// Metal work (NN debayer + rung box-reduce) lives in MetalPipeline;
// session machinery lives in DNGCaptureManager. Everything here is pure
// logic — unit-tested in DNGPipelineTests.
//
// Per frame, AS IT ARRIVES (no 64-buffer pileup):
//   rung² RGB floats (display-domain [0,1], from GPU)
//     → tesseract palette quantization (256 = 4⁴; epoch = frame/16)
//     → 256-bin histogram + binomial deviation vs B(S², 1/256)
//     → store ONLY the S² UInt8 index frame
// After 64 frames:
//   → GIF89a at rung size (5 cs delay; upscale honors the 256² floor)
//   → Wasserstein barycentric λ-trajectory (16 strata, dict {0, 32, 63})
//
// MEMORY BUDGET (why S = 1024 is the practical ceiling):
//   index bytes per burst = S² × 64 frames × 1 B
//     S = 64   →     262,144 B ≈ 0.25 MB   (upscale ×4 → 256² GIF)
//     S = 256  →   4,194,304 B ≈ 4 MB      (native 256² GIF)
//     S = 1024 →  67,108,864 B ≈ 64 MiB    (practical ceiling)
//     S = 4096 → 1,073,741,824 B = 1 GiB   (archival-only: index frames
//                alone are 1 GiB, and per-pixel dither makes the stream
//                LZW-hostile — the GIF would be multiples of that)
//   Peak raw residency stays ≤ 2 Bayer CVPixelBuffers (~25.5 MB each)
//   regardless of rung: each buffer is consumed and dropped in-callback.

import Foundation
import simd

// MARK: - Rung ladder

/// Output resolution rung S ∈ {64, 256, 1024}.
enum DNGRung: Int, CaseIterable, Identifiable, Sendable {
    case r64 = 64
    case r256 = 256
    case r1024 = 1024

    var id: Int { rawValue }
    var side: Int { rawValue }
    var pixelCount: Int { side * side }

    /// Index bytes stored for a full 64-frame burst.
    var indexBytesPerBurst: Int { pixelCount * DNGConfig.burstFrames }

    /// GIF upscale factor: every export honors the 256² floor.
    /// S ≥ 256 already IS the output size (upscale 1).
    var gifUpscale: Int { max(1, 256 / side) }

    var label: String {
        switch self {
        case .r64:   return "64"
        case .r256:  return "256"
        case .r1024: return "1024"
        }
    }
}

enum DNGConfig {
    /// Active rung — user-visible picker in the DNG mode UI.
    /// Same nonisolated(unsafe) global pattern as CameraConfig.mode.
    nonisolated(unsafe) static var rung: DNGRung = .r256

    static let burstFrames = 64

    /// Frames per temporal epoch (4 epochs across the burst → d axis).
    static let framesPerEpoch = burstFrames / 4
}

// MARK: - Per-frame binomial readout

/// Live "colors in the binomial distribution" readout: the 256-bin palette
/// histogram of one frame vs the binomial null B(S², 1/256).
struct DNGBinomialStats: Sendable, Equatable {
    let frame: Int
    /// E[count per bin] = S² / 256 (also the exact observed mean).
    let expectedMean: Double
    /// Var[count per bin] under B(S², 1/256) = S² · (1/256) · (255/256).
    let expectedVariance: Double
    /// Observed variance of the 256 bin counts around the expected mean.
    let observedVariance: Double
    /// Deviation magnitude √(Σ (count − μ)²) — same form as Birkhoff order.
    let deviation: Double
    /// observedVariance / expectedVariance: ≈1 for binomial noise,
    /// large for structured color.
    var varianceRatio: Double {
        expectedVariance > 0 ? observedVariance / expectedVariance : 0
    }
}

// MARK: - Result types

struct DNGStats: Sendable {
    let rung: DNGRung
    let nativeSide: Int
    let burstDurationSec: Double
    let meanIntervalMs: Double
    let maxIntervalMs: Double
    let skippedSlots: Int
    let iso: Int
    let exposureSec: Double
    let cfaFourCC: OSType
    let sensorWidth: Int
    let sensorHeight: Int
    /// Per-frame Wasserstein barycentric coordinates against {0, 32, 63}.
    let lambdas: [SIMD3<Double>]
    /// Per-frame binomial readouts (one per stored frame).
    let binomial: [DNGBinomialStats]
}

struct DNGResult: Sendable, Equatable {
    let id: UUID
    let gifData: Data
    let measure: BirkhoffMeasure
    let stats: DNGStats

    static func == (lhs: DNGResult, rhs: DNGResult) -> Bool {
        lhs.id == rhs.id
    }
}

enum DNGError: Error, CustomStringConvertible, Sendable {
    case noFrames
    case encodeFailed

    var description: String {
        switch self {
        case .noFrames:     return "DNG pipeline: no frames"
        case .encodeFailed: return "DNG pipeline: GIF encode failed"
        }
    }
}

// MARK: - Pipeline

enum DNGPipeline {

    // MARK: Box-reduce math (mirrors boxReduceRGB in DebayerNet.metal)

    /// Integer floor boundaries of output cell `o` when reducing N → S.
    /// The boxes partition [0, N) exactly (unit-tested); box widths differ
    /// by at most 1 px when N/S is fractional (e.g. 3024/1024 = 2.95).
    static func boxBounds(_ o: Int, from n: Int, to s: Int) -> (lo: Int, hi: Int) {
        (lo: o * n / s, hi: (o + 1) * n / s)
    }

    // MARK: Palette quantization (step 3)

    /// Quantize one display-domain RGB value onto the CURRENT palette.
    ///
    /// // BELL-PALETTE SEAM: swap constructor here — this is the ONLY place
    /// // the DNG mode maps colors to palette indices. Today: the tesseract
    /// // 4⁴ lattice (level = nearest of {32, 96, 159, 223}, exactly
    /// // floor(v·4) bucketing; epoch d = frame / 16). The bell palette
    /// // constructor is spec-only so far (spec/quantization/BellPalette.hs).
    static func paletteIndex(r: Float, g: Float, b: Float, frame: Int) -> UInt8 {
        func level(_ v: Float) -> UInt8 {
            UInt8(min(3, max(0, Int(min(max(v, 0), 1) * 4))))
        }
        let d = UInt8(min(3, max(0, frame / DNGConfig.framesPerEpoch)))
        return TesseractCoord(d: d, a: level(r), b: level(g), c: level(b)).index
    }

    /// Quantize a rung-resolution frame (side² × RGB floats, display domain)
    /// to palette indices. `rgb` is interleaved [r, g, b, r, g, b, …].
    static func quantizeFrame(rgb: [Float], side: Int, frame: Int) -> [UInt8] {
        let n = side * side
        var out = [UInt8](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = paletteIndex(
                r: rgb[i * 3], g: rgb[i * 3 + 1], b: rgb[i * 3 + 2], frame: frame
            )
        }
        return out
    }

    // MARK: Histogram + binomial deviation (step 3)

    /// 256-bin palette histogram of one index frame. Sums to side² exactly.
    static func histogram(_ indices: [UInt8]) -> [Int] {
        var counts = [Int](repeating: 0, count: 256)
        for i in indices { counts[Int(i)] += 1 }
        return counts
    }

    /// Binomial deviation of one frame's histogram vs B(pixels, 1/256).
    static func binomialStats(counts: [Int], pixels: Int, frame: Int) -> DNGBinomialStats {
        let p = 1.0 / 256.0
        let mu = Double(pixels) * p
        let expectedVar = Double(pixels) * p * (1.0 - p)
        var sumSq = 0.0
        for c in counts {
            let d = Double(c) - mu
            sumSq += d * d
        }
        return DNGBinomialStats(
            frame: frame,
            expectedMean: mu,
            expectedVariance: expectedVar,
            observedVariance: sumSq / 256.0,
            deviation: sumSq.squareRoot()
        )
    }

    /// Steps 3+4 fused: quantize one rung frame, histogram it, score it.
    static func processFrame(rgb: [Float], side: Int, frame: Int)
        -> (indices: [UInt8], counts: [Int], binomial: DNGBinomialStats) {
        let indices = quantizeFrame(rgb: rgb, side: side, frame: frame)
        let counts = histogram(indices)
        let binomial = binomialStats(counts: counts, pixels: side * side, frame: frame)
        return (indices, counts, binomial)
    }

    // MARK: Finish (steps 5+6)

    /// After 64 frames: encode the GIF at rung size and compute the
    /// Wasserstein λ-trajectory. Pure CPU; runs off-main in the manager's
    /// detached task.
    static func finish(indexFrames: [[UInt8]],
                       histograms: [[Int]],
                       binomial: [DNGBinomialStats],
                       rung: DNGRung,
                       nativeSide: Int,
                       hwTimestampsNs: [Int64],
                       skippedSlots: Int,
                       iso: Int,
                       exposureSec: Double,
                       cfaFourCC: OSType,
                       sensorWidth: Int,
                       sensorHeight: Int,
                       progress: @Sendable (Float, String) -> Void) -> Result<DNGResult, DNGError> {
        guard !indexFrames.isEmpty, indexFrames.count == histograms.count else {
            return .failure(.noFrames)
        }

        // Step 6: Wasserstein barycentric trajectory (CPU, small — 16 bins).
        progress(0.05, "Wasserstein trajectory")
        let strata = histograms.map { WassersteinCoordinates.projectToStrata($0) }
        let lambdas = WassersteinCoordinates.trajectory(strataHistograms: strata)

        // Result-view measure: mid-frame histogram through Birkhoff M = O/C.
        let midCounts = histograms[min(32, histograms.count - 1)]
        let measure = BirkhoffMeasure(counts: midCounts)

        // Step 5: GIF89a at rung size, 5 cs delay. Rung ≥ 256 IS the output
        // size (upscale 1); S = 64 replicates ×4 to honor the 256² floor.
        progress(0.2, "encoding GIF \(rung.side * rung.gifUpscale)²×\(indexFrames.count)")
        guard let gifData = GIFEncoder.encode(
            indexFrames: indexFrames,
            side: rung.side,
            measure: measure,
            upscale: rung.gifUpscale
        ) else {
            return .failure(.encodeFailed)
        }
        progress(0.95, "done")

        let ts = hwTimestampsNs.map { Double($0) / 1e9 }
        let intervals = ts.count > 1 ? zip(ts.dropFirst(), ts).map { $0 - $1 } : []
        let stats = DNGStats(
            rung: rung,
            nativeSide: nativeSide,
            burstDurationSec: (ts.max() ?? 0) - (ts.min() ?? 0),
            meanIntervalMs: intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count) * 1000,
            maxIntervalMs: (intervals.max() ?? 0) * 1000,
            skippedSlots: skippedSlots,
            iso: iso,
            exposureSec: exposureSec,
            cfaFourCC: cfaFourCC,
            sensorWidth: sensorWidth,
            sensorHeight: sensorHeight,
            lambdas: lambdas,
            binomial: binomial
        )

        return .success(DNGResult(id: UUID(), gifData: gifData, measure: measure, stats: stats))
    }
}
