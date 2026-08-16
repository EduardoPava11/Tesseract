// CubeStore.swift
// Tesseract
//
// ★ CR1 — RETENTION (docs/model-placement.md §2).
//
// Daniel, 2026-08-14: "we should not try to put any big metadata into
// the GIF — the data should live in the app, as the user should be
// able to re-edit to make new GIFs."
//
// THE DEFECT THIS CLOSES. `QuantizedFrame` carries exactly what an
// edit needs — rawRGB and depths per frame — but those frames lived in
// a local array inside the capture closure and were released when it
// returned; `GIFLibrary.archive` kept only the encoded GIF. Within
// milliseconds of being made, the only copy of the editable data was
// freed. Every downstream feature (reweave, dials, one-capture-many-
// GIFs) was blocked on this and on nothing else.
//
// THE FORMAT. 8-bit sRGB + Float32 depth per voxel:
//
//   header  "TSRCUBE1" + frameCount:u32 + side:u32          16 B
//   frame   side² × 3 B sRGB, then side² × 4 B depth     28,672 B
//   total (64 × 64²)                                  1,835,024 B
//                                                       = 1.75 MiB
//
// WHY 8-BIT IS LOSSLESS HERE, despite the C3 prefilter making the
// in-memory value continuous: `DyadPipeline.process` quantizes with
// `srgb8(from:)` as its FIRST act on the cube (DyadPipeline.swift:317,
// banker's rounding), so the export path never sees more than 8 bits.
// Storing the quantized byte and reconstructing byte/255 re-quantizes
// to the same byte exactly — round-trip identity, not approximation.
// ★ The caveat, stated because it is invisible otherwise: the LIVE
// coarse-read paths (DyadPipeline.swift:954, :1070) pool the raw
// FLOATS before quantizing, so a re-weave driven through `Live` rather
// than the export path may differ by up to half a byte quantum. CR3 is
// therefore defined on the EXPORT path, which is the path that made
// the artifact being reproduced.
//
// Depth stays Float32: it is a signal in [0,1] with no quantizer
// downstream, so narrowing it would be an undeclared loss — exactly
// what the flow rule forbids.

import Foundation

enum CubeStore {

    static let magic = "TSRCUBE1"
    static let headerBytes = 16

    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        var dir = docs.appendingPathComponent("Cubes", isDirectory: true)
        let fm = FileManager.default
        let existed = fm.fileExists(atPath: dir.path)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // ★ NOT BACKED UP (2026-08-16). A cube is 1.75 MiB and one is
        // written per capture into Documents/, which iCloud backs up by
        // default. It is DERIVED data: it exists only so the editor can
        // re-weave, and losing it costs a re-edit, never a photograph.
        // Backing it up would put tens of megabytes of regenerable
        // intermediate into a user's iCloud quota for nothing.
        // Applied once, on creation, so an existing install is not
        // rewritten on every access.
        if !existed {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        return dir
    }

    /// ★ THE RETENTION CAP (2026-08-16), and it is the only defect in
    /// this file that COMPOUNDS WITH USE. Every capture wrote a cube and
    /// nothing ever removed one, so a user who shoots daily accumulates
    /// megabytes a week of data that, today, NOTHING READS: Reweave has
    /// no caller on any user path. The cap is the honest interim state.
    ///
    /// The number is DERIVED, not chosen (the no-naked-constants
    /// decree): the shelf shows a 3x3 grid, so nine captures are exactly
    /// what a user can reach and re-edit. Keeping cubes for GIFs that
    /// cannot be selected retains data no interface can spend. When the
    /// shelf pages past nine this constant follows it rather than being
    /// re-tuned.
    static let retainedCubes = 9

