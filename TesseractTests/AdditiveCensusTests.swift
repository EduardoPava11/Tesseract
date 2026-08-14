// AdditiveCensusTests.swift
// Tesseract
//
// Parity teeth for the ADDITIVE LADDER's measurement half
// (spec/output/AdditiveLadder.hs AD1–AD12 is authoritative). Pure
// logic: runs on the simulator, no camera.

import XCTest
@testable import Tesseract

final class AdditiveCensusTests: XCTestCase {

    private let side = 64
    private let frames = 4          // one rung-16 block depth

    // MARK: - AD1/AD2: the partition and the composition identity

    func testStrataPartitionTheEightBits() {
        let widths = AdditiveCensus.strata.map { $0.width }
        let lows = AdditiveCensus.strata.map { $0.low }
        XCTAssertEqual(widths, [1, 1, 3, 3], "AD1: widths 1+1+3+3")
        XCTAssertEqual(lows, [7, 6, 3, 0], "AD1: descending, adjacent")
        XCTAssertEqual(widths.reduce(0, +), 8, "AD1: exhausts the index")
        for (a, b) in zip(AdditiveCensus.strata, AdditiveCensus.strata.dropFirst()) {
            XCTAssertEqual(a.low, b.low + b.width, "AD1: no gap, no overlap")
        }
    }

    func testCompositionIsABijectionOn256() {
        var seen = Set<UInt8>()
        for i in 0...255 {
            let v = UInt8(i)
            let composed = AdditiveCensus.compose(
                role: AdditiveCensus.field(AdditiveCensus.role, v),
                r16: AdditiveCensus.field(AdditiveCensus.r16, v),
                r32: AdditiveCensus.field(AdditiveCensus.r32, v),
                r64: AdditiveCensus.field(AdditiveCensus.r64, v))
            XCTAssertEqual(composed, v, "AD2: index = Σ strata")
            seen.insert(composed)
        }
        XCTAssertEqual(seen.count, 256, "AD2: bijection")
    }

    func testPrefixLawOperator() {
        for i in 0...255 {
            let v = UInt8(i)
            XCTAssertEqual(AdditiveCensus.classAt(AdditiveCensus.r64, v), i)
            XCTAssertEqual(AdditiveCensus.classAt(AdditiveCensus.r32, v), i / 8)
            XCTAssertEqual(AdditiveCensus.classAt(AdditiveCensus.role, v),
                           i >= 128 ? 1 : 0, "AD5: role class is the σ bit")
        }
    }

    // MARK: - AD3/AD4: the seating and the 1024 invariant

    func testTheThousandTwentyFourInvariant() {
        for st in [AdditiveCensus.r16, AdditiveCensus.r32, AdditiveCensus.r64] {
            let voxels = st.rung * st.rung * st.rung
            XCTAssertEqual(voxels % st.level, 0)
            XCTAssertEqual(voxels / st.level, 1024,
                           "AD4: balanced occupancy is 1024 at every rung")
        }
        XCTAssertEqual(AdditiveCensus.strata.map { $0.blockSide }, [1, 4, 2, 1],
                       "role is per-voxel (AD7); rungs 16/32/64 are 4/2/1")
    }

    // MARK: - AD11: conformance

    /// A cube built BY the law: each stratum's field drawn once per
    /// block of its own rung.
    private func lawfulCube(seed: UInt64) -> [[UInt8]] {
        var state = seed
        func rnd() -> Int { state = state &* 6364136223846793005 &+ 1; return Int(state >> 33) }
        var fields: [Int: [Int]] = [:]
        for st in AdditiveCensus.strata {
            let k = st.blockSide
            let n = side / k, nT = frames / k
            fields[st.low] = (0..<(max(1, nT) * n * n)).map { _ in rnd() % (1 << st.width) }
        }
        func pick(_ st: AdditiveCensus.Stratum, _ t: Int, _ y: Int, _ x: Int) -> Int {
            let k = st.blockSide, n = side / k
            let b = ((t / k) * n + (y / k)) * n + (x / k)
            let arr = fields[st.low]!
            return arr[b % arr.count]
        }
        return (0..<frames).map { t in
            (0..<(side * side)).map { p in
                let y = p / side, x = p % side
                return AdditiveCensus.compose(
                    role: pick(AdditiveCensus.role, t, y, x),
                    r16: pick(AdditiveCensus.r16, t, y, x),
                    r32: pick(AdditiveCensus.r32, t, y, x),
                    r64: pick(AdditiveCensus.r64, t, y, x))
            }
        }
    }

    private func freeCube(seed: UInt64) -> [[UInt8]] {
        var state = seed
        func rnd() -> UInt8 { state = state &* 6364136223846793005 &+ 1; return UInt8((state >> 33) % 256) }
        return (0..<frames).map { _ in (0..<(side * side)).map { _ in rnd() } }
    }

    func testLawfulCubeConformsAtEveryStratum() {
        let cube = lawfulCube(seed: 3)
        for st in AdditiveCensus.strata {
            XCTAssertEqual(
                AdditiveCensus.conformance(st, indexFrames: cube, side: side), 1.0,
                accuracy: 1e-12,
                "AD11: a cube built by the law conforms at \(st.name)")
        }
    }

    func testFreeCubeConformsOnlyAtTheLeaf() {
        let cube = freeCube(seed: 5)
        XCTAssertEqual(
            AdditiveCensus.conformance(AdditiveCensus.r64, indexFrames: cube, side: side),
            1.0, accuracy: 1e-12, "AD11: single-voxel blocks conform for free")
        XCTAssertLessThan(
            AdditiveCensus.conformance(AdditiveCensus.r16, indexFrames: cube, side: side),
            0.01, "AD11: free assignment does not conform at rung 16")
        XCTAssertLessThan(
            AdditiveCensus.conformance(AdditiveCensus.r32, indexFrames: cube, side: side),
            0.01, "AD11: nor at rung 32 — this gap is the S8 port's price")
    }

    // MARK: - AD12: census bounds and monotonicity

    func testCensusCountsAreBoundedAndMonotone() {
        for cube in [lawfulCube(seed: 3), freeCube(seed: 5)] {
            var last = 0
            for st in AdditiveCensus.strata {
                let used = AdditiveCensus.classesUsed(st, indexFrames: cube)
                XCTAssertLessThanOrEqual(used, st.level, "AD12: bounded by the level")
                XCTAssertGreaterThanOrEqual(used, last, "AD12: monotone by stratum")
                last = used
            }
        }
    }

    func testOccupancyTargetIsTheVoxelShare() {
        let cube = freeCube(seed: 5)
        let voxels = frames * side * side
        for st in AdditiveCensus.strata {
            let occ = AdditiveCensus.occupancy(st, indexFrames: cube)
            XCTAssertEqual(occ.target, voxels / st.level)
            XCTAssertLessThanOrEqual(occ.min, occ.max)
        }
    }

    // MARK: - the trace's shape

    func testTraceIsOneHeaderAndOneLinePerStratum() {
        let cube = freeCube(seed: 5)
        let lines = AdditiveCensus.trace(indexFrames: cube, side: side)
            .split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 1 + AdditiveCensus.strata.count)
        XCTAssertTrue(lines[0].hasPrefix("ADDITIVE CENSUS v1 "))
        for (line, st) in zip(lines.dropFirst(), AdditiveCensus.strata) {
            let cols = line.split(separator: " ")
            XCTAssertEqual(cols.count, 8, "name block conf used level min max target")
            XCTAssertEqual(String(cols[0]), st.name)
            XCTAssertNotNil(Double(cols[2]), "conformance round-trips")
        }
    }
}
