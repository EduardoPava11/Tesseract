import SwiftUI
import UIKit
import simd

/// An SF Symbol rendered as lattice CELLS — the icon twin of `CellText`
/// (ported from SixFour). The symbol is rasterised into a `box×box` mask
/// with anti-aliasing OFF, then nearest-neighbour upscaled.
/// `accessibilityLabel` is supplied by the wrapping control.
struct CellSymbol: View {
    let systemName: String
    /// Cells per side (the symbol is fit inside this square).
    var box: Int = 12
    var cell: CGFloat = Lattice.pt(1)
    var ink: Color = Color(srgb8: Ink.ink)

    var body: some View {
        if let mask = Self.snap(systemName, box: box) {
            Image(uiImage: mask)
                .renderingMode(.template)
                .resizable()
                .interpolation(.none)
                .frame(width: CGFloat(box) * cell, height: CGFloat(box) * cell)
                .foregroundStyle(ink)
        } else {
            Color.clear.frame(width: CGFloat(box) * cell, height: CGFloat(box) * cell)
        }
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// Rasterise an SF Symbol to a `box×box` alpha mask, AA off. Memoised.
    static func snap(_ name: String, box: Int) -> UIImage? {
        guard box > 0 else { return nil }
        let key = "\(box)|\(name)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        // SF Symbols overshoot their point size; 0.82 em fits the
        // glyph inside the box raster without clipping (owned
        // raster heuristic — line pass 2026-08-12).
        let symbolEmFraction: CGFloat = 0.82
        let cfg = UIImage.SymbolConfiguration(pointSize: CGFloat(box) * symbolEmFraction, weight: .semibold)
        guard let sym = UIImage(systemName: name, withConfiguration: cfg)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: box, height: box, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: box, height: box))
        ctx.setShouldAntialias(false)
        ctx.setAllowsAntialiasing(false)
        ctx.interpolationQuality = .none

        // Fit the symbol's aspect inside the box, centred.
        let s = sym.size
        let k = min(CGFloat(box) / max(s.width, 1), CGFloat(box) / max(s.height, 1))
        let w = s.width * k, h = s.height * k
        let rect = CGRect(x: (CGFloat(box) - w) / 2, y: (CGFloat(box) - h) / 2, width: w, height: h)

        UIGraphicsPushContext(ctx)
        ctx.translateBy(x: 0, y: CGFloat(box))   // flip to top-down
        ctx.scaleBy(x: 1, y: -1)
        sym.draw(in: rect)
        UIGraphicsPopContext()

        let img = ctx.makeImage().map { UIImage(cgImage: $0) }
        if let img { cache.setObject(img, forKey: key) }
        return img
    }
}

/// A frame-faced action control: `ControlFrame` + icon and/or label,
/// sized to a GridRegion footprint. The caller wraps it in a `Button`
/// (hit rect == the region rect via `.contentShape`).
struct CellFrameButton: View {
    var icon: CellIcon? = nil
    var symbol: String? = nil
    var title: String? = nil
    /// Ordinal into `CellMechanics.controlStates`.
    var state: Int = 0
    let tick: Int
    var reduceMotion: Bool = false
    let cols: Int
    let rows: Int
    /// Content ink; the frame draws its own treatment ink.
    var ink: SIMD3<UInt8> = Ink.ink

    var body: some View {
        ZStack {
            ControlFrame(cols: cols, rows: rows, state: state,
                         tick: tick, reduceMotion: reduceMotion)
            HStack(spacing: Lattice.pt(2)) {
                if let icon { icon }
                if let symbol { CellSymbol(systemName: symbol, ink: Color(srgb8: ink)) }
                // Button labels read at the body register (2026-08-10
                // upscale): the label register is for captions, not
                // touch targets.
                if let title { CellText(title, rows: TypeRows.body, ink: Color(srgb8: ink)) }
            }
        }
        .frame(width: Lattice.gif(cols), height: Lattice.gif(rows))
        .contentShape(Rectangle())
        .accessibilityHidden(true)   // the wrapping Button carries the label
    }
}