    /// Delete the oldest cubes beyond the cap, newest first by file
    /// creation date. Called after each save.
    static func trim(to limit: Int = retainedCubes) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let dated = urls.compactMap { u -> (URL, Date)? in
            guard let d = (try? u.resourceValues(forKeys: [.creationDateKey]))?
                .creationDate else { return nil }
            return (u, d)
        }.sorted { $0.1 > $1.1 }
        guard dated.count > limit else { return }
        for (url, _) in dated.dropFirst(limit) {
            try? fm.removeItem(at: url)
        }
    }

    /// The retained capture: what the editor re-weaves from.
    struct Cube: Sendable {
        let side: Int
        let rgb: [[(Float, Float, Float)]]   // [frame][pixel], sRGB [0,1]
        let depths: [[Float]]                // [frame][pixel], signal [0,1]

        var frameCount: Int { rgb.count }
    }

    /// The cube's URL for a GIF's URL — same stem, different directory,
    /// so the pair is keyed by the capture second the library already
    /// uses as its only metadata. No sidecar database, matching
    /// GIFLibrary's own contract.
    static func url(forGIF gifURL: URL) -> URL {
        directory.appendingPathComponent(
            gifURL.deletingPathExtension().lastPathComponent + ".cube")
    }

    // MARK: - Write

    static func encode(rgb: [[(Float, Float, Float)]],
                       depths: [[Float]], side: Int) -> Data? {
        guard !rgb.isEmpty, rgb.count == depths.count else { return nil }
        let px = side * side
        guard rgb.allSatisfy({ $0.count == px }),
              depths.allSatisfy({ $0.count == px }) else { return nil }

        var out = Data(capacity: headerBytes + rgb.count * px * 7)
        out.append(contentsOf: Array(magic.utf8))
        for v in [UInt32(rgb.count), UInt32(side)] {
            withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) }
        }
        for f in 0..<rgb.count {
            var bytes = [UInt8](); bytes.reserveCapacity(px * 3)
            for p in rgb[f] {
                bytes.append(to8(p.0)); bytes.append(to8(p.1)); bytes.append(to8(p.2))
            }
            out.append(contentsOf: bytes)
            for d in depths[f] {
                withUnsafeBytes(of: d.bitPattern.littleEndian) {
                    out.append(contentsOf: $0)
                }
            }
        }
        return out
    }

    /// The pipeline's own quantizer, verbatim (DyadPipeline.srgb8) —
    /// copied rather than called so the storage law does not drift if
    /// the pipeline's internals move. CubeStoreTests gates the parity.
    static func to8(_ c: Float) -> UInt8 {
        UInt8(min(255, max(0, (Double(c) * 255).rounded(.toNearestOrEven))))
    }

    @discardableResult
    static func save(rgb: [[(Float, Float, Float)]], depths: [[Float]],
                     side: Int, to url: URL) -> URL? {
        guard let data = encode(rgb: rgb, depths: depths, side: side) else { return nil }
        do {
            try data.write(to: url)
            trim()
            return url
        } catch {
            return nil
        }
    }

    /// Retain the capture beside its archived GIF.
    @discardableResult
    static func save(frames: [QuantizedFrame], forGIF gifURL: URL) -> URL? {
        let rgbs = frames.compactMap { $0.rawRGB }
        guard rgbs.count == frames.count else { return nil }
        return save(rgb: rgbs, depths: frames.map { $0.depths },
                    side: QuantizedFrame.size, to: url(forGIF: gifURL))
    }

    // MARK: - Read

    static func decode(_ data: Data) -> Cube? {
        guard data.count >= headerBytes,
              data.prefix(8).elementsEqual(magic.utf8) else { return nil }
        func u32(_ at: Int) -> UInt32 {
            var v: UInt32 = 0
            let lo = data.startIndex + at
            withUnsafeMutableBytes(of: &v) { dst in
                data.copyBytes(to: dst, from: lo..<(lo + 4))
            }
            return UInt32(littleEndian: v)
        }
        let frameCount = Int(u32(8)), side = Int(u32(12))
        guard frameCount > 0, side > 0 else { return nil }
        let px = side * side
        guard data.count == headerBytes + frameCount * px * 7 else { return nil }

        var rgb = [[(Float, Float, Float)]](); rgb.reserveCapacity(frameCount)
        var depths = [[Float]](); depths.reserveCapacity(frameCount)
        var off = data.startIndex + headerBytes
        for _ in 0..<frameCount {
            var frame = [(Float, Float, Float)](); frame.reserveCapacity(px)
            for p in 0..<px {
                let i = off + p * 3
                frame.append((Float(data[i]) / 255,
                              Float(data[i + 1]) / 255,
                              Float(data[i + 2]) / 255))
            }
            off += px * 3
            var ds = [Float](); ds.reserveCapacity(px)
            for p in 0..<px {
                var bits: UInt32 = 0
                let lo = off + p * 4
                withUnsafeMutableBytes(of: &bits) { dst in
                    data.copyBytes(to: dst, from: lo..<(lo + 4))
                }
                ds.append(Float(bitPattern: UInt32(littleEndian: bits)))
            }
            off += px * 4
            rgb.append(frame); depths.append(ds)
        }
        return Cube(side: side, rgb: rgb, depths: depths)
    }

    static func load(_ url: URL) -> Cube? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// The cube retained for an archived GIF, if it is still held.
    static func load(forGIF gifURL: URL) -> Cube? { load(url(forGIF: gifURL)) }

    static func exists(forGIF gifURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: url(forGIF: gifURL).path)
    }

    // MARK: - Housekeeping

    static func delete(forGIF gifURL: URL) {
        try? FileManager.default.removeItem(at: url(forGIF: gifURL))
    }

    /// Bytes held by retained cubes — the number the SET cover shows,
    /// so "keep all" is a visible cost rather than a silent one.
    static func totalBytes() -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.filter { $0.pathExtension == "cube" }.reduce(0) { acc, u in
            acc + ((try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    /// Bytes ONE capture costs, from the shape alone — the figure the
    /// storage line and the docs must agree on.
    static func bytesPerCapture(frames: Int = CameraConfig.totalFrames,
                                side: Int = CameraConfig.outputSize) -> Int {
        headerBytes + frames * side * side * 7
    }
}
