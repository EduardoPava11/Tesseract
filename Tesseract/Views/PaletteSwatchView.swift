// PaletteSwatchView.swift
// Tesseract
//
// 16×16 palette swatch: all 256 tesseract colors laid out on a grid.
// Each pixel = one palette entry, displayed at the atom pitch
// (16 cells = 64pt). The GIF's DNA.

import SwiftUI

/// Static 16×16 image of all 256 tesseract palette colors.
struct PaletteSwatchView: View {
    /// The palette image, generated once
    private static let paletteImage: CGImage? = generatePaletteImage()

    var body: some View {
        if let img = Self.paletteImage {
            Image(decorative: img, scale: 1.0)
                .interpolation(.none)  // pixel-perfect
                .resizable()
                .frame(width: Lattice.gif(TesseractLattice.paletteCells),
                       height: Lattice.gif(TesseractLattice.paletteCells))
                .pixelFrame()
        }
    }

    /// Generate a 16×16 CGImage where pixel (x,y) = palette index y*16+x
    private static func generatePaletteImage() -> CGImage? {
        let size = 16
        var rgba = [UInt8](repeating: 255, count: size * size * 4)

        for y in 0..<size {
            for x in 0..<size {
                let idx = y * size + x
                let coord = TesseractCoord(index: UInt8(idx))
                let (r, g, b) = coord.sRGB8
                let i = (y * size + x) * 4
                rgba[i] = r
                rgba[i + 1] = g
                rgba[i + 2] = b
                // alpha = 255
            }
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &rgba, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }
}
