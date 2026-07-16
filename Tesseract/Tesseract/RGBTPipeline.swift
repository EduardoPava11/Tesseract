// RGBTPipeline.swift
// Tesseract
//
// Pure capture-then-compute orchestrator for the RGBT burst mode.
// Runs entirely inside the caller's detached task.
//
//   [FrameCellStats] (64 frames × 4096 cells × 4 channels)
//     → ISP: mean DN → black-sub → normalize → WB → exposure-norm → sRGB OETF
//     → PhotonTime: N-hat, T = tExp/N-hat, Heisenberg-floored sigma_T, IVW combine
//     → normalize T → tHat, build [CapturedFrame] (depths := tHat)
//     → PerfectQuantizer.quantizeGlobal (unchanged)
//     → GIFEncoder.encode(frames:, measure:, upscale: 4) → 256×256 GIF Data
//
// Bayer-late (TENET): all calibration is linear so it commutes with
// within-channel averaging; no demosaic anywhere. Everything stays linear
// until the sRGB OETF at the quantizer boundary.

import Foundation
import os.log

private let logger = Logger(subsystem: "com.tesseract.app", category: "RGBTPipeline")

enum RGBTError: Error, CustomStringConvertible {
    case noFrames
    case wrongMode(String)
    case encodeFailed

    var description: String {
        switch self {
        case .noFrames:           return "pipeline: no frames"
        case .wrongMode(let msg): return "pipeline: wrong cube mode — \(msg)"
        case .encodeFailed:       return "pipeline: GIF encode failed"
        }
    }
}

enum RGBTPipeline {

    /// TENET EXPOSURE_PCTL = 99.5 — global exposure normalization anchor.
    static let exposurePercentile = 99.5

