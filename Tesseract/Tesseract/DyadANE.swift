// DyadANE.swift
// Tesseract
//
// The DYAD-256 pixel-assignment stage on the Apple Neural Engine:
// ONE dispatch for the whole 64³ capture (nn/dyad-assign/build_model.py,
// verified against the float64 reference before bundling).
//
// Placement law (spec/output/ExportMethods.hs XP1–XP2): tables and the
// role select are exact; the engine's fp16 can only flip near-tie
// argmins, which are lawful either way. Inputs are CENTERED OKLab
// coordinates — centering is argmin-invariant and buys ~10× fp16
// resolution (measured in the authoring script).
//
// ★ NO-SILENT-SECOND-PATH DECREE (2026-08-14). This is a TWIN:
// one law, two engines, and DyadANEParityTests is the proof they
// agree. Returning nil is therefore a DISPATCH decision, and the three
// reasons it can happen are kept apart on purpose, because lumping
// them together is how a defect becomes a permanent invisible cost:
//
//   PLATFORM   no bundled model on this device. A fact about the
//              hardware. The twin runs. Nothing is wrong.
//   SHAPE      the cube is not the 64 × 4096 the graph was COMPILED
//              for. The live solve reads at rung 16 (256 px/frame),
//              so this is a legitimate structural case, not a
//              failure. The twin runs.
//   DEFECT     the cube is RAGGED: frame counts or per-frame lengths
//              disagree with each other. No caller can mean this. It
//              traps in DEBUG so it surfaces on the bench instead of
//              quietly costing the ANE dispatch forever in the field.
//
// A prediction failure is a genuine runtime error and returns nil.

import CoreML
import Foundation

enum DyadANE {

    static let frameCount = 64
    static let pixelCount = 4096

    // Loaded once; MLModel prediction is used serially per capture.
    nonisolated(unsafe) private static let model: MLModel? = {
        guard let url = Bundle.main.url(forResource: "DyadAssign", withExtension: "mlmodelc")
        else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        return try? MLModel(contentsOf: url, configuration: config)
    }()

    static var isAvailable: Bool { model != nil }

