// CapturedFrame.swift
// Tesseract
//
// Raw data from GPU downsample: outputSize² RGB + depth.
// Universal 768 crop → integer step at 64, 128, 256.
// This is the INPUT to the quantization pipeline.

import Foundation

/// Raw frame data from GPU downsample + CPU block analysis.
struct CapturedFrame {
    /// Frame index in the 64-frame sequence (0..63)
    let index: Int

    /// Downsampled outputSize² RGB pixels [0,1]³ from GPU
    /// Each pixel represents a step×step block from the 768×768 crop.
    /// At 64×64: step=12, each pixel = 12×12 = 144 source samples.
    let rgb: [(Float, Float, Float)]

    /// Downsampled outputSize² depth values [0,1] (1=near, 0=far)
    let depths: [Float]

    /// Per-block Go evaluation from FULL camera resolution.
    /// outputSize² entries, each from a step×step block of source pixels.

    /// Capture timestamp
    let timestamp: TimeInterval

    /// Output dimensions from CameraConfig
    static var size: Int { CameraConfig.outputSize }
    static var pixelCount: Int { size * size }
}
