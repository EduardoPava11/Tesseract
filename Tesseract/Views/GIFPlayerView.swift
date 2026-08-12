// GIFPlayerView.swift
// Tesseract
//
// Animated GIF playback for the result and library screens.
// The 256×256 px export displayed with nearest-neighbor scaling.
// UIViewRepresentable wrapping UIImageView for animation.
//
// UI/UX line pass 2026-08-12: updateUIView now reloads when `data`
// changes (the library detail player used to keep playing the FIRST
// selected GIF forever); Reduce Motion holds the first frame instead
// of looping; the frame rate derives from the encoder's own delay.

import SwiftUI
import ImageIO

/// Plays an animated GIF from raw Data at the export's 20 fps,
/// looping — or holds frame 0 under Reduce Motion.
/// Nearest-neighbor scaling preserves the pixel-art aesthetic.
struct GIFPlayerView: UIViewRepresentable {
    let data: Data
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The export's frame rate, from the encoder's own delay (5 cs).
    private static let fps = 100.0 / Double(GIFEncoder.frameDelayCentiseconds)

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear

        // Nearest-neighbor: pixel-perfect fat voxels.
        imageView.layer.magnificationFilter = .nearest
        imageView.layer.minificationFilter = .nearest

        load(data, into: imageView, context: context)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        // Reload when the GIF changes (library tile selection) or
        // the Reduce Motion setting flips.
        if context.coordinator.loadedData != data
            || context.coordinator.loadedReduceMotion != reduceMotion {
            load(data, into: uiView, context: context)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedData: Data?
        var loadedReduceMotion: Bool?
    }

    private func load(_ data: Data, into imageView: UIImageView, context: Context) {
        context.coordinator.loadedData = data
        context.coordinator.loadedReduceMotion = reduceMotion
        imageView.stopAnimating()
        imageView.animationImages = nil
        imageView.image = nil

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let frameCount = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        images.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                images.append(UIImage(cgImage: cgImage))
            }
        }
        guard !images.isEmpty else { return }

        imageView.image = images.first
        // Reduce Motion: the still first frame IS the surface.
        guard !reduceMotion else { return }
        imageView.animationImages = images
        imageView.animationDuration = Double(frameCount) / Self.fps
        imageView.animationRepeatCount = 0  // infinite loop
        imageView.startAnimating()
    }
}
