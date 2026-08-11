import SwiftUI
import simd

/// The opaque ink vocabulary — ALL chrome color in the app routes through
/// these tokens (ported from SixFour's S3 opaque-ink system). State and
/// hierarchy are expressed by ink CHOICE, never by alpha, materials, or
/// shadows: a cell is exactly one indexed sRGB8 color.
enum Ink {
    /// Primary control/label ink.
    static let ink = SIMD3<UInt8>(235, 235, 235)
    /// The opaque "off"/secondary ink — replaces every white-with-alpha dim.
    static let ledGhost = SIMD3<UInt8>(40, 40, 40)
    /// Busy / error / destructive.
    static let reject = SIMD3<UInt8>(220, 60, 60)
    /// Confirmed / detected / success.
    static let accept = SIMD3<UInt8>(70, 200, 90)
    /// Selection accent (borders of selected cells, slider knobs).
    static let accent = SIMD3<UInt8>(96, 165, 250)

    /// Channel tints (opaque, no `.opacity`) — now serving the Go
    /// board rendering in ProcessingStateView.
    static let chanR = SIMD3<UInt8>(220, 60, 60)
    static let chanG = SIMD3<UInt8>(70, 200, 90)
    static let chanB = SIMD3<UInt8>(96, 165, 250)


    /// The 1pt frame around content grids (pixelFrame): opaque, never alpha.
    static let frameStroke = ledGhost
}

extension Color {
    /// The single sRGB8 → `Color` conversion for the whole app. EXPLICIT
    /// `.sRGB` space so on-screen chrome matches the GIF's color table
    /// byte-for-byte. Replaces every inline `.white.opacity(…)`.
    init(srgb8 c: SIMD3<UInt8>) {
        self.init(.sRGB, red: Double(c.x) / 255, green: Double(c.y) / 255, blue: Double(c.z) / 255)
    }
}

/// The closed CellText size registry — glyph height in CELLS (2pt sub-atoms).
/// Every text site names a register; ad-hoc rows are a lint smell.
///
/// Upscaled 2026-08-10 (Daniel: "small pixel words… use up more space to
/// be legible"): every register grew; the pixel-font look is unchanged —
/// glyphs are still rasterized AA-off at cell resolution, just taller.
enum TypeRows {
    /// Sparkline/stat labels, badges.
    static let micro = 4      // 8 pt  (was 3 = 6 pt)
    /// Hints, phase text, captions, metric values.
    static let label = 7      // 14 pt (was 5 = 10 pt)
    /// Button labels, headers.
    static let body = 9       // 18 pt (was 7 = 14 pt)
    /// Counters, percentages.
    static let counter = 11   // 22 pt (was 9)
    /// The idle wordmark / cover titles.
    static let display = 16   // 32 pt (was 13)
}
