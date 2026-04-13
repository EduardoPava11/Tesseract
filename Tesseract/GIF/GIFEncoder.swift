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
    static func encode(frames: [QuantizedFrame], measure: BirkhoffMeasure? = nil) -> Data? {
        guard !frames.isEmpty else { return nil }

        let size = QuantizedFrame.size  // 64

        // Create GIF destination in memory
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, frames.count, nil
        ) else { return nil }

        // GIF-level properties: loop forever + metadata comment
        var gifDict: [String: Any] = [
            kCGImagePropertyGIFLoopCount as String: 0
        ]
        // Embed stats as GIF comment (travels with the file)
        if let m = measure {
            let comment = "Tesseract 4⁴ | M=\(String(format: "%.1f", m.beauty)) O=\(String(format: "%.0f", m.order)) C=\(String(format: "%.3f", m.complexity)) dim=\(String(format: "%.2f", m.manifoldDim)) colors=\(m.colorsUsed)/256 | R1⊕R3=R4 σ=7.875"
            gifDict[kCGImagePropertyGIFUnclampedDelayTime as String] = comment
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: gifDict
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
