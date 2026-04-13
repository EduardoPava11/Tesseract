// GIFPlayerView.swift
// Tesseract
//
// Animated GIF playback for the result screen.
// 64×64 GIF displayed at 256×256 with nearest-neighbor scaling.
// UIViewRepresentable wrapping UIImageView for animation.

import SwiftUI
import ImageIO

/// Plays an animated GIF from raw Data at 20fps, looping forever.
/// Nearest-neighbor scaling preserves the pixel-art aesthetic.
struct GIFPlayerView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear

        // Nearest-neighbor: pixel-perfect scaling from 64→256
        imageView.layer.magnificationFilter = .nearest
        imageView.layer.minificationFilter = .nearest

        // Decode GIF frames from data
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return imageView
        }

        let frameCount = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        images.reserveCapacity(frameCount)

        for i in 0..<frameCount {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                images.append(UIImage(cgImage: cgImage))
            }
        }

        guard !images.isEmpty else { return imageView }

        imageView.animationImages = images
        imageView.animationDuration = Double(frameCount) / 20.0  // 20fps
        imageView.animationRepeatCount = 0  // infinite loop
        imageView.image = images.first  // show first frame immediately
        imageView.startAnimating()

        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        // Data doesn't change after creation
    }
}
