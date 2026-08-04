import SwiftUI
import UIKit
import simd

/// The content-layer LOOK contract (ported from SixFour): integer-scaled
/// cells, no interpolation, no anti-aliasing, no shading/gradient/opacity
/// on a cell — a cell is exactly one indexed sRGB8 color.
///
/// Scope (perf): the 64×64 GIF is a bitmap (`PixelImage`,
/// `.interpolation(.none)`), never 4096 Canvas fills. `PixelGrid` Canvas
/// drawing is for the 256-cell palette only.

/// A nearest-neighbour, integer-edge bitmap — GIF playback + live preview.
/// `.aspectRatio(1,.fit)` + `.frame` + `.fixedSize()` force a DEFINITE
/// square that cannot expand under `.position` (which offers the full
/// parent rect to a bare `.resizable()`).
struct PixelImage: View {
    let image: UIImage
    /// Integer-snapped square edge in points.
    let edge: CGFloat

    var body: some View {
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .frame(width: edge, height: edge)
            .fixedSize()
    }
}

/// Where row 0 / col 0 sits for `PixelGrid`.
enum PixelGridOrigin { case topLeft, bottomLeft }

/// A `cells × cells` grid of flat indexed cells, drawn as a single
/// `Canvas`. For the palette (≤ 256 cells) only — never the 64×64 GIF.
struct PixelGrid: View {
    let cells: Int
    let origin: PixelGridOrigin
    let colorAt: (_ row: Int, _ col: Int) -> SIMD3<UInt8>?

    var body: some View {
        Canvas { ctx, size in
            guard cells > 0 else { return }
            let cw = size.width / CGFloat(cells)
            let ch = size.height / CGFloat(cells)
            for r in 0 ..< cells {
                let screenRow = origin == .bottomLeft ? (cells - 1 - r) : r
                for c in 0 ..< cells {
                    guard let srgb = colorAt(r, c) else { continue }
                    let rect = CGRect(x: CGFloat(c) * cw, y: CGFloat(screenRow) * ch, width: cw, height: ch)
                    ctx.fillCell(rect, srgb8: srgb)
                }
            }
        }
    }
}

extension GraphicsContext {
    /// The one flat cell fill — solid, no interpolation, no stroke.
    @inline(__always)
    func fillCell(_ rect: CGRect, srgb8 c: SIMD3<UInt8>) {
        fill(Path(rect), with: .color(Color(srgb8: c)))
    }

    /// A border drawn as four OPAQUE filled edge rects — NOT `stroke`
    /// (edge-centred + anti-aliased) and NOT opacity.
    func fillBorder(_ rect: CGRect, width w: CGFloat, color: Color) {
        let p = GraphicsContext.Shading.color(color)
        fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: w)), with: p)
        fill(Path(CGRect(x: rect.minX, y: rect.maxY - w, width: rect.width, height: w)), with: p)
        fill(Path(CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height)), with: p)
        fill(Path(CGRect(x: rect.maxX - w, y: rect.minY, width: w, height: rect.height)), with: p)
    }
}

extension View {
    /// The chrome frame around a content grid: hard square, one opaque
    /// inset border, NO corner rounding (rounding clips the outermost
    /// indexed cells — an AA-on-content violation).
    func pixelFrame() -> some View {
        aspectRatio(1, contentMode: .fit)
            .border(Color(srgb8: Ink.frameStroke), width: 1)
    }
}
