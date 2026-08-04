// GIFEncoder.swift
// Tesseract
//
// GIF89a binary encoder with the 4^4 = 256 tesseract palette.
// Writes raw palette indices via LZW — NO CGImageDestination,
// NO re-quantization. The 256-entry Global Color Table is
// TesseractPalette.gifColorTable, written byte-for-byte.
//
// LZW encoder adapted from ROTAS (production-tested).

import Foundation

/// Encodes quantized frames into an animated GIF preserving the tesseract palette.
struct GIFEncoder {

    /// Frame delay for 20fps = 0.05s = 5 centiseconds
    static let frameDelayCentiseconds: UInt16 = 5

    // MARK: - Encode

    /// Encode quantized frames → GIF89a Data with preserved 4^4 palette.
    ///
    /// `upscale` replicates each palette index into a factor×factor block at
    /// emit time (fat voxels, INDEX domain — never colors, no interpolation).
    /// Default 1 preserves the existing byte-exact 64×64 output.
    static func encode(frames: [QuantizedFrame], measure: BirkhoffMeasure? = nil, upscale: Int = 1,
                       refined: RefinedPalette? = nil) -> Data? {
        encode(
            indexFrames: frames.map(\.paletteIndices),
            side: QuantizedFrame.size,    // 64
            measure: measure,
            upscale: upscale,
            refined: refined
        )
    }

    /// Side-parameterized variant for the DNG rung ladder (S ∈ {64, 256, 1024}):
    /// same GIF89a stream, same tesseract GCT, arbitrary square side.
    /// The QuantizedFrame overload above delegates here — one encoder.
    ///
    /// `refined` (pass 2, CentroidRefiner) substitutes a per-capture
    /// color table whose entries are cell-clamped — indices unchanged,
    /// reconstruction refined. nil = the canonical tesseract table.
    static func encode(indexFrames: [[UInt8]], side: Int, measure: BirkhoffMeasure? = nil, upscale: Int = 1,
                       refined: RefinedPalette? = nil) -> Data? {
        guard !indexFrames.isEmpty, side >= 1, upscale >= 1,
              indexFrames.allSatisfy({ $0.count == side * side }) else { return nil }

        let frames = indexFrames
        let width = side * upscale
        let height = side * upscale

        var data = Data()
        data.reserveCapacity(frames.count * 2048)

        // ── 1. GIF89a Header ──
        data.append(contentsOf: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])

        // ── 2. Logical Screen Descriptor ──
        //   packed byte 0xF7:
        //     bit 7   = 1 (GCT present)
        //     bits 4-6 = 7 (color resolution = 8 bits)
        //     bit 3   = 0 (GCT not sorted)
        //     bits 0-2 = 7 (GCT size = 2^(7+1) = 256 entries)
        data.append(contentsOf: [
            UInt8(width & 0xFF), UInt8((width >> 8) & 0xFF),
            UInt8(height & 0xFF), UInt8((height >> 8) & 0xFF),
            0xF7,   // packed: GCT flag=1, 256 entries
            0x00,   // background color index
            0x00    // pixel aspect ratio
        ])

        // ── 3. Global Color Table (256 × 3 = 768 bytes) ──
        //   Canonical: index i → TesseractCoord(index: i).sRGB8.
        //   Refined (pass 2): per-capture centroids, every entry inside
        //   its lattice cell (WL1) so re-quantization is unchanged.
        data.append(refined?.gifColorTable ?? TesseractPalette.gifColorTable)

        // ── 4. NETSCAPE2.0 Loop Extension (infinite) ──
        data.append(contentsOf: [
            0x21, 0xFF,                                             // application extension
            0x0B,                                                    // block size = 11
            0x4E, 0x45, 0x54, 0x53, 0x43, 0x41, 0x50, 0x45,       // "NETSCAPE"
            0x32, 0x2E, 0x30,                                       // "2.0"
            0x03, 0x01,                                              // sub-block: 3 bytes, data sub-block index 1
            0x00, 0x00,                                              // loop count = 0 (infinite)
            0x00                                                     // block terminator
        ])

        // ── 5. Comment Extension (Birkhoff measure) ──
        if let m = measure {
            let comment = "Tesseract 4^4 | M=\(String(format: "%.1f", m.beauty)) O=\(String(format: "%.0f", m.order)) C=\(String(format: "%.3f", m.complexity)) dim=\(String(format: "%.2f", m.manifoldDim)) colors=\(m.colorsUsed)/256 | R1+R3=R4 sigma=\(String(format: "%.3f", BinomialCadence.sigmaBase))"
            writeCommentExtension(comment, to: &data)
        }

        // ── 5b. Comment Extension (pass-2 push/pull trace provenance) ──
        //   Derived from the palette itself — table and trace cannot
        //   disagree, and the schedule rides along (RefinedPalette).
        if let refined {
            writeCommentExtension(refined.traceComment, to: &data)
        }

