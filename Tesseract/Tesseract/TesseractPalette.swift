// TesseractPalette.swift
// Tesseract
//
// The 4⁴ = 256 palette. Depth is continuous Float, not UInt8 zones.

import Foundation

struct TesseractPalette {

    static let table: [(UInt8, UInt8, UInt8)] = {
        (0..<256).map { TesseractCoord(index: UInt8($0)).sRGB8 }
    }()

    static let uniqueDisplayColors: Int = 64
    static let epochsPerColor: Int = 4

    static let gifColorTable: Data = {
        var data = Data(capacity: 768)
        for (r, g, b) in table { data.append(r); data.append(g); data.append(b) }
        return data
    }()

    /// Quantize a frame with continuous depth.
    /// depth drives σ continuously: σ = σ_base × (2 - depth).
    /// No zones. No lookup table. The 4 epochs emerge from the Gaussians.
    static func quantizeFrame(
        frame z: Int,
        pixels: [(Float, Float, Float)],
        depths: [Float]? = nil,
        width: Int = 64,
        seed: UInt32 = 42
    ) -> [UInt8] {
        pixels.enumerated().map { (i, pixel) in
            let x = i % width
            let y = i / width

            let epoch: UInt8
            if let d = depths, i < d.count {
                epoch = BinomialCadence.sampleEpoch(
                    frame: z, x: x, y: y, depth: d[i], seed: seed
                )
            } else {
                epoch = BinomialCadence.sampleEpoch(
                    frame: z, x: x, y: y, seed: seed
                )
            }

            return TesseractCoord.quantize(
                epoch: epoch, r: pixel.0, g: pixel.1, b: pixel.2
            ).index
        }
    }
}