    static func run(stats: [FrameCellStats],
                    skippedSlots: Int,
                    progress: @Sendable (Float, String) -> Void) -> Result<RGBTResult, RGBTError> {
        guard !stats.isEmpty else { return .failure(.noFrames) }
        // The view forces .training on appear; if the user backgrounded
        // mid-pipeline and flipped the GIF-mode level picker, fail loudly
        // rather than corrupting output (CameraConfig global coupling, v1).
        guard CameraConfig.outputSize == 64, CameraConfig.totalFrames == 64 else {
            return .failure(.wrongMode("outputSize \(CameraConfig.outputSize), totalFrames \(CameraConfig.totalFrames); need 64/64"))
        }

        let frameCount = stats.count
        let cellCount = BayerCellReducer.gridSide * BayerCellReducer.gridSide  // 4096
        let channels: [BayerChannel] = [.r, .gr, .gb, .b]

        // ── Steps 2 + 5: ISP + photon-time T per cell per frame ──
        // (progress 0.00–0.55, phase "photon statistics k/64")
        var linR = [Double](repeating: 0, count: frameCount * cellCount)
        var linG = [Double](repeating: 0, count: frameCount * cellCount)
        var linB = [Double](repeating: 0, count: frameCount * cellCount)
        var tAll = [Double](repeating: 0, count: frameCount * cellCount)
        var sigmaAll = [Double](repeating: 0, count: frameCount * cellCount)
        var floorHits = 0

        for (f, fs) in stats.enumerated() {
            progress(0.55 * Float(f) / Float(frameCount), "photon statistics \(f + 1)/\(frameCount)")
            let meta = fs.meta
            let count = fs.countPerChannel
            // Guard against absent EXIF: T must stay well-defined.
            let tExp = meta.exposureSec > 0 ? meta.exposureSec : 1.0 / 60.0

            // WB gains from AsShotNeutral, green-normalized. Applied to
            // display channels ONLY, after x_c feeds N-hat (T uses raw
            // signal statistics, not WB'd values).
            let nR = meta.wbNeutral[0], nG = meta.wbNeutral[1], nB = meta.wbNeutral[2]
            let gR = (nR > 0 && nR.isFinite && nG > 0 && nG.isFinite) ? nG / nR : 1.0
            let gB = (nB > 0 && nB.isFinite && nG > 0 && nG.isFinite) ? nG / nB : 1.0

            for cell in 0..<cellCount {
                var x = [Double](repeating: 0, count: 4)
                for c in 0..<4 {
                    let meanDN = Double(fs.sum[cell * 4 + c]) / Double(count)
                    let denom = max(meta.whiteLevel - meta.blackLevel[c], 1e-6)
                    // CLAMP, not max: metadata can report white levels below
                    // the actual bit depth (ROTAS device bug, LL hit 16.004).
                    x[c] = min(max((meanDN - meta.blackLevel[c]) / denom, 0), 1)
                }

                let base = f * cellCount + cell
                // Display channels: box-average already happened in the
                // reducer (linear DN); (Gr+Gb)/2 is the quad average.
                linR[base] = x[0] * gR
                linG[base] = (x[1] + x[2]) / 2.0
                linB[base] = x[3] * gB

                // Photon-statistics T: 4 channels at their own wavelength
                // anchors, IVW-combined.
                var ests = [Uncertain]()
                ests.reserveCapacity(4)
                var hitFloor = false
                for c in 0..<4 {
                    let (n, sigmaN) = PhotonTime.nHat(
                        x: x[c], s: meta.noise[c].s, o: meta.noise[c].o, count: count
                    )
                    let channel = channels[c]
                    let est = PhotonTime.estimateT(
                        channel: channel, tExp: tExp, nHat: n, sigmaN: sigmaN
                    )
                    // Floor detection: the estimate was clamped up to the
                    // Heisenberg floor iff its sigma equals the floor.
                    if est.sigma == PhotonPhysics.heisenbergFloorSec(channel, n: max(1, n)) {
                        hitFloor = true
                    }
                    ests.append(est)
                }
                let t = PhotonTime.weightedMean(ests, fallback: tExp)
                tAll[base] = t.value
                sigmaAll[base] = t.sigma
                if hitFloor { floorHits += 1 }
            }
        }

        // ── Step 3: global exposure normalization ──
        // E = p99.5 of all G values across all frames, so frames stay comparable.
        progress(0.55, "normalizing exposure")
        let e = max(percentile(linG, exposurePercentile), 1e-6)
        for i in 0..<linR.count {
            linR[i] = min(max(linR[i] / e, 0), 1)
            linG[i] = min(max(linG[i] / e, 0), 1)
            linB[i] = min(max(linB[i] / e, 0), 1)
        }

        // ── Step 6: normalize T to [0,1] ──
        progress(0.55, "normalizing T")
        let (tHat, tP1, tP99) = normalizeT(tAll)

        let finiteSigmas = sigmaAll.filter { $0.isFinite }
        let meanSigmaT = finiteSigmas.isEmpty ? 0 : finiteSigmas.reduce(0, +) / Double(finiteSigmas.count)
        let floorFraction = Double(floorHits) / Double(frameCount * cellCount)

        // ── Step 7: build [CapturedFrame] ──
        // sRGB OETF at the quantizer boundary — "keep linear until
        // quantization" ends here, because the fixed tesseract GCT entries
        // {32, 96, 159, 223} are display-domain bytes and the front-camera
        // path feeds display-domain values to PerfectQuantizer.
        // FLAG (spec decision): quantizing linear instead is a one-line
        // removal but will render dark.
        var capturedFrames = [CapturedFrame]()
        capturedFrames.reserveCapacity(frameCount)
        for f in 0..<frameCount {
            var rgb = [(Float, Float, Float)]()
            rgb.reserveCapacity(cellCount)
            var depths = [Float](repeating: 0, count: cellCount)
            for cell in 0..<cellCount {
                let base = f * cellCount + cell
                rgb.append((
                    Float(srgbOETF(linR[base])),
                    Float(srgbOETF(linG[base])),
                    Float(srgbOETF(linB[base]))
                ))
                depths[cell] = Float(tHat[base])
            }
            capturedFrames.append(CapturedFrame(
                index: f,
                rgb: rgb,
                depths: depths,
                blockEvals: nil,
                timestamp: Double(stats[f].hwTimestampNs) / 1e9
            ))
        }

        // ── Step 8: quantize (UNCHANGED PerfectQuantizer) ──
        // T flows through both depth entry points automatically: F-S
        // diffusion strength per pixel, and Phase 3 group epoch cadence.
        progress(0.55, "quantizing \(frameCount) frames")
        let quantized = PerfectQuantizer.quantizeGlobal(frames: capturedFrames)
        progress(0.85, "encoding GIF")

        // ── Step 9: encode 64³ cube at 20 fps with 4×4 fat voxels ──
        let midMeasure = quantized[min(31, quantized.count - 1)].measure
        guard let gifData = GIFEncoder.encode(frames: quantized, measure: midMeasure, upscale: 4) else {
            return .failure(.encodeFailed)
        }
        progress(1.0, "done")

        // ── Stats ──
        let ts = stats.map { Double($0.hwTimestampNs) / 1e9 }
        let intervals = ts.count > 1 ? zip(ts.dropFirst(), ts).map { $0 - $1 } : []
        let burstDuration = (ts.max() ?? 0) - (ts.min() ?? 0)
        let meanInterval = intervals.isEmpty ? 0 : intervals.reduce(0, +) / Double(intervals.count)
        let maxInterval = intervals.max() ?? 0
        let meta0 = stats[0].meta

        let rgbtStats = RGBTStats(
            burstDurationSec: burstDuration,
            meanIntervalMs: meanInterval * 1000,
            maxIntervalMs: maxInterval * 1000,
            skippedSlots: skippedSlots,
            iso: meta0.iso,
            exposureSec: meta0.exposureSec,
            tP1: tP1,
            tP99: tP99,
            meanSigmaT: meanSigmaT,
            floorFraction: floorFraction,
            cfaFourCC: meta0.cfa,
            sensorWidth: meta0.width,
            sensorHeight: meta0.height
        )
        logger.info("RGBT pipeline: T p1 \(tP1, format: .exponential) s, p99 \(tP99, format: .exponential) s, mean σT \(meanSigmaT, format: .exponential) s, floor \(floorFraction * 100, format: .fixed(precision: 1))%")

        return .success(RGBTResult(
            id: UUID(),
            gifData: gifData,
            measure: midMeasure,
            stats: rgbtStats
        ))
    }

