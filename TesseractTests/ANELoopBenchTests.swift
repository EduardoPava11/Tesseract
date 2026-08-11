// ANELoopBenchTests.swift
// Tesseract
//
// THE A-SERIES MICROBENCHMARK — the L2 exit criterion
// (docs/ane-loop-design.md §5, "A-series timing owed on device").
// Target hardware: iPhone 17 Pro (A19 Pro — 16-core ANE plus the
// GPU-core neural accelerators, which make the compute-unit choice
// an empirical question, not a default).
//
// Measures, on the physical device, for BOTH bundled graphs
// (ANELoopModel = K=4 export unit, ANELoopK1Model = K=1 streaming
// unit for the B+E offset architecture):
//
//   · steady-state latency per dispatch, per compute-unit config
//     (.all / .cpuAndNeuralEngine / .cpuAndGPU / .cpuOnly)
//   · per-fused-stage cost and the dispatch floor, by the two-point
//     fit: stages are 256 vs 64, so
//         perStage = (t_K4 − t_K1) / 192,   floor = t_K1 − 64·perStage
//   · the budget verdicts: K=4 vs the 200 ms rung-16 tick (5 Hz)
//     and K=1 vs the 50 ms polyphase tick (20 Hz).
//
// Run on device: ⌘U (or xcodebuild test -destination the phone),
// filter ANELoopBench; read the "ANE-LOOP BENCH" lines. Simulator
// and Mac runs are skipped — CoreML off-device says nothing about
// the A19 engine, and unmeasured numbers must not look measured.
// MEASUREMENT ONLY: no GIF byte depends on this; K stays pinned in
// ANELoop.sweeps until Daniel reads the device numbers.

import CoreML
import XCTest
@testable import Tesseract

final class ANELoopBenchTests: XCTestCase {

    private struct Feed {
        let q0: MLMultiArray
        let y: MLMultiArray
        let cand: MLMultiArray
        // The same capture for the SIMT port: indices + raw floats.
        let q0Idx: [UInt8]
        let yRaw: [Float]
        let candRaw: [Float]
    }

    private static let blocks = 4096
    private static let stages = [1: 64, 4: 256]     // sweeps → fused stages

    /// Deterministic synthetic capture (the spec's LCG — no
    /// randomness in gates), shaped like the real feed: centered
    /// labs with block-scale structure so exchanges actually fire.
    private func makeFeed() throws -> Feed {
        var s = 11
        func next() -> Float {
            s = (1103515245 &* s &+ 12345) % 2147483648
            return Float(s) / 2147483648.0 - 0.5
        }
        let b = Self.blocks
        let q0 = try MLMultiArray(shape: [NSNumber(value: b), 64, 3], dataType: .float32)
        let y = try MLMultiArray(shape: [NSNumber(value: b), 64, 3], dataType: .float32)
        let cand = try MLMultiArray(shape: [NSNumber(value: b), 8, 3], dataType: .float32)
        let qp = q0.dataPointer.bindMemory(to: Float.self, capacity: b * 64 * 3)
        let yp = y.dataPointer.bindMemory(to: Float.self, capacity: b * 64 * 3)
        let cp = cand.dataPointer.bindMemory(to: Float.self, capacity: b * 8 * 3)
        var q0Idx = [UInt8](repeating: 0, count: b * 64)
        for i in 0..<(b * 8 * 3) { cp[i] = 0.2 * next() }
        for bi in 0..<b {
            let coarse = (0.1 * next(), 0.1 * next(), 0.1 * next())
            for v in 0..<64 {
                let base = (bi * 64 + v) * 3
                yp[base] = 0.16 * next() + coarse.0
                yp[base + 1] = 0.16 * next() + coarse.1
                yp[base + 2] = 0.16 * next() + coarse.2
                let c = Int(abs(next()) * 8) % 8
                q0Idx[bi * 64 + v] = UInt8(c)
                let cb = (bi * 8 + c) * 3
                qp[base] = cp[cb]; qp[base + 1] = cp[cb + 1]; qp[base + 2] = cp[cb + 2]
            }
        }
        let yRaw = [Float](UnsafeBufferPointer(start: yp, count: b * 64 * 3))
        let candRaw = [Float](UnsafeBufferPointer(start: cp, count: b * 8 * 3))
        return Feed(q0: q0, y: y, cand: cand,
                    q0Idx: q0Idx, yRaw: yRaw, candRaw: candRaw)
    }

