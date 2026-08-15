import SwiftUI
import UIKit

/// Text rendered as lattice CELLS (ported from SixFour) — the chrome's
/// pixel-font primitive. Rasterize-and-snap: a monospaced string is drawn
/// into a bitmap at cell resolution with anti-aliasing OFF, then
/// nearest-neighbour upscaled so each source pixel becomes one hard cell.
///
/// `rows` names a `TypeRows` register (micro/label/body/counter/display).
/// Accessibility: the cells are decorative; the real string is exposed via
/// `accessibilityLabel`, so VoiceOver reads the text, not "rectangles".
struct CellText: View {
    let text: String
    /// Glyph height in cells (= source bitmap pixel rows).
    var rows: Int = TypeRows.body
    /// Point size of one cell — the 2pt half-atom.
    var cell: CGFloat = Lattice.pt(1)
    var ink: Color = Color(srgb8: Ink.ink)

    init(_ text: String, rows: Int = TypeRows.body,
         cell: CGFloat = Lattice.pt(1), ink: Color = Color(srgb8: Ink.ink)) {
        self.text = text
        self.rows = rows
        self.cell = cell
        self.ink = ink
    }

    var body: some View {
        if let mask = Self.snap(text, rows: rows) {
            Image(uiImage: mask)
                .renderingMode(.template)
                .resizable()
                .interpolation(.none)
                .frame(width: mask.size.width * cell, height: mask.size.height * cell)
                .foregroundStyle(ink)
                .accessibilityLabel(Text(text))
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    /// Cache of rasterised masks keyed by `rows|text` — the raster is a
    /// pure function of both, so dozens of chrome labels re-render free.
    private static let cache = NSCache<NSString, UIImage>()

    /// Rasterise `text` to a 1-bit alpha mask, one pixel per cell, AA off.
    static func snap(_ text: String, rows: Int) -> UIImage? {
        guard !text.isEmpty, rows > 0 else { return nil }
        let key = "\(rows)|\(text)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let font = UIFont.monospacedSystemFont(ofSize: CGFloat(rows), weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let ns = text as NSString
        let w = max(1, Int(ns.size(withAttributes: attrs).width.rounded(.up)))
        let h = rows

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))   // transparent paper
        ctx.setShouldAntialias(false)                         // hard cells, no fringe
        ctx.setAllowsAntialiasing(false)

        UIGraphicsPushContext(ctx)
        // CoreGraphics origin is bottom-left; flip so text reads top-down.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ns.draw(at: .zero, withAttributes: attrs)             // white ink on clear
        UIGraphicsPopContext()

        let img = ctx.makeImage().map { UIImage(cgImage: $0) }
        if let img { cache.setObject(img, forKey: key) }
        return img
    }
}
