// GoEvaluator.swift
// Tesseract
//
// Real KataGo on iPhone via CoreML.
// Model: KataGoModel19x19fp16m1w8LiCh (b18c384nbt, 22.5 MB)
// Pre-converted by ChinChangYang from PyTorch to CoreML.
//
// Input:  22 spatial channels × 19×19 (board state + features)
// Output: 19×19 ownership map [-1,1] (territory estimation)
//
// Pre-filtered: only blocks with Go complexity > 0.2 get NN eval.
// Others use simple territory counting from GoBoard.swift.

import CoreML
import os.log

private let logger = Logger(subsystem: "com.tesseract.app", category: "GoEvaluator")

/// Real KataGo evaluation via CoreML on the Neural Engine.
/// Thread-safe: MLModel.prediction is safe to call from any thread.
final class GoEvaluator: @unchecked Sendable {

    private var model: MLModel?
    private(set) var isReady = false

    init() {
        loadModel()
    }

    // MARK: - Model Loading

    private func loadModel() {
        let config = MLModelConfiguration()
        config.computeUnits = .all  // CPU + GPU + Neural Engine

        // Try compiled model first (faster), then mlpackage
        if let url = Bundle.main.url(forResource: "KataGoModel19x19fp16m1w8LiCh",
                                      withExtension: "mlmodelc") {
            do {
                model = try MLModel(contentsOf: url, configuration: config)
                isReady = true
                logger.info("GoEvaluator: loaded compiled model (mlmodelc)")
            } catch {
                logger.error("GoEvaluator: failed to load mlmodelc: \(error.localizedDescription)")
            }
        } else {
            logger.warning("GoEvaluator: no compiled model found. Add KataGoModel19x19fp16m1w8LiCh.mlpackage to the Xcode project.")
        }
    }

    // MARK: - Evaluate

    /// Evaluate a GoBoards position using the real KataGo CoreML model.
    /// Returns 19×19 ownership map [-1, 1].
    func evaluate(_ boards: GoBoards) -> GoOwnership? {
        guard let model = model else { return nil }

        // Encode the 3 Go boards into KataGo's 22-channel input format
        guard let spatialInput = encodeSpatialInput(boards),
              let globalInput = encodeGlobalInput(),
              let metaInput = encodeMetaInput() else {
            return nil
        }

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "input_spatial": MLFeatureValue(multiArray: spatialInput),
                "input_global": MLFeatureValue(multiArray: globalInput),
                "input_meta": MLFeatureValue(multiArray: metaInput)
            ])

            let result = try model.prediction(from: provider)

            guard let ownership = result.featureValue(for: "out_ownership")?.multiArrayValue else {
                logger.error("GoEvaluator: no ownership output")
                return nil
            }

            return decodeOwnership(ownership)
        } catch {
            logger.error("GoEvaluator: prediction failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Input Encoding

    /// Encode GoBoards into KataGo's 22-channel spatial input.
    /// We use channels 0-2 for our color-comparison boards:
    ///   Channel 0: board validity (all 1.0)
    ///   Channel 1: Black stones (channel A > B) — "own stones"
    ///   Channel 2: White stones (channel B > A) — "opponent stones"
    ///   Channels 3-21: zeroed (no move history, ko, ladders, etc.)
    ///
    /// We evaluate the R/G board as the primary position.
    /// For the full evaluation, call 3 times (R/G, G/B, B/R).
    private func encodeSpatialInput(_ boards: GoBoards) -> MLMultiArray? {
        guard let array = try? MLMultiArray(shape: [1, 22, 19, 19], dataType: .float32) else {
            return nil
        }

        // Zero all channels first
        let total = 1 * 22 * 19 * 19
        for i in 0..<total {
            array[i] = NSNumber(value: Float(0))
        }

        // Use the R/G board as the primary position
        let board = boards.rg

        for y in 0..<GoBoard.size {
            for x in 0..<GoBoard.size {
                let stone = board[x, y]

                // Channel 0: board validity (all 1.0 for 19×19)
                array[[0, 0, y, x] as [NSNumber]] = NSNumber(value: Float(1.0))

                // Channel 1: Black stones (own)
                if stone == .black {
                    array[[0, 1, y, x] as [NSNumber]] = NSNumber(value: Float(1.0))
                }

                // Channel 2: White stones (opponent)
                if stone == .white {
                    array[[0, 2, y, x] as [NSNumber]] = NSNumber(value: Float(1.0))
                }
            }
        }

        return array
    }

    /// Encode global input (19 features). Mostly zeros for our use case.
    private func encodeGlobalInput() -> MLMultiArray? {
        guard let array = try? MLMultiArray(shape: [1, 19], dataType: .float32) else {
            return nil
        }
        for i in 0..<19 {
            array[i] = NSNumber(value: Float(0))
        }
        return array
    }

    /// Encode metadata input (192 features). All zeros.
    private func encodeMetaInput() -> MLMultiArray? {
        guard let array = try? MLMultiArray(shape: [1, 192], dataType: .float32) else {
            return nil
        }
        for i in 0..<192 {
            array[i] = NSNumber(value: Float(0))
        }
        return array
    }

    // MARK: - Output Decoding

    /// Decode the ownership output (1, 1, 19, 19) → GoOwnership.
    private func decodeOwnership(_ array: MLMultiArray) -> GoOwnership {
        var values = [Float](repeating: 0, count: GoBoard.count)
        for y in 0..<GoBoard.size {
            for x in 0..<GoBoard.size {
                let idx = [0, 0, y, x] as [NSNumber]
                values[y * GoBoard.size + x] = array[idx].floatValue
            }
        }
        return GoOwnership(values: values)
    }
}

// MARK: - Ownership Result

/// 19×19 ownership map from KataGo CoreML evaluation.
/// Values in [-1, 1]: negative = Black territory, positive = White.
struct GoOwnership {
    let values: [Float]  // 361 elements, row-major

    /// Pixels near 0 are contested — best dithering candidates.
    var contestedCount: Int {
        values.filter { abs($0) < 0.3 }.count
    }

    /// Average ownership magnitude (0 = contested, 1 = settled).
    var settledness: Float {
        values.reduce(Float(0)) { $0 + abs($1) } / Float(max(1, values.count))
    }

    subscript(x: Int, y: Int) -> Float {
        values[y * GoBoard.size + x]
    }
}
