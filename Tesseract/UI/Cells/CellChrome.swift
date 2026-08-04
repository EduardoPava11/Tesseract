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
        let cfg = UIImage.SymbolConfiguration(pointSize: CGFloat(box) * 0.82, weight: .semibold)
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

/// A cell **action button** — flat opaque cell ground (no glass, no AA,
/// square corners) carrying an optional `CellIcon` + optional `CellText`
/// label. The caller wraps it in a `Button` so hit-rect == painted rect;
/// the touch floor is pinned in CELLS (11 = 44pt).
struct CellActionButton: View {
    enum Icon { case share, grid3x3, retake, none }
    var icon: Icon = .none
    var title: String? = nil
    /// Filled light ground + dark ink (the primary action). Otherwise a
    /// `ledGhost` ground + light ink.
    var prominent: Bool = false
    /// Expand to fill the row vs hug the icon.
    var fillWidth: Bool = true
    var heightCells: Int = TesseractLattice.touchFloorCells
    var minWidthCells: Int = TesseractLattice.touchFloorCells

    private var ground: SIMD3<UInt8> { prominent ? SIMD3(245, 245, 245) : Ink.ledGhost }
    private var fg: SIMD3<UInt8> { prominent ? SIMD3(20, 20, 20) : Ink.ink }

    var body: some View {
        HStack(spacing: Lattice.pt(3)) {
            iconView
            if let title { CellText(title, rows: TypeRows.body, ink: Color(srgb8: fg)) }
        }
        .padding(.horizontal, Lattice.pt(6))
        .frame(minHeight: Lattice.gif(heightCells))    // touch floor in CELLS
        .frame(maxWidth: fillWidth ? .infinity : nil)
        .frame(minWidth: Lattice.gif(minWidthCells))
        .background(Color(srgb8: ground))              // flat opaque ground
        .accessibilityHidden(true)                     // caller supplies the label
    }

    @ViewBuilder private var iconView: some View {
        switch icon {
        case .share:   CellIcon.share(ink: fg)
        case .grid3x3: CellIcon.grid3x3(ink: fg)
        case .retake:  CellIcon.retake(ink: fg)
        case .none:    EmptyView()
        }
    }
}

/// A cell **slider** — flat `ledGhost` baseline track with a single lit
/// knob cell; drag maps x → value quantised to `step`. Keeps
/// `accessibilityAdjustableAction` so VoiceOver can nudge it.
struct CellSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var tint: SIMD3<UInt8> = Ink.accent
    /// Track length in cells.
    var cols: Int = 56
    var heightCells: Int = TesseractLattice.touchFloorCells
    var cell: CGFloat = Lattice.pt(1)
    private let rows = 6

    private var span: Double { max(range.upperBound - range.lowerBound, 0.0001) }

    var body: some View {
        let frac = (value - range.lowerBound) / span
        let knob = max(0, min(cols - 1, Int((frac * Double(cols - 1)).rounded())))
        let ghost = Ink.ledGhost
        CellSprite(cols: cols, rows: rows, cellPt: cell) { c, r in
            if c == knob { return tint }                                   // the knob column
            return (r == rows / 2 - 1 || r == rows / 2) ? ghost : nil      // baseline track
        }
        .frame(width: cell * CGFloat(cols), height: cell * CGFloat(rows))
        .frame(minHeight: Lattice.gif(heightCells))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            let f = max(0, min(1, v.location.x / (cell * CGFloat(cols))))
            set(range.lowerBound + f * span)
        })
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(value))"))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: set(value + step)
            case .decrement: set(value - step)
            default: break
            }
        }
    }

    private func set(_ raw: Double) {
        let stepped = (raw / step).rounded() * step
        value = min(range.upperBound, max(range.lowerBound, stepped))
    }
}
