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

    // MARK: - Export

    /// Get the recorded quantized frames.
    func exportFrames() -> [QuantizedFrame] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }
}
