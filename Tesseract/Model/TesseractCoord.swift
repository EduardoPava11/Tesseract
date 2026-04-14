// TesseractCoord.swift
// Tesseract
//
// Port of Tesseract.hs — R1 ⊕ R3 = R4
// 4⁴ = 256. Perfect symmetry. No axis is special.

import simd

/// A point in the 4⁴ tesseract lattice.
/// (d, a, b, c) ∈ {0,1,2,3}⁴
///   d = temporal epoch (R1)
///   a = R channel      (R3.x)
///   b = G channel      (R3.y)
///   c = B channel      (R3.z)
struct TesseractCoord: Hashable, Equatable, CustomStringConvertible {
    let d: UInt8  // epoch [0..3]
    let a: UInt8  // R [0..3]
    let b: UInt8  // G [0..3]
    let c: UInt8  // B [0..3]

    // MARK: - Index ↔ Coord bijection

    /// Palette index: i = d×64 + a×16 + b×4 + c
    var index: UInt8 {
        d &* 64 &+ a &* 16 &+ b &* 4 &+ c
    }

    /// Inverse: index → coordinate via base-4 decomposition
    init(index i: UInt8) {
        let ii = Int(i)
        let (dv, r1) = ii.quotientAndRemainder(dividingBy: 64)
        let (av, r2) = r1.quotientAndRemainder(dividingBy: 16)
        let (bv, cv) = r2.quotientAndRemainder(dividingBy: 4)
        self.d = UInt8(dv)
        self.a = UInt8(av)
        self.b = UInt8(bv)
        self.c = UInt8(cv)
    }

    init(d: UInt8, a: UInt8, b: UInt8, c: UInt8) {
        self.d = d; self.a = a; self.b = b; self.c = c
    }

    // MARK: - Projection to sRGB (drop epoch)

    /// Display color: epoch is invisible, 4 entries share each sRGB.
    var sRGB: SIMD3<Float> {
        SIMD3(
            (Float(a) + 0.5) / 4.0,
            (Float(b) + 0.5) / 4.0,
            (Float(c) + 0.5) / 4.0
        )
    }

    /// sRGB as 8-bit (0-255) for GIF palette table.
    /// Canonical values: {32, 96, 159, 223} for levels {0, 1, 2, 3}.
    /// Uses round() to match the Haskell spec (not truncation).
    var sRGB8: (UInt8, UInt8, UInt8) {
        let c = sRGB
        return (
            UInt8(clamping: Int(round(c.x * 255))),
            UInt8(clamping: Int(round(c.y * 255))),
            UInt8(clamping: Int(round(c.z * 255)))
        )
    }

    // MARK: - Embed into continuous R4

    var r4: SIMD4<Float> {
        SIMD4(Float(d), Float(a), Float(b), Float(c))
    }

    // MARK: - Direct Sum: R1 ⊕ R3 = R4

    /// π₁: project onto R1 (temporal epoch)
    var epoch: Float { Float(d) }

    /// π₂: project onto R3 (sRGB color axes)
    var color: SIMD3<Float> { SIMD3(Float(a), Float(b), Float(c)) }

    /// inject₁: epoch → tesseract  (a=0, b=0, c=0)
    static func fromEpoch(_ d: UInt8) -> TesseractCoord {
        TesseractCoord(d: d, a: 0, b: 0, c: 0)
    }

    /// inject₂: color → tesseract  (d=0)
    static func fromColor(a: UInt8, b: UInt8, c: UInt8) -> TesseractCoord {
        TesseractCoord(d: 0, a: a, b: b, c: c)
    }

    // MARK: - Metric

    /// 4D Euclidean distance
    func distance(to other: TesseractCoord) -> Float {
        simd_distance(self.r4, other.r4)
    }

    // MARK: - Corners

    /// Black = (0,0,0,0) = index 0
    static let black = TesseractCoord(d: 0, a: 0, b: 0, c: 0)

    /// White = (3,3,3,3) = index 255
    static let white = TesseractCoord(d: 3, a: 3, b: 3, c: 3)

    // MARK: - All 256 lattice points

    static let all: [TesseractCoord] = {
        var coords: [TesseractCoord] = []
        coords.reserveCapacity(256)
        for d: UInt8 in 0...3 {
            for a: UInt8 in 0...3 {
                for b: UInt8 in 0...3 {
                    for c: UInt8 in 0...3 {
                        coords.append(TesseractCoord(d: d, a: a, b: b, c: c))
                    }
                }
            }
        }
        return coords
    }()

    // MARK: - Constants

    /// Tesseract diagonal: √(4 × 3²) = 6
    static let diagonal: Float = 6.0

    /// Cell volume: (1/4)⁴ = 1/256
    static let cellVolume: Float = 1.0 / 256.0

    // MARK: - CustomStringConvertible

    var description: String { "(\(d),\(a),\(b),\(c))" }
}

// MARK: - Quantization

extension TesseractCoord {
    /// Floor-based 4D quantization: (frame, sRGB) → nearest lattice point.
    /// Epoch from frame index (16 frames per epoch).
    /// Color channels by floor(channel × 4).
    static func quantize(frame: Int, r: Float, g: Float, b: Float) -> TesseractCoord {
        let d = UInt8(clamping: frame / 16)
        let a = UInt8(clamping: min(3, Int(r * 4)))
        let bv = UInt8(clamping: min(3, Int(g * 4)))
        let c = UInt8(clamping: min(3, Int(b * 4)))
        return TesseractCoord(d: d, a: a, b: bv, c: c)
    }

    /// Quantize with explicit epoch (for binomial cadence sampling)
    static func quantize(epoch: UInt8, r: Float, g: Float, b: Float) -> TesseractCoord {
        let a = UInt8(clamping: min(3, Int(r * 4)))
        let bv = UInt8(clamping: min(3, Int(g * 4)))
        let c = UInt8(clamping: min(3, Int(b * 4)))
        return TesseractCoord(d: epoch, a: a, b: bv, c: c)
    }
}