    // MARK: - T normalization

    /// Robust percentile normalization (a near-zero-photon cell yields an
    /// enormous T), then INVERTED:
    ///   tHat = 1 - clamp((T - p1) / (p99 - p1), 0, 1)
    ///
    /// ORIENTATION FLAG: bright cells (many photons, small T, small sigma_T)
    /// map to tHat ~ 1, inheriting depth's "1 = near = sharp epochs + 30%
    /// diffusion" convention (BinomialCadence.sigmaForDepth and the F-S
    /// strength in PerfectQuantizer, both unchanged). Flipping the axis is a
    /// one-character change (drop the `1 -`); confident-equals-sharp ships.
    static func normalizeT(_ t: [Double]) -> (tHat: [Double], p1: Double, p99: Double) {
        guard !t.isEmpty else { return ([], 0, 0) }
        let p1 = percentile(t, 1)
        let p99 = percentile(t, 99)
        let range = max(p99 - p1, 1e-12)
        let tHat = t.map { 1.0 - min(max(($0 - p1) / range, 0), 1) }
        return (tHat, p1, p99)
    }

    /// Percentile by full sort (262,144 doubles ≈ 30 ms; fine off-main).
    static func percentile(_ xs: [Double], _ q: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let sorted = xs.sorted()
        let idx = Int((Double(sorted.count - 1) * q / 100.0).rounded())
        return sorted[min(max(idx, 0), sorted.count - 1)]
    }

    // MARK: - sRGB OETF

    /// Piecewise IEC 61966-2-1, applied ONCE (sixteen3 rule; exact curve,
    /// not pow(1/2.2)).
    static func srgbOETF(_ x: Double) -> Double {
        let v = min(max(x, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }
}