        // ── 6. Frames ──
        let delay = frameDelayCentiseconds
        for frame in frames {
            // Graphics Control Extension (8 bytes)
            data.append(contentsOf: [
                0x21, 0xF9, 0x04,                           // GCE introducer
                0x00,                                        // packed: disposal=0, no transparency
                UInt8(delay & 0xFF), UInt8((delay >> 8) & 0xFF),  // delay in centiseconds
                0x00,                                        // transparent color index (unused)
                0x00                                         // block terminator
            ])

            // Image Descriptor (10 bytes, no local color table)
            data.append(contentsOf: [
                0x2C,                                        // image separator
                0x00, 0x00,                                  // left = 0
                0x00, 0x00,                                  // top = 0
                UInt8(width & 0xFF), UInt8((width >> 8) & 0xFF),
                UInt8(height & 0xFF), UInt8((height >> 8) & 0xFF),
                0x00                                         // packed: no LCT, not interlaced
            ])

            // LZW-compressed palette indices (minCodeSize = 8 for 256 colors)
            let indices = upscale == 1
                ? frame
                : replicate(frame, side: side, factor: upscale)
            #if DEBUG
            if upscale > 1, frame == frames[0] {
                // SixFour selfCheck contract: decimate(replicate(x)) == x
                assert(decimate(indices, side: side, factor: upscale) == frame,
                       "GIFEncoder: replicate/decimate round-trip failed")
            }
            #endif
            data.append(lzwEncode(indices, minCodeSize: 8))
        }

        // ── 7. Trailer ──
        data.append(0x3B)

        return data
    }

    // MARK: - Index-domain replication (fat voxels)

    /// Nearest-neighbor replication of palette INDICES: each source cell
    /// becomes a factor×factor block. No color math, no interpolation.
    static func replicate(_ cells: [UInt8], side: Int, factor: Int) -> [UInt8] {
        let outSide = factor * side
        var out = [UInt8](repeating: 0, count: outSide * outSide)
        for oy in 0..<outSide {
            let sy = oy / factor
            for ox in 0..<outSide {
                out[oy * outSide + ox] = cells[sy * side + ox / factor]
            }
        }
        return out
    }

    /// Inverse of `replicate` (takes the top-left sample of each block).
    static func decimate(_ cells: [UInt8], side: Int, factor: Int) -> [UInt8] {
        let outSide = factor * side
        var out = [UInt8](repeating: 0, count: side * side)
        for y in 0..<side {
            for x in 0..<side {
                out[y * side + x] = cells[(y * factor) * outSide + x * factor]
            }
        }
        return out
    }

    // MARK: - Comment Extension

    private static func writeCommentExtension(_ comment: String, to data: inout Data) {
        let bytes = Array(comment.utf8)
        data.append(contentsOf: [0x21, 0xFE])  // comment extension introducer
        var remaining = bytes[...]
        while !remaining.isEmpty {
            let chunk = remaining.prefix(255)
            data.append(UInt8(chunk.count))
            data.append(contentsOf: chunk)
            remaining = remaining.dropFirst(chunk.count)
        }
        data.append(0x00)  // block terminator
    }

    // MARK: - LZW Compression (adapted from ROTAS)

    /// LZW compression for GIF. Writes minCodeSize byte + sub-blocks + terminator.
    /// Uses [UInt8] dictionary keys for fast hashing.
    private static func lzwEncode(_ pixels: [UInt8], minCodeSize: UInt8) -> Data {
        var result = Data()
        result.append(minCodeSize)

        let clearCode = 1 << Int(minCodeSize)
        let endCode = clearCode + 1

        var dictionary = [[UInt8]: Int]()
        var codeSize = Int(minCodeSize) + 1
        var nextCode = endCode + 1
        let maxCode = 4095

        var bitBuffer: UInt32 = 0
        var bitsInBuffer = 0
        var subBlock = [UInt8]()
        subBlock.reserveCapacity(255)

        func outputCode(_ code: Int) {
            bitBuffer |= UInt32(code) << bitsInBuffer
            bitsInBuffer += codeSize
            while bitsInBuffer >= 8 {
                subBlock.append(UInt8(bitBuffer & 0xFF))
                bitBuffer >>= 8
                bitsInBuffer -= 8
                if subBlock.count == 255 {
                    result.append(UInt8(subBlock.count))
                    result.append(contentsOf: subBlock)
                    subBlock.removeAll(keepingCapacity: true)
                }
            }
        }

        func initDictionary() {
            dictionary.removeAll(keepingCapacity: true)
            for i in 0..<clearCode {
                dictionary[[UInt8(i)]] = i
            }
            nextCode = endCode + 1
            codeSize = Int(minCodeSize) + 1
        }

        initDictionary()
        outputCode(clearCode)

        var current = [UInt8]()
        current.reserveCapacity(16)
        for pixel in pixels {
            current.append(pixel)
            if dictionary[current] != nil {
                // current is in dictionary — keep extending
            } else {
                // Output code for current minus last byte
                let prev = Array(current.dropLast())
                outputCode(dictionary[prev]!)
                if nextCode <= maxCode {
                    dictionary[current] = nextCode
                    nextCode += 1
                    if nextCode > (1 << codeSize) && codeSize < 12 {
                        codeSize += 1
                    }
                } else {
                    outputCode(clearCode)
                    initDictionary()
                }
                current = [pixel]
            }
        }

        if !current.isEmpty {
            outputCode(dictionary[current]!)
        }
        outputCode(endCode)

        if bitsInBuffer > 0 {
            subBlock.append(UInt8(bitBuffer & 0xFF))
        }
        if !subBlock.isEmpty {
            result.append(UInt8(subBlock.count))
            result.append(contentsOf: subBlock)
        }
        result.append(0x00)  // block terminator
        return result
    }

    // MARK: - Save to Photos

    /// Save GIF data to a temporary file for sharing.
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
