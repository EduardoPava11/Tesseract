// Axes.swift
// Tesseract
//
// Algebraic types for the 4 free orthogonal axes of the 4^4 tesseract.
// Matches Haskell spec: TesseractAxes.hs
//
// R, G, B are color axes (14 fine bins each, ditherable).
// T (Epoch) is the temporal axis (4 levels, NOT ditherable).
// The type system prevents mixing channels.
//
// 3D Color (R,G,B) ↔ 2D Space (x,y) + 1D Time (z)

import Foundation

// ════════════════════════════════════════════════════════════════
// § 1. ORTHOGONAL CHANNEL BINS (newtypes — can't mix R with G)
// ════════════════════════════════════════════════════════════════

/// Red channel bin (0..13). Haskell: `newtype RBin = RBin Int`
struct RBin: Hashable, Comparable {
    let value: Int
    static func < (lhs: RBin, rhs: RBin) -> Bool { lhs.value < rhs.value }
}

/// Green channel bin (0..13). Haskell: `newtype GBin = GBin Int`
struct GBin: Hashable, Comparable {
    let value: Int
    static func < (lhs: GBin, rhs: GBin) -> Bool { lhs.value < rhs.value }
}

/// Blue channel bin (0..13). Haskell: `newtype BBin = BBin Int`
struct BBin: Hashable, Comparable {
    let value: Int
    static func < (lhs: BBin, rhs: BBin) -> Bool { lhs.value < rhs.value }
}

/// Temporal epoch (0..3). NOT a color bin. NOT ditherable.
/// Haskell: `newtype Epoch = Epoch Int`
struct TessEpoch: Hashable, Comparable {
    let value: Int
    static func < (lhs: TessEpoch, rhs: TessEpoch) -> Bool { lhs.value < rhs.value }
}

/// Coarse tesseract level (0..3) — the 4-level quantization.
/// Haskell: `newtype TessLevel = TessLevel Int`
struct TessLevel: Hashable {
    let value: Int

    /// Cell center in [0,1]: (level + 0.5) / 4.0
    var center: Float {
        (Float(value) + 0.5) / 4.0
    }

    /// Canonical 8-bit value: round(center × 255) → {32, 96, 159, 223}
    var byte: UInt8 {
        UInt8(clamping: Int(round(center * 255)))
    }
}

// ════════════════════════════════════════════════════════════════
// § 2. BIN ↔ LEVEL MAPPING
// ════════════════════════════════════════════════════════════════

/// Maps a 14-bin index to a 4-level tesseract level.
/// 14 bins divide [0,1] into 14 equal slices.
/// 4 levels divide [0,1] into 4 equal slices.
/// Bins 0-3 → level 0, bins 4-6 → level 1, bins 7-10 → level 2, bins 11-13 → level 3.
func binToLevel(_ bin: Int) -> TessLevel {
    switch bin {
    case 0...3:   return TessLevel(value: 0)
    case 4...6:   return TessLevel(value: 1)
    case 7...10:  return TessLevel(value: 2)
    default:      return TessLevel(value: 3)  // 11-13
    }
}

/// Maps a continuous value [0,1] to a bin index (0..13).
func valueToBin(_ v: Float) -> Int {
    min(13, max(0, Int(v * 14.0)))
}

// ════════════════════════════════════════════════════════════════
// § 3. COMPOSED COLOR: Product of 3 orthogonal bins
//
// Haskell: data ComposedColor = CC !RBin !GBin !BBin
// ════════════════════════════════════════════════════════════════

/// A color composed from one bin per independent channel.
/// The channels are orthogonal: changing R doesn't affect G or B.
struct ComposedColor: Hashable {
    let r: RBin
    let g: GBin
    let b: BBin

    /// Coarse tesseract levels from the 3 bins
    var levels: (TessLevel, TessLevel, TessLevel) {
        (binToLevel(r.value), binToLevel(g.value), binToLevel(b.value))
    }

    /// Display color key (0..63) — identifies which of 64 sRGB colors this maps to
    var displayKey: Int {
        let (a, bv, c) = levels
        return a.value * 16 + bv.value * 4 + c.value
    }
}

// ════════════════════════════════════════════════════════════════
// § 4. ADDRESSED: Color grounded in space and time
//
// Ared + Egreen + Nblue == [(3,5), 2]
// 3D Color ↔ 2D Space + 1D Time
// ════════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════════
// § 5. TESS INDEX: The final palette entry (color × epoch)
//
// Haskell: data TessIndex = TessIndex TessLevel TessLevel TessLevel Epoch
// Swift equivalent: TesseractCoord (already exists, perfect bijection)
// ════════════════════════════════════════════════════════════════

/// Compose a palette index from composed color + epoch.
/// index = d×64 + a×16 + b×4 + c
func paletteIndex(color: ComposedColor, epoch: TessEpoch) -> UInt8 {
    let (a, bv, c) = color.levels
    return UInt8(epoch.value * 64 + a.value * 16 + bv.value * 4 + c.value)
}
