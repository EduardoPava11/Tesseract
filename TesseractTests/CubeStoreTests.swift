// CubeStoreTests.swift
// Tesseract
//
// ★ CR1 + CR3 (docs/model-placement.md §2).
//
// CR1 retains the cube so the capture can be re-woven. CR3 is what
// makes retention EVIDENCE rather than a second copy of an unknown:
//
//     reweave(cube, identityEdit) must reproduce the archived GIF's
//     INDEX FRAMES AND PALETTE TABLES, exactly
//
// A store that round-trips its own bytes proves only that it can
// write and read. CR3 proves the retained cube is the data the
// artifact actually came from — which is the whole claim.
//
// ★ SCOPED 2026-08-15 (Daniel's ruling), from "byte for byte" to
// "the picture". The old wording was never what this file checked,
// and it could not have been: the capture path calls
// `GIFMachine.makeGIF(frames:)`, which emits the PHASE F and SK GENES
// provenance sections guarded on having the frames; the re-weave path
// calls `finish(..., frames: [])`, so those sections are STRUCTURALLY
// ABSENT from a re-woven file. A re-woven identity has differed from
// its archived twin in comment bytes since the day reweave landed.
//
// The ruling makes CR3 a statement about the PICTURE rather than
// about the file, which is what the assertions below have always
// said. Frame-derived provenance may differ. Indices and tables may
// not. That is the honest gate, and it is the one that unblocks the
// CaptureTensor call-site swap, which was staged behind CR3 and
// nothing else.

import XCTest
@testable import Tesseract

final class CubeStoreTests: XCTestCase {

    private let side = QuantizedFrame.size
    private let frames = 8      // a short cube: the law is per-frame

    // MARK: - synthetic capture (deterministic, no camera)

    private func syntheticCube(seed: UInt64) -> (rgb: [[(Float, Float, Float)]],
                                                 depths: [[Float]]) {
        var state = seed
        func rnd() -> Float {
            state = state &* 6364136223846793005 &+ 1
            return Float((state >> 33) % 10_000) / 10_000
        }
        var rgb = [[(Float, Float, Float)]](), depths = [[Float]]()
        for f in 0..<frames {
            var frame = [(Float, Float, Float)](), ds = [Float]()
            for p in 0..<(side * side) {
                let x = Float(p % side) / Float(side)
                let y = Float(p / side) / Float(side)
                let t = Float(f) / Float(frames)
                // a moving subject on a ground, plus noise: enough
                // structure that the role law finds two phases
                let disc = (x - 0.5 - 0.1 * t) * (x - 0.5 - 0.1 * t)
                         + (y - 0.5) * (y - 0.5) < 0.05
                frame.append((disc ? 0.2 + 0.6 * rnd() : 0.05 * rnd(),
                              disc ? 0.5 * rnd() : 0.4 + 0.1 * rnd(),
                              disc ? 0.3 * rnd() : 0.7 + 0.2 * rnd()))
                ds.append(disc ? 0.85 + 0.1 * rnd() : 0.15 * rnd())
            }
            rgb.append(frame); depths.append(ds)
        }
        return (rgb, depths)
    }

    // MARK: - the format

    func testHeaderAndSizeMatchTheDeclaredArithmetic() {
        let c = syntheticCube(seed: 1)
        let data = CubeStore.encode(rgb: c.rgb, depths: c.depths, side: side)
        XCTAssertNotNil(data)
        XCTAssertEqual(data!.count,
                       CubeStore.headerBytes + frames * side * side * 7,
                       "16 B header + 7 B/voxel (3 sRGB + 4 depth)")
        XCTAssertTrue(data!.prefix(8).elementsEqual(CubeStore.magic.utf8))

        // The number quoted to Daniel and written in the docs.
        XCTAssertEqual(CubeStore.bytesPerCapture(frames: 64, side: 64), 1_835_024)
        XCTAssertEqual(Double(CubeStore.bytesPerCapture(frames: 64, side: 64))
                        / 1024 / 1024, 1.75, accuracy: 0.001)
    }

    func testRoundTripIsExactInTheQUANTIZEDDomain() {
        let c = syntheticCube(seed: 2)
        let data = CubeStore.encode(rgb: c.rgb, depths: c.depths, side: side)!
        let back = CubeStore.decode(data)!

        XCTAssertEqual(back.side, side)
        XCTAssertEqual(back.frameCount, frames)
        for f in 0..<frames {
            for p in 0..<(side * side) {
                // RGB: equal after the quantizer the export path applies
                // as its first act. This is the precise claim — not that
                // the float survives, but that the byte does.
                let o = c.rgb[f][p], r = back.rgb[f][p]
                XCTAssertEqual(CubeStore.to8(o.0), CubeStore.to8(r.0))
                XCTAssertEqual(CubeStore.to8(o.1), CubeStore.to8(r.1))
                XCTAssertEqual(CubeStore.to8(o.2), CubeStore.to8(r.2))
                // Depth: Float32 is stored whole, so it is bit-identical.
                XCTAssertEqual(c.depths[f][p], back.depths[f][p])
            }
        }
    }