    private func load(_ resource: String, _ units: MLComputeUnits) -> MLModel? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mlmodelc")
        else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = units
        return try? MLModel(contentsOf: url, configuration: config)
    }

    /// Median steady latency in ms (2 warmup + 5 timed dispatches),
    /// plus the cold first-predict.
    private func time(_ model: MLModel, _ feed: Feed) throws -> (first: Double, steady: Double) {
        let provider = try MLDictionaryFeatureProvider(
            dictionary: ["q0": feed.q0, "y": feed.y, "cand": feed.cand])
        var t0 = Date()
        _ = try model.prediction(from: provider)
        let first = -t0.timeIntervalSinceNow * 1000
        _ = try model.prediction(from: provider)
        var samples: [Double] = []
        for _ in 0..<5 {
            t0 = Date()
            _ = try model.prediction(from: provider)
            samples.append(-t0.timeIntervalSinceNow * 1000)
        }
        return (first, samples.sorted()[samples.count / 2])
    }

    func testDeviceBench() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("ANE bench is device-only: simulator CoreML says nothing about the A19 engine.")
        #else
        let feed = try makeFeed()
        let configs: [(String, MLComputeUnits)] = [
            ("all", .all),
            ("cpu+ane", .cpuAndNeuralEngine),
            ("cpu+gpu", .cpuAndGPU),
            ("cpu", .cpuOnly),
        ]
        var steady: [String: [Int: Double]] = [:]   // config → sweeps → ms

        for (name, units) in configs {
            for (sweeps, resource) in [(4, "ANELoopModel"), (1, "ANELoopK1Model")] {
                guard let model = load(resource, units) else {
                    print("ANE-LOOP BENCH \(name) K\(sweeps): model unavailable")
                    continue
                }
                let t = try time(model, feed)
                steady[name, default: [:]][sweeps] = t.steady
                print(String(
                    format: "ANE-LOOP BENCH %@ K%d: first %.1f ms, steady %.2f ms/dispatch",
                    name, sweeps, t.first, t.steady))
            }
            if let t1 = steady[name]?[1], let t4 = steady[name]?[4] {
                let perStage = (t4 - t1) / 192
                let floor = t1 - 64 * perStage
                print(String(
                    format: "ANE-LOOP BENCH %@ fit: %.3f ms/stage, dispatch floor %.2f ms",
                    name, perStage, floor))
            }
        }

        // The SIMT port: the hand-written Metal kernel, timed on the
        // same feed. Runtime K means one pipeline serves every sweep
        // count — the row the CoreML `.cpuAndGPU` scheduler can't
        // show (its graph is still the fused fixed-K one).
        if ANELoop.isSIMTAvailable {
            for sweeps in [1, 4] {
                _ = ANELoop.sweepSIMT(q0: feed.q0Idx, y: feed.yRaw,
                                      cand: feed.candRaw,
                                      blockCount: Self.blocks, sweeps: sweeps)
                var samples: [Double] = []
                for _ in 0..<5 {
                    let t0 = Date()
                    _ = ANELoop.sweepSIMT(q0: feed.q0Idx, y: feed.yRaw,
                                          cand: feed.candRaw,
                                          blockCount: Self.blocks, sweeps: sweeps)
                    samples.append(-t0.timeIntervalSinceNow * 1000)
                }
                let med = samples.sorted()[samples.count / 2]
                steady["metal-simt", default: [:]][sweeps] = med
                print(String(
                    format: "ANE-LOOP BENCH metal-simt K%d: steady %.2f ms/dispatch",
                    sweeps, med))
            }
            if let t1 = steady["metal-simt"]?[1], let t4 = steady["metal-simt"]?[4] {
                let perStage = (t4 - t1) / 192
                print(String(
                    format: "ANE-LOOP BENCH metal-simt fit: %.3f ms/stage, dispatch floor %.2f ms",
                    perStage, t1 - 64 * perStage))
            }
        } else {
            print("ANE-LOOP BENCH metal-simt: Metal unavailable")
        }

        // Budget verdicts on the best config (the numbers that pin K).
        let best = steady.min { a, b in
            (a.value[4] ?? .infinity) < (b.value[4] ?? .infinity)
        }
        if let (name, times) = best, let t4 = times[4] {
            let t1 = times[1] ?? .infinity
            print(String(
                format: "ANE-LOOP BENCH verdict [%@]: 5 Hz tick fits %d K4 dispatches; "
                    + "20 Hz tick fits %d K1 dispatches (K_eff for B+E)",
                name, Int(200 / t4), t1.isFinite ? Int(50 / t1) : 0))
            XCTAssertGreaterThan(Int(200 / t4), 0,
                "A K=4 dispatch exceeds the whole 5 Hz budget — the export loop cannot run on this device.")
        } else {
            XCTFail("No compute-unit config produced a measurement — are both mlpackages bundled?")
        }
        #endif
    }
}
