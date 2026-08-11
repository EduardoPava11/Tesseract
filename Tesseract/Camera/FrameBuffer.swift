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
    let paletteIndices: [UInt8]   // outputSize² entries
    let rawRGB: [(Float, Float, Float)]?  // outputSize² sRGB pixels — nil in preview, populated during recording for CPU perfect pass
    let depths: [Float]           // outputSize² continuous depth values [0,1]
    let measure: BirkhoffMeasure
    let subjectAnalysis: SubjectAnalysis?  // depth-based subject/background separation
    let anchorTrace: AnchorTrace?          // black/white distribution tail anchors
    let timestamp: TimeInterval

    /// Output dimensions from CameraConfig
    static var size: Int { CameraConfig.outputSize }
    static var pixelCount: Int { size * size }
}

/// Accumulates frames during recording, then produces the final 64-frame sequence.
/// Stores CapturedFrames (raw RGB + depth) during capture.
/// After capture, PerfectQuantizer processes them globally → QuantizedFrames → GIF.
final class FrameBuffer: @unchecked Sendable {

    private let lock = NSLock()
    private var capturedFrames: [CapturedFrame] = []
    private var isRecording = false

    /// Maximum frames for one GIF
    private var capacity: Int { CameraConfig.totalFrames }  // S×K=4096: 64, 32, or 16

    // MARK: - Recording Control

    func startRecording() {
        lock.lock()
        capturedFrames.removeAll()
        capturedFrames.reserveCapacity(capacity)
        isRecording = true
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
        return capturedFrames.count
    }

    var isFull: Bool {
        frameCount >= capacity
    }

    // MARK: - Export

}
