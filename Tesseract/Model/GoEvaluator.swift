// GoEvaluator.swift
// Tesseract
//
// CoreML-based Go territory evaluation.
// Loads GoEval.mlpackage and evaluates 19×19 color-comparison boards.
//
// Input:  GoBoards (3 × 19×19 boards: R/G, G/B, B/R)
// Output: 19×19 ownership map [-1, 1] per board
//
// Pre-filtered: only blocks with complexity > 0.2 get NN evaluation.
// Others use simple territory counting from GoBoard.swift.
//
// Memory per evaluation: 3 × 361 × 4 bytes input + 361 × 4 bytes output = ~5.8 KB

import CoreML
import os.log

private let logger = Logger(subsystem: "com.tesseract.app", category: "GoEvaluator")

/// CoreML-based Go territory evaluator.
/// Wraps the GoEval.mlpackage model for 19×19 board evaluation.
final class GoEvaluator {

    private var model: MLModel?
    private(set) var isReady = false

    init() {
        loadModel()
    }

    // MARK: - Model Loading

    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all  // CPU + GPU + Neural Engine

            // Xcode auto-generates the GoEval class from GoEval.mlpackage
            if let modelURL = Bundle.main.url(forResource: "GoEval", withExtension: "mlmodelc") {
                model = try MLModel(contentsOf: modelURL, configuration: config)
                isReady = true
                logger.info("GoEvaluator: model loaded from mlmodelc")
            } else {
                // Try loading from mlpackage directly
                let config2 = MLModelConfiguration()
                config2.computeUnits = .all
                // Model might be compiled at build time
                logger.warning("GoEvaluator: mlmodelc not found, model may not be added to project")
            }
        } catch {
            logger.error("GoEvaluator: failed to load model: \(error.localizedDescription)")
        }
    }

    // MARK: - Evaluate

    /// Evaluate a GoBoards (3 channel-pair boards) using the CoreML model.
    /// Returns 19×19 ownership map [-1, 1] for each board.
    /// Returns nil if model not loaded or evaluation fails.
    func evaluate(_ boards: GoBoards) -> GoOwnership? {
        guard let model = model else { return nil }

        // Encode 3 boards into a (1, 3, 19, 19) MLMultiArray
        guard let input = encodeBoards(boards) else { return nil }

        do {
            let provider = try MLDictionaryFeatureProvider(
                dictionary: ["board": MLFeatureValue(multiArray: input)]
            )
            let result = try model.prediction(from: provider)

            // Decode ownership output
            guard let ownership = result.featureValue(for: "ownership")?.multiArrayValue else {
                return nil
            }

            return decodeOwnership(ownership)
        } catch {
            logger.error("GoEvaluator: prediction failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Encode/Decode

    /// Encode GoBoards → MLMultiArray (1, 3, 19, 19)
    /// Black = 1.0, White = -1.0, Empty = 0.0
    private func encodeBoards(_ boards: GoBoards) -> MLMultiArray? {
        guard let array = try? MLMultiArray(shape: [1, 3, 19, 19], dataType: .float32) else {
            return nil
        }

        let allBoards = [boards.rg, boards.gb, boards.br]
        for (c, board) in allBoards.enumerated() {
            for y in 0..<GoBoard.size {
                for x in 0..<GoBoard.size {
                    let idx = [0, c, y, x] as [NSNumber]
                    let value: Float = switch board[x, y] {
                    case .black: 1.0
                    case .white: -1.0
                    case .empty: 0.0
                    }
                    array[idx] = NSNumber(value: value)
                }
            }
        }

        return array
    }

    /// Decode MLMultiArray (1, 1, 19, 19) → GoOwnership
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

/// 19×19 ownership map from CoreML evaluation.
/// Values in [-1, 1]: negative = Black territory, positive = White.
/// Memory: 361 × 4 bytes = 1,444 bytes.
struct GoOwnership {
    let values: [Float]  // 361 elements, row-major

    /// How many positions are contested (|ownership| < 0.3)?
    /// These are the best dithering candidates.
    var contestedCount: Int {
        values.filter { abs($0) < 0.3 }.count
    }

    /// Average ownership magnitude (0 = fully contested, 1 = fully settled)
    var settledness: Float {
        let sum = values.reduce(Float(0)) { $0 + abs($1) }
        return sum / Float(max(1, values.count))
    }

    subscript(x: Int, y: Int) -> Float {
        values[y * GoBoard.size + x]
    }
}
