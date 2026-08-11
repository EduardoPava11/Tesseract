// GIFMachineTests.swift
// Tesseract
//
// Swift mirrors of the ExportMethods spec (XM2–XM5): eligibility
// resolution, the persisted setting's round-trip, and the table
// scheme each method actually emits on the wire. No camera, no Metal.

import XCTest
@testable import Tesseract

final class GIFMachineTests: XCTestCase {

    private var savedMethod: String?
    private var savedBleed: Any?
    private var savedMirror: Any?

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        savedMethod = d.string(forKey: ExportSettings.methodKey)
        savedBleed = d.object(forKey: ExportSettings.bleedKey)
        savedMirror = d.object(forKey: ExportSettings.mirrorKey)
    }

    override func tearDown() {
        let d = UserDefaults.standard
        if let saved = savedMethod {
            d.set(saved, forKey: ExportSettings.methodKey)
        } else {
            d.removeObject(forKey: ExportSettings.methodKey)
        }
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

    // MARK: - XM2/XM3: eligibility resolution

    func testResolveChain() {
        let rich = frames(withRGB: true)
        let poor = frames(withRGB: false)
        XCTAssertEqual(GIFMachine.resolve(.dyad, frames: rich), .dyad)
        XCTAssertEqual(GIFMachine.resolve(.dyad, frames: poor), .refined,
                       "no rawRGB → dyad falls to refined")
        XCTAssertEqual(GIFMachine.resolve(.refined, frames: poor), .refined)
        for method in ExportMethod.allCases {
            XCTAssertEqual(GIFMachine.resolve(.tesseract, frames: rich), .tesseract)
            XCTAssertTrue(GIFMachine.eligible(GIFMachine.resolve(method, frames: poor),
                                              frames: poor),
                          "resolved method must always be eligible (XM2)")
        }
        XCTAssertEqual(GIFMachine.resolve(.dyad, frames: []), .refined,
                       "empty capture is not dyad-eligible")
    }

    // MARK: - XM5: the wire scheme per method

    func testDyadEmitsPerFrameTables() throws {
        let gif = try XCTUnwrap(GIFMachine.makeGIF(frames: frames(withRGB: true),
                                                   measure: nil, method: .dyad))
        XCTAssertEqual(firstDescriptorPackedByte(gif), 0x87,
                       "dyad carries a 256-entry LCT on every frame")
    }

    func testDyadWithoutRGBFallsToGlobalTable() throws {
        let gif = try XCTUnwrap(GIFMachine.makeGIF(frames: frames(withRGB: false),
                                                   measure: nil, method: .dyad))
        XCTAssertEqual(firstDescriptorPackedByte(gif), 0x00,
                       "resolved refined → single global table")
    }

    func testTesseractEmitsCanonicalGCT() throws {
        let gif = try XCTUnwrap(GIFMachine.makeGIF(frames: frames(withRGB: false),
                                                   measure: nil, method: .tesseract))
        let b = [UInt8](gif)
        XCTAssertEqual(Data(b[13..<(13 + 768)]), TesseractPalette.gifColorTable)
        XCTAssertEqual(firstDescriptorPackedByte(gif), 0x00)
    }

    func testRefinedEmitsGlobalTable() throws {
        let gif = try XCTUnwrap(GIFMachine.makeGIF(frames: frames(withRGB: true),
                                                   measure: nil, method: .refined))
        XCTAssertEqual(firstDescriptorPackedByte(gif), 0x00)
    }

    func testEmptyCaptureProducesNoGIF() {
        XCTAssertNil(GIFMachine.makeGIF(frames: [], measure: nil, method: .dyad))
    }

    // MARK: - XM4: the persisted setting

    func testSettingsRoundTrip() {
        for method in ExportMethod.allCases {
            for bleed in [true, false] {
                for mirror in [true, false] {
                    ExportSettings(method: method, bleed: bleed, mirror: mirror).save()
                    let loaded = ExportSettings.load()
                    XCTAssertEqual(loaded.method, method)
                    XCTAssertEqual(loaded.bleed, bleed)
                    XCTAssertEqual(loaded.mirror, mirror)
                }
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
            frames: capture, measure: nil,
            settings: ExportSettings(method: .dyad, bleed: true, mirror: false)))
        let flipped = try XCTUnwrap(GIFMachine.makeGIF(
            frames: capture, measure: nil,
            settings: ExportSettings(method: .dyad, bleed: true, mirror: true)))
        XCTAssertNotEqual(plain, flipped, "mirror must change the bytes")
        // Same palette work either way: identical GCT (frame 0's table).
        XCTAssertEqual(Data([UInt8](plain)[13..<781]), Data([UInt8](flipped)[13..<781]))
    }

    func testGarbageStoredValueParsesToDefault() {
        UserDefaults.standard.set("garbage", forKey: ExportSettings.methodKey)
        XCTAssertEqual(ExportSettings.load().method, .dyad)
        UserDefaults.standard.removeObject(forKey: ExportSettings.methodKey)
        XCTAssertEqual(ExportSettings.load().method, .dyad,
                       "missing value defaults to dyad")
    }

    // MARK: - Stats provenance: the GIF carries its own generator

    func testStatsTraceRebuildsTablesByteExact() throws {
        let out = try XCTUnwrap(DyadPipeline.process(frames: frames(withRGB: true)))
        let trace = GIFMachine.dyadTrace(
            out, settings: ExportSettings(method: .dyad, bleed: true, mirror: false))
        let rebuilt = try XCTUnwrap(GIFMachine.rebuildTables(fromTrace: trace))
        XCTAssertEqual(rebuilt, out.tables,
                       "9 numbers per frame must regenerate every palette byte")
    }

    func testGIFCarriesItsGenerator() throws {
        // The full circle: encode → walk the raw bytes → parse the
        // comment → re-solve the tables → byte-match the embedded LCTs.
        let gif = try XCTUnwrap(GIFMachine.makeGIF(
            frames: frames(withRGB: true), measure: nil,
            settings: ExportSettings(method: .dyad, bleed: true, mirror: false)))
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

        let trace = try XCTUnwrap(comments.first(where: { $0.contains("DYAD STATS v1") }),
                                  "the provenance comment must be in the stream")
        XCTAssertTrue(trace.contains("DYAD HARMONY"), "harmony rides the same comment")
        XCTAssertTrue(trace.contains("DYAD SETTINGS bleed=1 mirror=0"))
        let rebuilt = try XCTUnwrap(GIFMachine.rebuildTables(fromTrace: trace))
        XCTAssertEqual(rebuilt, embeddedLCTs,
                       "the GIF's own comment must regenerate its embedded tables")
    }

    // MARK: - Pill cycle

    func testPillCycleVisitsEveryMethod() {
        var seen: Set<ExportMethod> = []
        var m = ExportMethod.tesseract
        for _ in 0..<ExportMethod.allCases.count {
            seen.insert(m)
            m = m.next
        }
        XCTAssertEqual(seen, Set(ExportMethod.allCases))
        XCTAssertEqual(m, .tesseract, "cycle returns to its start")
    }
}
