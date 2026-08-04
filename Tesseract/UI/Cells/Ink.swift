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

    /// Channel tints for the R/G/B/D preview thumbs (opaque, no `.opacity`).
    static let chanR = SIMD3<UInt8>(220, 60, 60)
    static let chanG = SIMD3<UInt8>(70, 200, 90)
    static let chanB = SIMD3<UInt8>(96, 165, 250)
    static let chanD = SIMD3<UInt8>(235, 235, 235)

    /// Gene tints in dual explore (was `.cyan` / `.orange` with opacity).
    static let tintA = SIMD3<UInt8>(80, 200, 220)
    static let tintB = SIMD3<UInt8>(235, 160, 60)

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
enum TypeRows {
    /// Sparkline/stat labels, badges (was 7-8pt system).
    static let micro = 3
    /// Hints, phase text, captions, metric values (was 9-10pt / .caption).
    static let label = 5
    /// Button labels, headers (was .headline/.title3/.body).
    static let body = 7
    /// Counters, percentages (was .title2).
    static let counter = 9
    /// The idle wordmark (was .title).
    static let display = 13
}
