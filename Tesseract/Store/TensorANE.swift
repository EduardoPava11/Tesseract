// TensorANE.swift
// Tesseract
//
// The capture tensor's ENCODE on the Apple Neural Engine: ONE dispatch
// for the whole 64³ capture (nn/tensor-codec/build_model.py, gated
// against the float64 reference before bundling).
//
// Placement laws: spec/neural/TensorEncoder.hs TA1–TA9. The two that
// carry the placement:
//
//   TA1  the 2×2×2 spacetime pool FACTORS into a temporal pair-average
//        and a spatial 2×2 average, and the two commute. So the whole
//        octave transform is conv + avg_pool — no 3D operator, which
//        is the thing the engine cannot schedule well.
//   TA3  the graph's only decision is a sign, and a flipped sign costs
//        exactly 2·min(|r|, g) of extra reconstruction error, NOT 2g.
//        A flip can only happen where |r| is under fp16's resolution,
//        so the engine's precision is bounded to nothing where it can
//        act at all. Measured on the authoring gate: 98.30% of 786432
//        signs agree, and the WORST disagreeing residual is 4.853e-4
//        against an fp16 ulp of 4.883e-4 at that magnitude — i.e.
//        every single disagreement is a residual the engine could not
//        see. This is the encoder's XP2.
//
// ★ NO-SILENT-SECOND-PATH DECREE (2026-08-14). This is a TWIN, in the
// same sense DyadANE is: one law, two engines, and
// TensorANEParityTests is the proof they agree. Returning nil is a
// DISPATCH decision, and the three reasons are kept apart because
// lumping them is how a defect becomes a permanent invisible cost:
//
//   PLATFORM   no bundled model on this device. A fact about the
//              hardware. The twin runs. Nothing is wrong.
//   SHAPE      the level is not the 64 × 64 × 64 × 3 the graph was
//              COMPILED for. A caller encoding a shorter capture is
//              legitimate, not a failure. The twin runs.
//   DEFECT     the level's data length disagrees with its own declared
//              shape. No caller can mean this. It traps in DEBUG so it
//              surfaces on the bench instead of quietly costing the
//              dispatch forever in the field.

import CoreML
import Foundation

enum TensorANE {

    static let frames = CaptureTensor.fineFrames
    static let side = CaptureTensor.fineSide
    static let channels = CaptureTensor.channels

    nonisolated(unsafe) private static let model: MLModel? = {
        guard let url = Bundle.main.url(forResource: "TensorEncode",
                                        withExtension: "mlmodelc")
        else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        return try? MLModel(contentsOf: url, configuration: config)
    }()

    static var isAvailable: Bool { model != nil }

    /// Encode the whole capture's colour in one dispatch. Returns the
    /// same Transform the CPU law returns, or nil per the three
    /// dispatch reasons above.
    static func transform(_ fine: CaptureTensor.Level)
        -> CaptureTensor.Transform? {

        // DEFECT: the level contradicts its own shape.
        assert(fine.data.count == fine.frames * fine.side * fine.side * 3,
               "ragged level: \(fine.data.count) floats for "
               + "\(fine.frames)×\(fine.side)² × 3")

        // PLATFORM: no engine on this device. The twin runs.
        guard let model else { return nil }

        // SHAPE: the graph is compiled for exactly 64 × 64² × 3.
        guard fine.frames == frames, fine.side == side else { return nil }

        // The graph reads NCHW with frames as the batch, so the
        // interleaved store transposes once on the way in.
        guard let input = try? MLMultiArray(
            shape: [NSNumber(value: frames), NSNumber(value: channels),
                    NSNumber(value: side), NSNumber(value: side)],
            dataType: .float32) else { return nil }
        let dst = input.dataPointer.bindMemory(
            to: Float32.self, capacity: frames * channels * side * side)
        let plane = side * side
        for t in 0..<frames {
            for p in 0..<plane {
                let src = (t * plane + p) * 3
                for c in 0..<channels {
                    dst[(t * channels + c) * plane + p] = fine.data[src + c]
                }
            }
        }

        // A prediction error on a graph compiled for THIS shape, fed
        // THIS shape, is a DEFECT — not a platform fact and not a
        // caller mistake. It says the wrapper and the graph disagree
        // about something, so it traps in DEBUG with the engine's own
        // words instead of costing the dispatch silently in the field.
        let result: MLFeatureProvider
        do {
            let provider = try MLDictionaryFeatureProvider(
                dictionary: ["cube": MLFeatureValue(multiArray: input)])
            result = try model.prediction(from: provider)
        } catch {
            assertionFailure("TensorEncode dispatch failed: \(error)")
            return nil
        }
        guard
            let l16 = result.featureValue(for: "l16")?.multiArrayValue,
            let s32 = result.featureValue(for: "sign32")?.multiArrayValue,
            let s64 = result.featureValue(for: "sign64")?.multiArrayValue,
            let a32 = result.featureValue(for: "g32")?.multiArrayValue,
            let a64 = result.featureValue(for: "g64")?.multiArrayValue
        else {
            assertionFailure("TensorEncode returned unexpected features: "
                             + "\(result.featureNames)")
            return nil
        }

        let g32 = level(a32, frames: 16, side: 16)
        let g64 = level(a64, frames: 16, side: 16)
        return CaptureTensor.Transform(
            l16: level(l16, frames: 16, side: 16),
            sign32: bits(s32, frames: 32, side: 32),
            sign64: bits(s64, frames: 64, side: 64),
            g32: g32, g64: g64,
            dev16: CaptureTensor.deviation(g32: g32, g64: g64))
    }

    /// NCHW → the interleaved store.
    private static func level(_ a: MLMultiArray, frames f: Int, side s: Int)
        -> CaptureTensor.Level {
        var out = CaptureTensor.Level(frames: f, side: s)
        let src = a.dataPointer.bindMemory(
            to: Float32.self, capacity: f * channels * s * s)
        let plane = s * s
        for t in 0..<f {
            for c in 0..<channels {
                let base = (t * channels + c) * plane
                for p in 0..<plane {
                    out.data[(t * plane + p) * 3 + c] = Float(src[base + p])
                }
            }
        }
        return out
    }

    /// The graph emits each sign as 0 or 1; the format stores a bit.
    /// Reading it here means the packer has ONE input shape whichever
    /// engine ran, which is what makes the twin a twin.
    private static func bits(_ a: MLMultiArray, frames f: Int, side s: Int)
        -> [Bool] {
        level(a, frames: f, side: s).data.map { $0 > 0.5 }
    }
}
