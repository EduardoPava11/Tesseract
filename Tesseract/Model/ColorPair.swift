// ColorPair.swift
// Tesseract
//
// Depth-guided color pairing: two colors working together
// at a given depth level form a texture pair.

import simd

/// A depth zone: one of 4 layers (near → far)
struct DepthZone {
    let level: UInt8       // 0=near, 1=mid-near, 2=mid-far, 3=far
    let pixelCount: Int
    let dominantPair: ColorPair
}

/// A texture pair: two palette colors that co-occur at a depth level.
/// Their binomial frequencies encode the texture signal.
struct ColorPair: CustomStringConvertible {
    let colorA: TesseractCoord   // more frequent
    let colorB: TesseractCoord   // less frequent
    let countA: Int
    let countB: Int

    /// Fraction of the zone these two colors cover
    var coverage: Float {
        Float(countA + countB) / max(1, Float(countA + countB))
    }

    /// Ratio between the two colors (1.0 = equal, higher = A dominates)
    var ratio: Float {
        Float(countA) / max(1, Float(countB))
    }

    /// sRGB distance between the pair
    var colorDistance: Float {
        simd_distance(colorA.sRGB, colorB.sRGB)
    }

    var description: String {
        "\(colorA) ↔ \(colorB) ratio=\(String(format: "%.2f", ratio))"
    }

    // MARK: - Extract dominant pair from a set of pixels

    /// Given palette indices for pixels in a depth zone,
    /// find the two most frequent colors.
    static func extract(from indices: [UInt8]) -> ColorPair {
        var histogram = [UInt8: Int]()
        for idx in indices {
            histogram[idx, default: 0] += 1
        }
        let sorted = histogram.sorted { $0.value > $1.value }
        let topA = sorted.first ?? (key: 0, value: 0)
        let topB = sorted.dropFirst().first ?? (key: 0, value: 0)
        return ColorPair(
            colorA: TesseractCoord(index: topA.key),
            colorB: TesseractCoord(index: topB.key),
            countA: topA.value,
            countB: topB.value
        )
    }
}
