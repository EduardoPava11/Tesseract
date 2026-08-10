// GeneCapsule.swift
// Tesseract
//
// Port of ROTAS GIFEngram.hs gene capsule encoding.
// Int8-quantized NN weights stored in a GIF Application Extension Block.
//
// Format: "TESSERACT04" identifier + Int8 weights + scale/zero-point header.
// Standard GIF viewers ignore this block. Tesseract reads it.
// Share a GIF = share a gene = share a way of seeing.

import Foundation

struct GeneCapsule {

    // ════════════════════════════════════════════════════════════
    // § 1. ENCODE — Float32 gene → Int8 capsule
    // ════════════════════════════════════════════════════════════

    /// Quantize gene weights to Int8 with per-layer scale/zero-point.
    /// Returns the capsule data (header + quantized weights).
    ///
    /// Layout:
    ///   [0..3]   Float32 attention_scale
    ///   [4..7]   Float32 attention_zero
    ///   [8..11]  Float32 core_scale
    ///   [12..15] Float32 core_zero
    ///   [16..]   Int8 quantized weights (4581 bytes)
    ///   Total: 16 + 4581 = 4597 bytes
    static func encode(_ gene: GeneWeights) -> Data {
        var data = Data()
        data.reserveCapacity(16 + GeneWeights.totalCount)

        // ATTENTION quantization (first 4416 weights)
        let attnSlice = Array(gene.weights[0..<GeneWeights.attentionCount])
        let (attnScale, attnZero) = scaleZeroPoint(attnSlice)

        // CORE quantization (last 132 weights)
        let coreSlice = Array(gene.weights[GeneWeights.attentionCount..<GeneWeights.totalCount])
        let (coreScale, coreZero) = scaleZeroPoint(coreSlice)

        // Write header (4 Float32 = 16 bytes)
        appendFloat(&data, attnScale)
        appendFloat(&data, attnZero)
        appendFloat(&data, coreScale)
        appendFloat(&data, coreZero)

        // Write quantized weights
        for w in attnSlice {
            data.append(quantize(w, scale: attnScale, zero: attnZero))
        }
        for w in coreSlice {
            data.append(quantize(w, scale: coreScale, zero: coreZero))
        }

        return data
    }

    // ════════════════════════════════════════════════════════════
    // § 2. DECODE — Int8 capsule → Float32 gene
    // ════════════════════════════════════════════════════════════

    /// Dequantize Int8 capsule back to Float32 gene weights.
    static func decode(_ data: Data) -> GeneWeights? {
        let expectedSize = 16 + GeneWeights.totalCount  // 4564
        guard data.count >= expectedSize else { return nil }

        let bytes = [UInt8](data)

        // Read header
        let attnScale = readFloat(bytes, offset: 0)
        let attnZero  = readFloat(bytes, offset: 4)
        let coreScale = readFloat(bytes, offset: 8)
        let coreZero  = readFloat(bytes, offset: 12)

        // Dequantize weights
        var weights = [Float]()
        weights.reserveCapacity(GeneWeights.totalCount)

        for i in 0..<GeneWeights.attentionCount {
            let q = Int8(bitPattern: bytes[16 + i])
            weights.append(dequantize(q, scale: attnScale, zero: attnZero))
        }
        for i in 0..<GeneWeights.coreCount {
            let q = Int8(bitPattern: bytes[16 + GeneWeights.attentionCount + i])
            weights.append(dequantize(q, scale: coreScale, zero: coreZero))
        }

        return GeneWeights(weights: weights)
    }

    // ════════════════════════════════════════════════════════════
    // § 3. GIF EXTENSION BLOCK — write/extract from GIF data
    // ════════════════════════════════════════════════════════════

    /// Application Extension Block identifier (11 bytes, matches ROTAS "RG\0" convention)
    static let identifier = "TESSERACT04"  // 11 ASCII bytes

    /// Write gene capsule as a GIF Application Extension Block.
    /// Returns the extension block bytes (to be inserted into GIF stream).
    static func gifExtensionBlock(_ gene: GeneWeights) -> Data {
        let capsule = encode(gene)
        var block = Data()

        // Extension introducer
        block.append(0x21)  // Extension
        block.append(0xFF)  // Application Extension label

        // Application identifier (11 bytes)
        block.append(0x0B)  // Block size = 11
        block.append(contentsOf: identifier.utf8)

        // Sub-blocks: split capsule into 255-byte chunks
        var offset = 0
        while offset < capsule.count {
            let chunkSize = min(255, capsule.count - offset)
            block.append(UInt8(chunkSize))
            block.append(capsule[offset..<offset + chunkSize])
            offset += chunkSize
        }

        // Block terminator
        block.append(0x00)

        return block
    }

    /// Extract gene capsule from a GIF data blob.
    /// Searches for the "TESSERACT04" application extension.
    static func extract(fromGIF gifData: Data) -> GeneWeights? {
        let bytes = [UInt8](gifData)
        let idBytes = [UInt8](identifier.utf8)

        // Search for 0x21 0xFF 0x0B followed by identifier
        var i = 0
        while i < bytes.count - 14 {
            if bytes[i] == 0x21 && bytes[i+1] == 0xFF && bytes[i+2] == 0x0B {
                // Check identifier
                let slice = Array(bytes[(i+3)..<(i+14)])
                if slice == idBytes {
                    // Found it — read sub-blocks
                    var capsuleData = Data()
                    var j = i + 14
                    while j < bytes.count {
                        let blockSize = Int(bytes[j])
                        j += 1
                        if blockSize == 0 { break }  // terminator
                        guard j + blockSize <= bytes.count else { break }
                        capsuleData.append(contentsOf: bytes[j..<j+blockSize])
                        j += blockSize
                    }
                    return decode(capsuleData)
                }
            }
            i += 1
        }
        return nil
    }

    /// Capsule size in bytes (header + weights)
    static var capsuleSize: Int { 16 + GeneWeights.totalCount }

    // ════════════════════════════════════════════════════════════
    // HELPERS
    // ════════════════════════════════════════════════════════════

    private static func scaleZeroPoint(_ values: [Float]) -> (Float, Float) {
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 0
        let range = max(maxVal - minVal, 1e-8)
        let scale = range / 255.0
        let zero = minVal
        return (scale, zero)
    }

    private static func quantize(_ value: Float, scale: Float, zero: Float) -> UInt8 {
        let q = Int((value - zero) / scale)
        return UInt8(clamping: max(0, min(255, q)))
    }

    private static func dequantize(_ q: Int8, scale: Float, zero: Float) -> Float {
        Float(Int(q) + 128) * scale + zero  // map Int8 [-128,127] to UInt8 [0,255] range
    }

    private static func appendFloat(_ data: inout Data, _ value: Float) {
        var v = value
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func readFloat(_ bytes: [UInt8], offset: Int) -> Float {
        var value: Float = 0
        withUnsafeMutableBytes(of: &value) { buf in
            for i in 0..<4 { buf[i] = bytes[offset + i] }
        }
        return value
    }
}
