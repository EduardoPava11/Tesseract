// RAWBurstPackage.swift
// Tesseract
//
// Four loose files per burst, ready for UIActivityViewController / AirDrop:
//   a.dng          - first Bayer RAW capture, full sensor (e.g. 8064x6048)
//   b.dng          - second Bayer RAW capture
//   preview.jpg    - embedded preview from capture A, decoded to JPEG
//   manifest.json  - burst metadata + the 4096x4096 center-crop region the
//                    tesseract-isp Haskell spec is expected to read from
//
// The DNGs themselves are NOT trimmed; the crop is advisory. This keeps
// iOS's DNG writer untouched (no custom TIFF surgery) while giving the
// downstream ISP a canonical 4096x4096 processing region.

import Foundation

struct RAWBurst: Sendable, Equatable {
    let packageDirectory: URL
    let dngA: URL
    let dngB: URL
    let preview: URL?
    let manifest: URL
    let deltaMs: Double
    let sensorWidth: Int
    let sensorHeight: Int

    var shareItems: [URL] {
        var xs: [URL] = [dngA, dngB]
        if let p = preview { xs.append(p) }
        xs.append(manifest)
        return xs
    }
}

enum RAWBurstPackage {

    static let cropSide: Int = 4096

    static func assemble(a: RAWPhoto,
                         b: RAWPhoto,
                         deltaMs: Double,
                         startTime: Date) throws -> RAWBurst {
        let fm = FileManager.default
        let stamp = isoStamp(startTime)
        let root  = fm.temporaryDirectory.appendingPathComponent("tesseractburst-\(stamp)",
                                                                 isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let dngA = root.appendingPathComponent("a.dng")
        let dngB = root.appendingPathComponent("b.dng")
        try a.dngData.write(to: dngA, options: .atomic)
        try b.dngData.write(to: dngB, options: .atomic)

        var previewURL: URL? = nil
        if let jpeg = a.previewJPEG {
            let u = root.appendingPathComponent("preview.jpg")
            try jpeg.write(to: u, options: .atomic)
            previewURL = u
        }

        let w = max(a.sensorWidth, b.sensorWidth)
        let h = max(a.sensorHeight, b.sensorHeight)
        let manifestURL = root.appendingPathComponent("manifest.json")
        let manifest = buildManifest(a: a, b: b, deltaMs: deltaMs,
                                     sensorWidth: w, sensorHeight: h)
        let jsonData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try jsonData.write(to: manifestURL, options: .atomic)

        return RAWBurst(
            packageDirectory: root,
            dngA: dngA,
            dngB: dngB,
            preview: previewURL,
            manifest: manifestURL,
            deltaMs: deltaMs,
            sensorWidth: w,
            sensorHeight: h
        )
    }

    private static func buildManifest(a: RAWPhoto,
                                      b: RAWPhoto,
                                      deltaMs: Double,
                                      sensorWidth w: Int,
                                      sensorHeight h: Int) -> [String: Any] {
        let cropX = max(0, (w - cropSide) / 2)
        let cropY = max(0, (h - cropSide) / 2)
        return [
            "format":   "tesseract-burst",
            "version":  "0.1.0",
            "deltaMs":  deltaMs,
            "crop": [
                "x":      cropX,
                "y":      cropY,
                "width":  cropSide,
                "height": cropSide,
                "note":   "center 4096x4096 of the full-sensor DNG; spec-ingest domain"
            ],
            "sensor": [
                "width":  w,
                "height": h
            ],
            "captures": [
                serialize(a),
                serialize(b)
            ]
        ]
    }

    private static func serialize(_ p: RAWPhoto) -> [String: Any] {
        var dict: [String: Any] = [
            "label":            p.label,
            "timestamp":        isoStamp(p.timestamp),
            "timestampEpochMs": Int(p.timestamp.timeIntervalSince1970 * 1000),
            "sensorWidth":      p.sensorWidth,
            "sensorHeight":     p.sensorHeight,
            "exposureSec":      p.exposureSeconds,
            "iso":              p.isoSpeed,
            "fNumber":          p.apertureFNumber,
            "focalLengthMm":    p.focalLengthMm,
            "dngBytes":         p.dngData.count
        ]
        if let m = p.lensModel { dict["lensModel"] = m }
        if !p.rawMetadata.isEmpty {
            dict["rawMetadata"] = p.rawMetadata
        }
        return dict
    }

    private static func isoStamp(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d).replacingOccurrences(of: ":", with: "-")
    }
}
