// TesseractPalette.swift
// Tesseract
//
// The 4⁴ = 256 palette as a GIF color table.
// Each entry maps to an sRGB color via TesseractCoord.sRGB.
// 4 entries per display color (one per epoch).
// Depth drives SNR: near pixels get stable epochs, far pixels shimmer.

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

    /// Quantize a full frame with depth-driven SNR cadence.
    ///
    /// When `depthZones` is provided, near pixels (zone 0) get stable epoch
    /// assignment and far pixels (zone 3) get volatile assignment.
    /// This is signal-to-noise ratio applied to the temporal axis.
    ///
    /// - Parameters:
    ///   - z: Frame index (0..63)
    ///   - pixels: 4096 sRGB pixels in [0,1]
    ///   - depthZones: Optional per-pixel depth zone (0=near/signal, 3=far/noise)
    ///   - width: Frame width (64)
    ///   - seed: PRNG seed
    /// - Returns: 4096 palette indices
    static func quantizeFrame(
        frame z: Int,
        pixels: [(Float, Float, Float)],
        depthZones: [UInt8]? = nil,
        width: Int = 64,
        seed: UInt32 = 42
    ) -> [UInt8] {
        pixels.enumerated().map { (i, pixel) in
            let x = i % width
            let y = i / width

            let epoch: UInt8
            if let zones = depthZones, i < zones.count {
                // Depth-aware: near pixels → stable, far pixels → volatile
                epoch = BinomialCadence.sampleEpoch(
                    frame: z, x: x, y: y,
                    depthZone: zones[i], seed: seed
                )
            } else {
                // No depth: uniform cadence (preview mode)
                epoch = BinomialCadence.sampleEpoch(
                    frame: z, x: x, y: y, seed: seed
                )
            }

            let tc = TesseractCoord.quantize(
                epoch: epoch, r: pixel.0, g: pixel.1, b: pixel.2
            )
            return tc.index
        }
    }
}
