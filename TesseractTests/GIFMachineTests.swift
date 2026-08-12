// GIFMachineTests.swift
// Tesseract
//
// Swift mirrors of the ExportMethods spec (XM1–XM4): DYAD per-frame
// palettes are the only export law (Daniel's decree, 2026-08-12) —
// eligible captures emit one LCT per frame, ineligible captures
// emit NOTHING (honest refusal, no global-table fallback). Plus the
// persisted toggles and the provenance round-trip. No camera, no
// Metal.

import XCTest
@testable import Tesseract

final class GIFMachineTests: XCTestCase {

    private var savedBleed: Any?
    private var savedMirror: Any?

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        savedBleed = d.object(forKey: ExportSettings.bleedKey)
        savedMirror = d.object(forKey: ExportSettings.mirrorKey)
    }

    override func tearDown() {
        let d = UserDefaults.standard
        if let b = savedBleed as? Bool {
            d.set(b, forKey: ExportSettings.bleedKey)
        } else {
            d.removeObject(forKey: ExportSettings.bleedKey)
        }
        if let m = savedMirror as? Bool {
            d.set(m, forKey: ExportSettings.mirrorKey)
        } else {
            d.removeObject(forKey: ExportSettings.mirrorKey)
        }
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeFrame(index: Int, withRGB: Bool) -> QuantizedFrame {
        let n = QuantizedFrame.pixelCount
        let side = QuantizedFrame.size
        let c = Double(side - 1) / 2
        var rgb = [(Float, Float, Float)](repeating: (0.6, 0.45, 0.35), count: n)
        var depths = [Float](repeating: 0, count: n)
        for p in 0..<n {
            let x = Double(p % side), y = Double(p / side)
            if (x - c) * (x - c) + (y - c) * (y - c) <= 24 * 24 {
                depths[p] = 1
                rgb[p].0 += Float(p % 16) * 0.01
            }
        }
        let indices = (0..<n).map { UInt8($0 % 256) }
        return QuantizedFrame(
            index: index, paletteIndices: indices,
            rawRGB: withRGB ? rgb : nil, depths: depths,
            measure: BirkhoffMeasure(paletteIndices: indices),
            subjectAnalysis: nil, anchorTrace: nil,
            timestamp: Double(index) / 20.0)
    }

    private func frames(withRGB: Bool, count: Int = 4) -> [QuantizedFrame] {
        (0..<count).map { makeFrame(index: $0, withRGB: withRGB) }
    }

    private func defaultSettings(mirror: Bool = false) -> ExportSettings {
        ExportSettings(bleed: true, mirror: mirror)
    }

    /// Packed byte of the FIRST image descriptor in a GIF stream.
    private func firstDescriptorPackedByte(_ gif: Data) -> UInt8? {
        let b = [UInt8](gif)
        var pos = 13 + 768
        while pos < b.count {
            if b[pos] == 0x2C { return b[pos + 9] }
            guard b[pos] == 0x21 else { return nil }
            pos += 2
            while b[pos] != 0x00 { pos += 1 + Int(b[pos]) }
            pos += 1
        }
        return nil
    }

    // MARK: - XM2: honest refusal — DYAD or nothing

    func testEligibility() {
        XCTAssertTrue(GIFMachine.eligible(frames: frames(withRGB: true)))
        XCTAssertFalse(GIFMachine.eligible(frames: frames(withRGB: false)),
                       "no rawRGB → not eligible")
        XCTAssertFalse(GIFMachine.eligible(frames: []),
                       "empty capture is not eligible")
    }

    func testDyadEmitsPerFrameTables() throws {
        let export = try XCTUnwrap(GIFMachine.makeGIF(frames: frames(withRGB: true),
                                                      settings: defaultSettings()))
        XCTAssertEqual(firstDescriptorPackedByte(export.data), 0x87,
                       "every frame carries a 256-entry LCT")
        XCTAssertGreaterThan(export.measure.colorsUsed, 0,
                             "the measure describes the emitted cube")
    }

    func testIneligibleCaptureProducesNoGIF() {
        XCTAssertNil(GIFMachine.makeGIF(frames: frames(withRGB: false),
                                        settings: defaultSettings()),
                     "no rawRGB → honest nil, never a global-table downgrade")
        XCTAssertNil(GIFMachine.makeGIF(frames: [],
                                        settings: defaultSettings()))
    }

    // MARK: - The persisted toggles

    func testSettingsRoundTrip() {
        for bleed in [true, false] {
            for mirror in [true, false] {
                ExportSettings(bleed: bleed, mirror: mirror).save()
                let loaded = ExportSettings.load()
                XCTAssertEqual(loaded.bleed, bleed)
                XCTAssertEqual(loaded.mirror, mirror)
            }
        }
    }

    func testToggleDefaults() {
        UserDefaults.standard.removeObject(forKey: ExportSettings.bleedKey)
        UserDefaults.standard.removeObject(forKey: ExportSettings.mirrorKey)
        let loaded = ExportSettings.load()
        XCTAssertTrue(loaded.bleed, "bleed defaults on")
        XCTAssertFalse(loaded.mirror, "mirror defaults off")
    }

    // MARK: - The MIRROR toggle

    func testMirrorIsInvolutive() {
        let side = QuantizedFrame.size
        let indices = (0..<side * side).map { UInt8($0 % 251) }
        let once = GIFMachine.mirrored(indices, side: side)
        XCTAssertNotEqual(once, indices, "asymmetric content must change")
        XCTAssertEqual(GIFMachine.mirrored(once, side: side), indices,
                       "mirror ∘ mirror = id")
        // Row law: element (y, x) swaps with (y, side−1−x).
        XCTAssertEqual(once[0], indices[side - 1])
    }

    func testMirrorSettingChangesTheGIF() throws {
        let capture = frames(withRGB: true)
        let plain = try XCTUnwrap(GIFMachine.makeGIF(
            frames: capture,
            settings: ExportSettings(bleed: true, mirror: false))).data
        let flipped = try XCTUnwrap(GIFMachine.makeGIF(
            frames: capture,
            settings: ExportSettings(bleed: true, mirror: true))).data
        XCTAssertNotEqual(plain, flipped, "mirror must change the bytes")
        // Same palette work either way: identical GCT (frame 0's table).
        XCTAssertEqual(Data([UInt8](plain)[13..<781]), Data([UInt8](flipped)[13..<781]))
    }

    // MARK: - Stats provenance: the GIF carries its own generator

    func testStatsTraceRebuildsTablesByteExact() throws {
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames(withRGB: true)))
        let trace = GIFMachine.dyadTrace(out, settings: defaultSettings())
        let rebuilt = try XCTUnwrap(GIFMachine.rebuildTables(fromTrace: trace))
        XCTAssertEqual(rebuilt, out.tables,
                       "the stats numbers must regenerate every palette byte")
    }

    func testGIFCarriesItsGenerator() throws {
        // The full circle: encode → walk the raw bytes → parse the
        // comment → re-solve the tables → byte-match the embedded LCTs.
        let gif = try XCTUnwrap(GIFMachine.makeGIF(
            frames: frames(withRGB: true),
            settings: defaultSettings())).data
        let b = [UInt8](gif)

        var comments: [String] = []
        var embeddedLCTs: [Data] = []
        var pos = 13 + 768
        while pos < b.count && b[pos] != 0x3B {
            if b[pos] == 0x21 {
                let isComment = b[pos + 1] == 0xFE
                var payload = [UInt8]()
                pos += 2
                while b[pos] != 0x00 {
                    let n = Int(b[pos])
                    if isComment { payload.append(contentsOf: b[(pos + 1)...(pos + n)]) }
                    pos += 1 + n
                }
                pos += 1
                if isComment, let s = String(bytes: payload, encoding: .utf8) {
                    comments.append(s)
                }
            } else if b[pos] == 0x2C {
                XCTAssertEqual(b[pos + 9], 0x87)
                embeddedLCTs.append(Data(b[(pos + 10)..<(pos + 10 + 768)]))
                pos += 10 + 768 + 1
                while b[pos] != 0x00 { pos += 1 + Int(b[pos]) }
                pos += 1
            } else {
                XCTFail("unknown block 0x\(String(b[pos], radix: 16)) at \(pos)")
                return
            }
        }

        let trace = try XCTUnwrap(comments.first(where: { $0.contains("DYAD STATS v3") }),
                                  "the provenance comment must be in the stream (v3 = pair tree)")
        XCTAssertTrue(trace.contains("DYAD HARMONY"), "harmony rides the same comment")
        XCTAssertTrue(trace.contains("DYAD SETTINGS bleed=1 mirror=0"))
        XCTAssertTrue(trace.contains("RATE LEDGER v1"),
                      "the beauty meter rides the same comment (rate-ladder S0)")
        let rebuilt = try XCTUnwrap(GIFMachine.rebuildTables(fromTrace: trace))
        XCTAssertEqual(rebuilt, embeddedLCTs,
                       "the GIF's own comment must regenerate its embedded tables")
    }

    // MARK: - RATE LEDGER (rate-ladder redesign, step S0)

    /// The meter's ordering law (spec RateLadder RL5): an ordered
    /// cube costs the coder less than a noisy one — M(flat) > M(noise)
    /// through the encoder's OWN LZW.
    func testRateLedgerOrdersFlatAboveNoise() {
        let n = QuantizedFrame.pixelCount
        let flat = (0..<4).map { f in [UInt8](repeating: UInt8(f), count: n) }
        var seed: UInt64 = 0x2545F4914F6CDD1D
        let noise = (0..<4).map { _ in
            (0..<n).map { _ -> UInt8 in
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return UInt8(truncatingIfNeeded: seed)
            }
        }
        let flatCost = GIFEncoder.lzwCost(indexFrames: flat)
        let noiseCost = GIFEncoder.lzwCost(indexFrames: noise)
        XCTAssertLessThan(flatCost, noiseCost,
                          "order must compress; noise must not")
        // And the noise cube's K̂ sits near (or above) 8 bits/px while
        // the flat cube's is far below 1 — the meter separates them.
        let kFlat = 8 * Double(flatCost) / Double(4 * n)
        let kNoise = 8 * Double(noiseCost) / Double(4 * n)
        XCTAssertLessThan(kFlat, 1.0)
        XCTAssertGreaterThan(kNoise, 6.0)
    }
}
