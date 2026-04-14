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
    let rawRGB: [(Float, Float, Float)]?  // 4096 sRGB pixels — nil in preview, populated during recording for CPU perfect pass
    let depths: [Float]           // 4096 continuous depth values [0,1]
    let measure: BirkhoffMeasure
    let subjectAnalysis: SubjectAnalysis?  // depth-based subject/background separation
    let anchorTrace: AnchorTrace?          // black/white distribution tail anchors
    let timestamp: TimeInterval

    /// Width and height are always 64
    static let size = 64
    static let pixelCount = size * size  // 4096
}

/// Accumulates frames during recording, then produces the final 64-frame sequence.
/// Stores CapturedFrames (raw RGB + depth) during capture.
/// After capture, PerfectQuantizer processes them globally → QuantizedFrames → GIF.
final class FrameBuffer: @unchecked Sendable {

    private let lock = NSLock()
    private var frames: [QuantizedFrame] = []
    private var capturedFrames: [CapturedFrame] = []
    private var isRecording = false

    /// Maximum frames for one GIF
    private let capacity = CameraConfig.totalFrames  // 64

    // MARK: - Recording Control

    func startRecording() {
        lock.lock()
        frames.removeAll()
        frames.reserveCapacity(capacity)
        capturedFrames.removeAll()
        capturedFrames.reserveCapacity(capacity)
        isRecording = true
        lock.unlock()
    }

    func stopRecording() {
        lock.lock()
        isRecording = false
        lock.unlock()
    }

    // MARK: - Captured Frame Storage (for capture-then-compute)

    /// Store a captured frame (raw RGB + depth) during recording.
    /// Returns current frame count, or nil if not recording / full.
    @discardableResult
    func addCapturedFrame(_ frame: CapturedFrame) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard isRecording, capturedFrames.count < capacity else { return nil }
        capturedFrames.append(frame)
        if capturedFrames.count >= capacity {
            isRecording = false
        }
        return capturedFrames.count
    }

    /// Export captured frames for global quantization.
    func exportCapturedFrames() -> [CapturedFrame] {
        lock.lock()
        defer { lock.unlock() }
        return capturedFrames
    }

    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        // Use captured frames count during recording (capture-then-compute)
        return max(capturedFrames.count, frames.count)
    }

    var isFull: Bool {
        frameCount >= capacity
    }

    // MARK: - Add Pre-Quantized Frame (from Metal)

    /// Add a frame that was already quantized by the Metal pipeline.
    /// Pass rawRGB during recording for the CPU perfect pass.
    /// Returns current frame count, or nil if not recording / full.
    @discardableResult
    func addQuantizedFrame(
        paletteIndices: [UInt8],
        rawRGB: [(Float, Float, Float)]? = nil,
        depth: [Float]?,
        timestamp: TimeInterval
    ) -> Int? {
        lock.lock()
        defer { lock.unlock() }

        guard isRecording, frames.count < capacity else { return nil }

        let frameIndex = frames.count

        let depthValues = depth ?? [Float](repeating: 0.5, count: QuantizedFrame.pixelCount)
        let measure = BirkhoffMeasure(paletteIndices: paletteIndices)

        let subject = PerfectQuantizer.analyzeSubject(depths: depthValues)
        let anchors = PerfectQuantizer.findAnchors(indices: paletteIndices)

        let frame = QuantizedFrame(
            index: frameIndex,
            paletteIndices: paletteIndices,
            rawRGB: rawRGB,
            depths: depthValues,
            measure: measure,
            subjectAnalysis: subject,
            anchorTrace: anchors,
            timestamp: timestamp
        )

        frames.append(frame)

        if frames.count >= capacity {
            isRecording = false
        }

        return frames.count
    }

    // MARK: - Add Frame (CPU path)

    /// Add a frame with CPU-side quantization (fallback when Metal unavailable).
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

        // Continuous depth drives σ: σ = σ_base × (2 - depth). No zones.
        let depthValues: [Float]? = depth

        let indices = TesseractPalette.quantizeFrame(
            frame: frameIndex,
            pixels: rgb,
            depths: depthValues,
            seed: seed
        )

        let measure = BirkhoffMeasure(paletteIndices: indices)
        let dv = depthValues ?? [Float](repeating: 0.5, count: QuantizedFrame.pixelCount)
        let subject = PerfectQuantizer.analyzeSubject(depths: dv)
        let anchors = PerfectQuantizer.findAnchors(indices: indices)

        let frame = QuantizedFrame(
            index: frameIndex,
            paletteIndices: indices,
            rawRGB: rgb,
            depths: dv,
            measure: measure,
            subjectAnalysis: subject,
            anchorTrace: anchors,
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
            // Bin continuous depth into 4 display zones for color pair analysis
            let d = frame.depths[i]
            let zone = min(3, max(0, Int((1.0 - d) * 4)))  // 1=near→zone0, 0=far→zone3
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