    /// Assign every pixel of a 64-frame capture in one dispatch.
    /// - labs: per-frame OKLab pixels (4096 each), PRE-PULLED for the bleed
    /// - primaries: per-frame OKLab primaries (128 each, from the table)
    /// - masks: per-frame face flags (true = face)
    /// - fars: per-frame fully-pulled flags (forces exact index 255)
    /// Returns 64 index frames (face 0..127, background 128..255), or nil.
    static func assign(
        labs: [[OKLabColor]],
        primaries: [[OKLabColor]],
        masks: [[Bool]],
        fars: [[Bool]]
    ) -> [[UInt8]]? {
        // DEFECT: a ragged cube. Independent of which rung the caller
        // read at, the four arrays describe ONE cube, so their frame
        // counts must agree and every frame must be the same size. No
        // caller can legitimately mean otherwise, so this traps on the
        // bench rather than silently costing the dispatch in the field.
        let frames = labs.count
        assert(primaries.count == frames && masks.count == frames
               && fars.count == frames,
               "ragged cube: frame counts disagree (labs \(labs.count), "
               + "primaries \(primaries.count), masks \(masks.count), "
               + "fars \(fars.count))")
        assert(Set(labs.map { $0.count }).count <= 1
               && Set(masks.map { $0.count }).count <= 1
               && Set(fars.map { $0.count }).count <= 1
               && Set(primaries.map { $0.count }).count <= 1,
               "ragged cube: per-frame lengths disagree within an array")
        assert(labs.isEmpty
               || (labs[0].count == masks[0].count
                   && labs[0].count == fars[0].count),
               "ragged cube: labs, masks and fars disagree on pixel count")

        // PLATFORM: no engine on this device. The twin runs.
        guard let model else { return nil }

        // SHAPE: the graph is compiled for exactly 64 × 4096. The live
        // solve reads at rung 16, which is lawful and lands on the twin.
        guard labs.count == frameCount, primaries.count == frameCount,
              masks.count == frameCount, fars.count == frameCount,
              labs.allSatisfy({ $0.count == pixelCount }),
              masks.allSatisfy({ $0.count == pixelCount }),
              fars.allSatisfy({ $0.count == pixelCount }),
              primaries.allSatisfy({ $0.count == DyadPalette.primaryCount })
        else { return nil }

        guard
            let labArray = try? MLMultiArray(
                shape: [NSNumber(value: frameCount), NSNumber(value: pixelCount), 3],
                dataType: .float32),
            let primArray = try? MLMultiArray(
                shape: [NSNumber(value: frameCount), NSNumber(value: DyadPalette.primaryCount), 3],
                dataType: .float32),
            let maskArray = try? MLMultiArray(
                shape: [NSNumber(value: frameCount), NSNumber(value: pixelCount)],
                dataType: .float32),
            let farArray = try? MLMultiArray(
                shape: [NSNumber(value: frameCount), NSNumber(value: pixelCount)],
                dataType: .float32)
        else { return nil }

        let labPtr = labArray.dataPointer.bindMemory(
            to: Float32.self, capacity: frameCount * pixelCount * 3)
        let primPtr = primArray.dataPointer.bindMemory(
            to: Float32.self, capacity: frameCount * DyadPalette.primaryCount * 3)
        let maskPtr = maskArray.dataPointer.bindMemory(
            to: Float32.self, capacity: frameCount * pixelCount)
        let farPtr = farArray.dataPointer.bindMemory(
            to: Float32.self, capacity: frameCount * pixelCount)

        for f in 0..<frameCount {
            // Center on the frame's CENTROID = primaries[0]
            // (argmin-invariant; matches the CPU-side bleed pull).
            let c = primaries[f][0]
            let cl = c.l, ca = c.a, cb = c.b

            let primBase = f * DyadPalette.primaryCount * 3
            for (j, p) in primaries[f].enumerated() {
                primPtr[primBase + 3 * j]     = Float32(p.l - cl)
                primPtr[primBase + 3 * j + 1] = Float32(p.a - ca)
                primPtr[primBase + 3 * j + 2] = Float32(p.b - cb)
            }
            let labBase = f * pixelCount * 3
            let maskBase = f * pixelCount
            for (i, lab) in labs[f].enumerated() {
                labPtr[labBase + 3 * i]     = Float32(lab.l - cl)
                labPtr[labBase + 3 * i + 1] = Float32(lab.a - ca)
                labPtr[labBase + 3 * i + 2] = Float32(lab.b - cb)
                maskPtr[maskBase + i] = masks[f][i] ? 1 : 0
                farPtr[maskBase + i] = fars[f][i] ? 1 : 0
            }
        }

        guard
            let input = try? MLDictionaryFeatureProvider(dictionary: [
                "lab_c": MLFeatureValue(multiArray: labArray),
                "prim_c": MLFeatureValue(multiArray: primArray),
                "mask": MLFeatureValue(multiArray: maskArray),
                "far": MLFeatureValue(multiArray: farArray),
            ]),
            let result = try? model.prediction(from: input),
            let indices = result.featureValue(for: "indices")?.multiArrayValue,
            indices.count == frameCount * pixelCount
        else { return nil }

        let idxPtr = indices.dataPointer.bindMemory(
            to: Int32.self, capacity: frameCount * pixelCount)
        var out: [[UInt8]] = []
        out.reserveCapacity(frameCount)
        for f in 0..<frameCount {
            var frame = [UInt8](repeating: 0, count: pixelCount)
            for i in 0..<pixelCount {
                let v = idxPtr[f * pixelCount + i]
                // Lawfulness gate per role: face → primary; fully
                // pulled background → 255; bleed band → σ-half.
                let lawful: Bool
                if masks[f][i] {
                    lawful = (0..<Int32(DyadPalette.primaryCount)).contains(v)
                } else if fars[f][i] {
                    lawful = v == 255
                } else {
                    lawful = (128...255).contains(v)
                }
                guard lawful else { return nil }
                frame[i] = UInt8(v)
            }
            out.append(frame)
        }
        return out
    }
}
