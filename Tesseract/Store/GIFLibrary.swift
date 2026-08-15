// GIFLibrary.swift
// Tesseract
//
// The on-device GIF archive (Daniel, 2026-08-10: "a section in the app
// to review old GIFs and to look at their color palettes"). Every
// successful capture export is archived to Documents/Library as the
// exact bytes that were encoded — the GIF is self-describing (per-frame
// LCTs + DYAD STATS/MIXTURE provenance comments), so the library needs
// no sidecar database: palette and provenance are read back from the
// file itself.

import Foundation
import ImageIO

enum GIFLibrary {

    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir
    }

    /// Archive an encoded GIF. Filename carries the capture second —
    /// the only metadata the library needs beyond the bytes themselves.
    @discardableResult
    static func archive(_ data: Data, date: Date = Date()) -> URL? {
        let name = "tesseract_\(Int(date.timeIntervalSince1970)).gif"
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// All archived GIFs, newest first (timestamp is in the filename —
    /// no file-attribute reads, so no required-reason API).
    static func list() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "gif" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// ★ CR1: a capture is a PAIR — the archived GIF and the retained
    /// cube it can be re-woven from (CubeStore, keyed by the same
    /// stem). Deleting one must delete the other, or the library grows
    /// orphan cubes the user has no way to see or reclaim.
    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        CubeStore.delete(forGIF: url)
    }

    /// The 256-entry global color table (for DYAD exports the GCT is
    /// frame 0's table by contract). 768 bytes, or nil if malformed.
    static func palette(of data: Data) -> Data? {
        guard data.count > 13 + 768,
              data.prefix(6).elementsEqual("GIF89a".utf8) else { return nil }
        let packed = data[data.startIndex + 10]
        guard packed & 0x80 != 0, packed & 0x07 == 7 else { return nil }
        let start = data.startIndex + 13
        return data.subdata(in: start..<(start + 768))
    }

    /// The "DYAD MIXTURE" provenance line (m* = crossover in meters,
    /// derived α, phase count) — the capture's role law, readable back.
    static func mixtureLine(of data: Data) -> String? {
        guard let range = data.range(of: Data("DYAD MIXTURE".utf8)) else { return nil }
        // Comment sub-blocks are ≤255 bytes; the line ends at newline or
        // block boundary — take a bounded slice and cut at the newline.
        let end = data.index(range.lowerBound,
                             offsetBy: min(200, data.distance(from: range.lowerBound,
                                                              to: data.endIndex)))
        let slice = data.subdata(in: range.lowerBound..<end)
        let text = String(decoding: slice, as: UTF8.self)
        return text.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    /// First frame as a still (tile thumbnails: nine playing GIFs at
    /// once would fight the 20 Hz chrome clock).
    static func thumbnail(of url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
