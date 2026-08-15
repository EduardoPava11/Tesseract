// TesseractPalette.swift
// Tesseract
//
// The 4^4 = 256 palette table and GIF color table.
// Static data — no quantization logic here.
// Quantization is handled by PerfectQuantizer.

import Foundation

struct TesseractPalette {

    /// All 256 palette entries as (R, G, B) 8-bit tuples.
    /// Index i → TesseractCoord(index: i).sRGB8
    /// Canonical values per channel: {32, 96, 159, 223}
    static let table: [(UInt8, UInt8, UInt8)] = {
        (0..<256).map { TesseractCoord(index: UInt8($0)).sRGB8 }
    }()

    /// 64 unique display colors (4 epochs share each sRGB).
    static let uniqueDisplayColors: Int = 64

    /// 4 epochs per display color.
    static let epochsPerColor: Int = 4

    /// GIF Global Color Table: 768 bytes (256 × 3 RGB).
    /// Written directly into the GIF89a header.
    static let gifColorTable: Data = {
        var data = Data(capacity: 768)
        for (r, g, b) in table { data.append(r); data.append(g); data.append(b) }
        return data
    }()
}
