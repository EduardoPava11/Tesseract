// FrameBuffer.swift
// Tesseract
//
// Ring buffer for 64 quantized frames.
// When recording starts, we freeze the buffer and export.

import Foundation
import simd

/// A single quantized frame ready for GIF encoding.
struct QuantizedFrame {
    let index: Int                // 0..63
    let paletteIndices: [UInt8]   // 4096 entries (64×64)
    let depthZones: [UInt8]       // 4096 depth zone assignments (0..3)
    let measure: BirkhoffMeasure
    let timestamp: TimeInterval

    /// Width and height are always 64
    static let size = 64
    static let pixelCount = size * size  // 4096
}

/// Accumulates frames during recording, then produces the final 64-frame sequence.
final class FrameBuffer: @unchecked Sendable {

    private let lock = NSLock()
    private var frames: [QuantizedFrame] = []
    private var isRecording = false

    /// Maximum frames for one GIF
    private let capacity = CameraConfig.totalFrames  // 64

    // MARK: - Recording Control

    func startRecording() {
        lock.lock()
        frames.removeAll()
        frames.reserveCapacity(capacity)
        isRecording = true
        lock.unlock()
    }

    func stopRecording() {
        lock.lock()
        isRecording = false
        lock.unlock()
    }

    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames.count
    }

    var isFull: Bool {
        frameCount >= capacity
    }

    // MARK: - Add Frame

    /// Add a quantized frame during recording.
    /// Returns the current frame count, or nil if not recording / full.
    @discardableResult
    func addFrame(
        rgb: [(Float, Float, Float)],    // 4096 sRGB pixels [0,1]
        depth: [Float]?,                  // 4096 depth values (meters), optional
        timestamp: TimeInterval,
        seed: UInt32 = 42
    ) -> Int? {
        lock.lock()
        defer { lock.unlock() }

        guard isRecording, frames.count < capacity else { return nil }

        let frameIndex = frames.count

        // Quantize depth to 4 zones FIRST (needed for SNR cadence)
        let depthZones: [UInt8]
        if let depth = depth {
            depthZones = quantizeDepth(depth)
        } else {
            depthZones = [UInt8](repeating: 0, count: QuantizedFrame.pixelCount)
        }

        // Quantize with depth-driven SNR cadence:
        // Near pixels (face/signal) → stable epoch assignment
        // Far pixels (background/noise) → volatile epoch assignment
        let indices = TesseractPalette.quantizeFrame(
            frame: frameIndex,
            pixels: rgb,
            depthZones: depthZones,  // depth drives the temporal cadence
            seed: seed
        )

        let measure = BirkhoffMeasure(paletteIndices: indices)

        let frame = QuantizedFrame(
            index: frameIndex,
            paletteIndices: indices,
            depthZones: depthZones,
            measure: measure,
            timestamp: timestamp
        )

        frames.append(frame)

        if frames.count >= capacity {
            isRecording = false
        }

        return frames.count
    }

    // MARK: - Export

    /// Get the recorded frames (call after recording completes).
    func exportFrames() -> [QuantizedFrame] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    /// Aggregate Birkhoff measure across all frames
    func aggregateMeasure() -> BirkhoffMeasure? {
        let exported = exportFrames()
        guard !exported.isEmpty else { return nil }

        // Combine all frame histograms
        var totalCounts = [Int](repeating: 0, count: 256)
        for frame in exported {
            for idx in frame.paletteIndices {
                totalCounts[Int(idx)] += 1
            }
        }
        // Normalize to per-frame equivalent
        let perFrameCounts = totalCounts.map { $0 / max(1, exported.count) }
        return BirkhoffMeasure(counts: perFrameCounts)
    }

    // MARK: - Depth Quantization

    /// Quantize depth values to 4 zones: 0=near, 1=mid-near, 2=mid-far, 3=far
    private func quantizeDepth(_ depths: [Float]) -> [UInt8] {
        // Find range (ignore non-finite values)
        var minD: Float = .greatestFiniteMagnitude
        var maxD: Float = 0
        for d in depths where d.isFinite && d > 0 {
            minD = min(minD, d)
            maxD = max(maxD, d)
        }
        let range = max(maxD - minD, 0.001)

        return depths.map { d in
            guard d.isFinite && d > 0 else { return 0 }
            let normalized = (d - minD) / range
            return UInt8(min(3, max(0, Int(normalized * 4))))
        }
    }

    // MARK: - Depth Color Pairs (for future use)

    /// Extract dominant color pairs per depth zone for a frame.
    func extractColorPairs(frame: QuantizedFrame) -> [DepthZone] {
        var zoneIndices: [[UInt8]] = [[], [], [], []]

        for i in 0..<QuantizedFrame.pixelCount {
            let zone = Int(frame.depthZones[i])
            zoneIndices[zone].append(frame.paletteIndices[i])
        }

        return (0..<4).map { level in
            let indices = zoneIndices[level]
            let pair = ColorPair.extract(from: indices)
            return DepthZone(
                level: UInt8(level),
                pixelCount: indices.count,
                dominantPair: pair
            )
        }
    }
}
