// CapturedFrame.swift
// Tesseract
//
// Raw data from GPU downsample: 64×64 RGB + depth.
// This is the INPUT to the quantization pipeline.
// Separate from QuantizedFrame (the OUTPUT).
//
// During capture: GPU fills these, CPU stores them.
// After capture: CPU processes ALL frames globally → GIF.

import Foundation

/// Raw frame data from GPU downsample + CPU block analysis.
struct CapturedFrame {
    /// Frame index in the 64-frame sequence (0..63)
    let index: Int

    /// Downsampled 64×64 RGB pixels [0,1]³ from GPU
    let rgb: [(Float, Float, Float)]

    /// Downsampled 64×64 depth values [0,1] (1=near, 0=far)
    let depths: [Float]

    /// Per-block Go evaluation from FULL camera resolution.
    /// 4096 entries (64×64 grid), each from an 18×18 block of source pixels.
    /// Computed during capture by CPU reading the CVPixelBuffer directly.
    /// Memory: 4096 × ~80 bytes = ~320 KB per frame.
    let blockEvals: [BlockEval]?

    /// Capture timestamp
    let timestamp: TimeInterval

    /// Width and height are always 64
    static let size = 64
    static let pixelCount = size * size  // 4096
}