    func testStoredByteIsIdempotentUnderRequantization() {
        // The property the 8-bit claim rests on: to8(byte/255) == byte,
        // for every byte. If this failed anywhere, CR3 would fail there.
        for b in 0...255 {
            XCTAssertEqual(CubeStore.to8(Float(b) / 255), UInt8(b))
        }
    }

    func testMalformedDataIsRejectedNotGuessed() {
        let c = syntheticCube(seed: 3)
        let good = CubeStore.encode(rgb: c.rgb, depths: c.depths, side: side)!
        XCTAssertNil(CubeStore.decode(Data()))
        XCTAssertNil(CubeStore.decode(good.prefix(CubeStore.headerBytes)))
        XCTAssertNil(CubeStore.decode(good.dropLast(1)))
        var wrongMagic = good
        wrongMagic[0] = 0x00
        XCTAssertNil(CubeStore.decode(wrongMagic))
    }

    // MARK: - ★ CR3 — the soundness gate

    func testIdentityReweaveReproducesTheIndicesAndTables() throws {
        let c = syntheticCube(seed: 7)

        // The artifact, as the capture would have made it.
        guard let original = DyadPipeline.process(rgb: c.rgb, depths: c.depths)
        else { return XCTFail("the synthetic capture must be exportable") }

        // Retain, then re-weave from what was retained.
        let data = CubeStore.encode(rgb: c.rgb, depths: c.depths, side: side)!
        let cube = CubeStore.decode(data)!
        guard let reweave = DyadPipeline.process(rgb: cube.rgb, depths: cube.depths)
        else { return XCTFail("the retained cube must be re-weavable") }

        XCTAssertEqual(reweave.indexFrames.count, original.indexFrames.count)
        for f in 0..<original.indexFrames.count {
            XCTAssertEqual(reweave.indexFrames[f], original.indexFrames[f],
                           "CR3: frame \(f) indices must be identical")
            XCTAssertEqual(reweave.tables[f], original.tables[f],
                           "CR3: frame \(f) palette must be identical")
        }
    }

    func testCR3FailsLoudlyIfTheCubeIsPerturbed() throws {
        // Guard against a vacuous CR3: if the gate passed for ANY cube,
        // it would prove nothing. One changed byte must break it.
        let c = syntheticCube(seed: 7)
        guard let original = DyadPipeline.process(rgb: c.rgb, depths: c.depths)
        else { return XCTFail("baseline") }

        var perturbed = c.rgb
        perturbed[0][0] = (1 - perturbed[0][0].0, perturbed[0][0].1, perturbed[0][0].2)
        guard let other = DyadPipeline.process(rgb: perturbed, depths: c.depths)
        else { return XCTFail("perturbed") }

        let sameIndices = zip(original.indexFrames, other.indexFrames)
            .allSatisfy { $0 == $1 }
        let sameTables = zip(original.tables, other.tables).allSatisfy { $0 == $1 }
        XCTAssertFalse(sameIndices && sameTables,
                       "a changed cube must change the artifact, or CR3 is vacuous")
    }

    // MARK: - the pair, and its cost

    func testCubeIsKeyedToItsGIFByStem() {
        let gif = URL(fileURLWithPath: "/tmp/Library/tesseract_1755000000.gif")
        let cube = CubeStore.url(forGIF: gif)
        XCTAssertEqual(cube.lastPathComponent, "tesseract_1755000000.cube")
        XCTAssertEqual(cube.deletingLastPathComponent().lastPathComponent, "Cubes")
    }

    func testDeletingAGIFReclaimsItsCube() throws {
        let data = Data("GIF89a-not-a-real-gif".utf8)
        guard let gifURL = GIFLibrary.archive(data) else {
            return XCTFail("archive")
        }
        let c = syntheticCube(seed: 11)
        XCTAssertNotNil(CubeStore.save(rgb: c.rgb, depths: c.depths,
                                       side: side,
                                       to: CubeStore.url(forGIF: gifURL)))
        XCTAssertTrue(CubeStore.exists(forGIF: gifURL))
        XCTAssertGreaterThan(CubeStore.totalBytes(), 0)

        GIFLibrary.delete(gifURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gifURL.path))
        XCTAssertFalse(CubeStore.exists(forGIF: gifURL),
                       "CR1: the pair is deleted together — no orphan cubes")
    }
}
