// GIFEncoder.swift
// Tesseract
//
// GIF89a encoder with the 4⁴ = 256 tesseract palette.
// 64 frames at 20fps, infinite loop.
// Uses ImageIO (built-in, no dependencies).

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes quantized frames into an animated GIF.
struct GIFEncoder {

    /// Frame delay for 20fps = 1/20 = 0.05 seconds
    /// GIF stores delay in centiseconds: 5 (= 50ms)
    static let frameDelay: Int = 5  // centiseconds

    /// Encode quantized frames → GIF Data
    static func encode(frames: [QuantizedFrame]) -> Data? {
        guard !frames.isEmpty else { return nil }

        let size = QuantizedFrame.size  // 64

        // Create GIF destination in memory
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, frames.count, nil
        ) else { return nil }

        // GIF-level properties: loop forever
        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0  // infinite loop
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // Frame-level properties
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: Float(frameDelay) / 100.0
            ]
        ]

        // Encode each frame
        for frame in frames {
            guard let image = createCGImage(from: frame) else { continue }
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { return nil }

        return data as Data
    }

    /// Create a CGImage from a quantized frame using the tesseract palette.
    private static func createCGImage(from frame: QuantizedFrame) -> CGImage? {
        let size = QuantizedFrame.size
        var rgbaData = [UInt8](repeating: 255, count: size * size * 4)

        for i in 0..<(size * size) {
            let idx = frame.paletteIndices[i]
            let coord = TesseractCoord(index: idx)
            let (r, g, b) = coord.sRGB8
            rgbaData[i * 4]     = r
            rgbaData[i * 4 + 1] = g
            rgbaData[i * 4 + 2] = b
            // alpha = 255 (already set)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rgbaData,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        return context.makeImage()
    }

    // MARK: - Save to Photos

    /// Save GIF data to the photo library.
    /// Returns the temporary file URL.
    static func saveToTempFile(_ data: Data) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("tesseract_\(Int(Date().timeIntervalSince1970)).gif")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
