// QuantizedImage.swift
// Tesseract
//
// One image builder for the COARSE reads (spec/ui/WidgetGrid.hs WG12:
// the 64³, 32³ and 16³ instruments coexist). The fine read keeps the
// builders the two managers already own; this is the shared one the
// new rungs needed, so a third copy of "indices + table → CGImage"
// does not appear.
//
// The image is `side × side` palette indices resolved through the
// live DYAD table — NEVER an interpolated resample of the fine image.
// Interpolating (or point-sampling) the finished picture would show a
// rung the ladder does not have; the coarse windows are pooled FEED
// re-assigned by the export's own law (DyadPipeline.Live.coarseReads),
// which is why all three windows agree (OV4: pool ∘ up = id).

import CoreGraphics
import Foundation

enum QuantizedImage {

    /// `side²` indices painted with a 256-entry table. Returns nil on
    /// a short table or a length mismatch — a half-painted instrument
    /// is worse than a widget that states its own shape.
    static func make(indices: [UInt8], side: Int,
                     table: [(UInt8, UInt8, UInt8)]) -> CGImage? {
        guard side > 0, indices.count == side * side,
              table.count == CameraConfig.paletteSize else { return nil }
        var rgba = [UInt8](repeating: 255, count: side * side * 4)
        for i in 0..<(side * side) {
            let (r, g, b) = table[Int(indices[i])]
            rgba[i * 4] = r; rgba[i * 4 + 1] = g; rgba[i * 4 + 2] = b
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        // The buffer pointer must outlive `makeImage()`, so the context is
        // built and drained INSIDE the access. `&rgba` would only be valid
        // for the duration of the CGContext call itself (Swift inout-to-
        // pointer lifetime rule) — the image would then read freed memory.
        return rgba.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            return ctx.makeImage()
        }
    }

    /// The 768-byte GIF color table for the surface's palette widget —
    /// the same packing `CellPalette` already consumes, so the widget
    /// draws the bytes the encoder writes and not a re-derivation.
    static func packed(_ table: [(UInt8, UInt8, UInt8)]) -> Data? {
        guard table.count == CameraConfig.paletteSize else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(table.count * 3)
        for e in table { bytes.append(e.0); bytes.append(e.1); bytes.append(e.2) }
        return Data(bytes)
    }
}
