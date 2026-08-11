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

extension View {
    /// The chrome frame around a content grid: hard square, one opaque
    /// inset border, NO corner rounding (rounding clips the outermost
    /// indexed cells — an AA-on-content violation).
    func pixelFrame() -> some View {
        aspectRatio(1, contentMode: .fit)
            .border(Color(srgb8: Ink.frameStroke), width: 1)
    }
}
