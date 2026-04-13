// TesseractPalette.swift
// Tesseract
//
// The 4⁴ = 256 palette as a GIF color table.
// Each entry maps to an sRGB color via TesseractCoord.sRGB.
// 4 entries per display color (one per epoch).

import Foundation

/// The global tesseract palette for GIF encoding.
struct TesseractPalette {

    /// 256-entry palette: index → (R, G, B) in 0-255
    static let table: [(UInt8, UInt8, UInt8)] = {
        (0..<256).map { i in
            TesseractCoord(index: UInt8(i)).sRGB8
        }
    }()

    /// 64 unique display colors (epochs collapsed)
    static let uniqueDisplayColors: Int = 64  // 4³

    /// How many palette entries share each display color
    static let epochsPerColor: Int = 4

    /// Flat RGB data for GIF global color table (768 bytes)
    static let gifColorTable: Data = {
        var data = Data(capacity: 768)
        for (r, g, b) in table {
            data.append(r); data.append(g); data.append(b)
        }
        return data
    }()

    /// Quantize a full frame: [sRGB pixels] → [palette indices]
    /// using binomial cadence for epoch assignment.
    static func quantizeFrame(
        frame z: Int,
        pixels: [(Float, Float, Float)],  // sRGB in [0,1]
        width: Int = 64,
        seed: UInt32 = 42
    ) -> [UInt8] {
        pixels.enumerated().map { (i, pixel) in
            let x = i % width
            let y = i / width
            let epoch = BinomialCadence.sampleEpoch(frame: z, x: x, y: y, seed: seed)
            let tc = TesseractCoord.quantize(epoch: epoch, r: pixel.0, g: pixel.1, b: pixel.2)
            return tc.index
        }
    }
}
