// BayerCellReducer.swift
// Tesseract
//
// Pure CPU reducer: one ~12MP Bayer CVPixelBuffer → 64×64 per-cell,
// per-channel sufficient statistics (sum, sumSq). ~530 KB out per frame;
// the 25.5 MB CVPixelBuffer is dropped on return — no DNG bytes ever exist.
//
// Bayer-quad-aware: even block size + even crop origin means every cell
// covers whole 2×2 CFA quads → exactly (block/2)² samples per channel per
// cell. R, Gr, Gb, B stay separate (never demosaiced); Gr and Gb are only
// averaged much later for the display G.

import CoreVideo
import Foundation
import os.log

private let logger = Logger(subsystem: "com.tesseract.app", category: "BayerCellReducer")

/// 64×64 cells × 4 channels of raw-DN sufficient statistics for one frame.
struct FrameCellStats: Sendable {
    let slot: Int
    let meta: FrameMeta
    let hwTimestampNs: Int64
    /// 64*64 cells × 4 channels, channel order R=0, Gr=1, Gb=2, B=3;
    /// index = cell*4 + ch. Sum of raw DN.
    let sum: [UInt64]
    /// Same layout; sum of DN*DN (diagnostics / future empirical variance).
    let sumSq: [UInt64]
    /// (blockSize/2)², identical for all 4 channels of every cell.
    let countPerChannel: Int
    let blockSize: Int
    let cropX: Int
    let cropY: Int
}

enum BayerCellReducer {

    static let gridSide = 64

    /// CFA channel LUT for position index (y & 1) * 2 + (x & 1), in
    /// ABSOLUTE sensor coordinates. Channel order R=0, Gr=1, Gb=2, B=3.
    /// Returns nil for non-Bayer formats.
    static func cfaLUT(_ fourCC: OSType) -> [Int]? {
        switch fourCC {
        case kCVPixelFormatType_14Bayer_RGGB: return [0, 1, 2, 3]  // 'rgg4'
        case kCVPixelFormatType_14Bayer_BGGR: return [3, 2, 1, 0]  // 'bgg4'
        case kCVPixelFormatType_14Bayer_GRBG: return [1, 0, 3, 2]  // 'grb4'
        case kCVPixelFormatType_14Bayer_GBRG: return [2, 3, 0, 1]  // 'gbr4'
        default: return nil
        }
    }

    /// Reduce one raw Bayer frame to per-cell sufficient statistics.
    /// Consumes the payload's CVPixelBuffer; nothing from it escapes.
    /// Returns nil (logged) on format mismatch or geometry failure.
    static func reduce(_ payload: RawFramePayload) -> FrameCellStats? {
        let buffer = payload.buffer

        // Validate the buffer against the metadata captured with it —
        // catches mid-burst CFA changes (sixteen3 lesson).
        let actualFormat = CVPixelBufferGetPixelFormatType(buffer)
        guard actualFormat == payload.meta.cfa else {
            logger.error("reduce slot \(payload.slot): buffer fourCC \(fourCCString(actualFormat)) != meta \(fourCCString(payload.meta.cfa))")
            return nil
        }
        guard let lut = cfaLUT(actualFormat) else {
            logger.error("reduce slot \(payload.slot): non-Bayer format \(fourCCString(actualFormat))")
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            logger.error("reduce slot \(payload.slot): no base address")
            return nil
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        // bytesPerRow includes padding — never assume width (ROTAS lesson).
        let rowStride = CVPixelBufferGetBytesPerRow(buffer) / 2  // UInt16 units

        // Geometry from the ACTUAL buffer dims (feedback_no_crop_changes).
        let n = gridSide
        let side = min(width, height)                 // expect 3024
        let block = (side / n) & ~1                   // largest EVEN block: 3024 → 46
        guard block >= 2, block % 2 == 0 else {
            logger.error("reduce slot \(payload.slot): Bayer phase would break — side \(side), block \(block)")
            return nil
        }
        let crop = n * block                          // 2944
        let cropX = ((width - crop) / 2) & ~1         // even origin preserves CFA phase
        let cropY = ((height - crop) / 2) & ~1
        guard cropX >= 0, cropY >= 0,
              cropX + crop <= width, cropY + crop <= height else {
            logger.error("reduce slot \(payload.slot): crop out of bounds")
            return nil
        }

        let base = baseAddress.assumingMemoryBound(to: UInt16.self)

        var sum = [UInt64](repeating: 0, count: n * n * 4)
        var sumSq = [UInt64](repeating: 0, count: n * n * 4)

        // Cell-major loops for cache locality. DN ≤ 4095 (12-bit in 16-bit
        // container): per-cell sums ≤ 529·4095 ≈ 2.2e6, sumSq ≤ 529·4095² ≈
        // 8.9e9 — UInt64 is comfortably safe even for 14-bit inputs.
        sum.withUnsafeMutableBufferPointer { sPtr in
            sumSq.withUnsafeMutableBufferPointer { qPtr in
                for cy in 0..<n {
                    for cx in 0..<n {
                        var s0: UInt64 = 0, s1: UInt64 = 0, s2: UInt64 = 0, s3: UInt64 = 0
                        var q0: UInt64 = 0, q1: UInt64 = 0, q2: UInt64 = 0, q3: UInt64 = 0
                        let y0 = cropY + cy * block
                        let x0 = cropX + cx * block
                        for by in 0..<block {
                            let row = base + (y0 + by) * rowStride + x0
                            let rowParity = ((y0 + by) & 1) << 1
                            for bx in 0..<block {
                                let dn = UInt64(row[bx])
                                let ch = lut[rowParity | ((x0 + bx) & 1)]
                                switch ch {
                                case 0: s0 &+= dn; q0 &+= dn &* dn
                                case 1: s1 &+= dn; q1 &+= dn &* dn
                                case 2: s2 &+= dn; q2 &+= dn &* dn
                                default: s3 &+= dn; q3 &+= dn &* dn
                                }
                            }
                        }
                        let o = (cy * n + cx) * 4
                        sPtr[o] = s0; sPtr[o + 1] = s1; sPtr[o + 2] = s2; sPtr[o + 3] = s3
                        qPtr[o] = q0; qPtr[o + 1] = q1; qPtr[o + 2] = q2; qPtr[o + 3] = q3
                    }
                }
            }
        }

        return FrameCellStats(
            slot: payload.slot,
            meta: payload.meta,
            hwTimestampNs: payload.hwTimestampNs,
            sum: sum,
            sumSq: sumSq,
            countPerChannel: (block / 2) * (block / 2),
            blockSize: block,
            cropX: cropX,
            cropY: cropY
        )
    }
}

/// Render an OSType as its four-character string (diagnostics).
func fourCCString(_ code: OSType) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xFF),
        UInt8((code >> 16) & 0xFF),
        UInt8((code >> 8) & 0xFF),
        UInt8(code & 0xFF)
    ]
    return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", code)
}
