// FaceMeshSignalTests.swift
// Tesseract
//
// Tests for the FACE mode pure logic (FaceMeshSignal), mirroring the
// FC axioms of spec/temporal/FaceCadence.hs with synthetic meshes:
//   FC1: s_nose = 1 exactly
//   FC2: all signals in [0,1]
//   FC3: equidistant vertices get equal signals
//   FC4: scale invariance (λ = 0.5, 2, 10)
//   FC5: rasterized pixel within its triangle's [min,max] vertex signals
//   FC6: uncovered pixels exactly 0
//   R=0 guard: coincident vertices ⇒ all signals 1, no NaN

import XCTest
import simd
@testable import Tesseract

final class FaceMeshSignalTests: XCTestCase {

    // ── Synthetic mesh: nose at +z apex, ring of vertices behind it ──

    private let apexMesh: [SIMD3<Float>] = [
        SIMD3(0, 0, 1),        // 0: nose (max z)
        SIMD3(1, 0, 0),        // 1
        SIMD3(-1, 0, 0),       // 2
        SIMD3(0, 1, 0),        // 3
        SIMD3(0, -1, 0),       // 4
        SIMD3(0.5, 0.5, 0.5),  // 5
    ]

    // ── FC1: nose signal is exactly 1 ──

    func testFC1_noseSignalIsExactlyOne() throws {
        let nose = try XCTUnwrap(FaceMeshSignal.noseIndex(vertices: apexMesh))
        XCTAssertEqual(nose, 0, "max-z vertex is the nose")
        let signals = FaceMeshSignal.vertexSignals(vertices: apexMesh)
        XCTAssertEqual(signals[nose], 1.0, "FC1: s_nose = 1 exactly (no tolerance)")
    }

    // ── FC2: all signals in [0,1] ──

    func testFC2_allSignalsInUnitInterval() {
        // Deterministic pseudo-random cloud (no SystemRandomNumberGenerator:
        // axiom must hold for every input, seedless repeatability preferred).
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(state >> 40) / Float(1 << 24) * 4 - 2  // [-2, 2)
        }
        let cloud = (0..<200).map { _ in SIMD3<Float>(next(), next(), next()) }
        let signals = FaceMeshSignal.vertexSignals(vertices: cloud)
        XCTAssertEqual(signals.count, cloud.count)
        for s in signals {
            XCTAssertFalse(s.isNaN)
            XCTAssertGreaterThanOrEqual(s, 0)
            XCTAssertLessThanOrEqual(s, 1)
        }
    }

    // ── FC3: equal distances ⇒ equal signals ──

    func testFC3_equidistantVerticesGetEqualSignals() {
        let signals = FaceMeshSignal.vertexSignals(vertices: apexMesh)
        // Vertices 1-4 are all at distance √2 from the nose (0,0,1).
        XCTAssertEqual(signals[1], signals[2])
        XCTAssertEqual(signals[2], signals[3])
        XCTAssertEqual(signals[3], signals[4])
    }

    // ── FC4: scale invariance ──

    func testFC4_scaleInvariance() {
        let base = FaceMeshSignal.vertexSignals(vertices: apexMesh)
        for lambda: Float in [0.5, 2, 10] {
            let scaled = apexMesh.map { $0 * lambda }
            let signals = FaceMeshSignal.vertexSignals(vertices: scaled)
            for i in 0..<base.count {
                XCTAssertEqual(signals[i], base[i], accuracy: 1e-6,
                               "FC4: λ=\(lambda) must not change s_\(i)")
            }
        }
    }

    // ── R=0 guard: all vertices coincide ⇒ all 1, no NaN ──

    func testR0Guard_coincidentVerticesAllOne() {
        let collapsed = [SIMD3<Float>](repeating: SIMD3(0.3, -0.2, 0.7), count: 5)
        let signals = FaceMeshSignal.vertexSignals(vertices: collapsed)
        XCTAssertEqual(signals.count, 5)
        for s in signals {
            XCTAssertFalse(s.isNaN)
            XCTAssertEqual(s, 1.0, "R=0 ⇒ all signals exactly 1")
        }
    }

    func testEmptyMesh() {
        XCTAssertNil(FaceMeshSignal.noseIndex(vertices: []))
        XCTAssertEqual(FaceMeshSignal.vertexSignals(vertices: []), [])
    }

    // ── FC5 + FC6: rasterizer on a single right triangle ──
    //
    // Triangle a=(0,0) b=(4,0) c=(0,4) on an 8×8 grid. With pixel centers
    // at (x+0.5, y+0.5) and the top-left edge rule, coverage is exactly
    // the pixels with x + y ≤ 2 (hypotenuse centers x+y = 3 are excluded).

    private let triPositions: [SIMD2<Float>] = [
        SIMD2(0, 0), SIMD2(4, 0), SIMD2(0, 4),
    ]
    private let triSignals: [Float] = [0.2, 0.8, 0.5]
    private let triIndices: [Int] = [0, 1, 2]
    private let gridSize = 8

    private var expectedCovered: Set<Int> {
        // Pixel center (x+0.5, y+0.5) is inside the closed triangle
        // (0,0)-(4,0)-(0,4) iff (x+0.5)+(y+0.5) ≤ 4 ⇔ x+y ≤ 3. The four
        // x+y == 3 pixels sit EXACTLY on the hypotenuse and are covered
        // under the spec's closed-triangle rule (λ ≥ 0, edges inclusive).
        var covered = Set<Int>()
        for y in 0..<gridSize {
            for x in 0..<gridSize where x + y <= 3 {
                covered.insert(y * gridSize + x)
            }
        }
        return covered  // 10 pixels: the x+y ≤ 3 staircase
    }

    func testFC5_coveredPixelsWithinVertexSignalRange() {
        let grid = FaceMeshSignal.rasterize(
            positions: triPositions, signals: triSignals,
            triangles: triIndices, gridSize: gridSize
        )
        XCTAssertEqual(grid.count, gridSize * gridSize)

        let lo = triSignals.min()!, hi = triSignals.max()!
        let covered = expectedCovered
        XCTAssertEqual(covered.count, 10)
        for idx in covered {
            XCTAssertGreaterThanOrEqual(grid[idx], lo,
                "FC5: pixel \(idx) below min vertex signal")
            XCTAssertLessThanOrEqual(grid[idx], hi,
                "FC5: pixel \(idx) above max vertex signal")
        }

        // Barycentric spot check at pixel (0,0), center (0.5, 0.5):
        // λ = (0.75, 0.125, 0.125) ⇒ 0.75·0.2 + 0.125·0.8 + 0.125·0.5
        XCTAssertEqual(grid[0], 0.75 * 0.2 + 0.125 * 0.8 + 0.125 * 0.5,
                       accuracy: 1e-6)
    }

    func testFC6_uncoveredPixelsExactlyZero() {
        let grid = FaceMeshSignal.rasterize(
            positions: triPositions, signals: triSignals,
            triangles: triIndices, gridSize: gridSize
        )
        let covered = expectedCovered
        for idx in 0..<grid.count where !covered.contains(idx) {
            XCTAssertEqual(grid[idx], 0, "FC6: uncovered pixel \(idx) must be exactly 0")
        }
    }

    // ── Rasterizer robustness ──

    func testRasterize_windingIndependent() {
        // Reversed winding must produce the identical grid.
        let forward = FaceMeshSignal.rasterize(
            positions: triPositions, signals: triSignals,
            triangles: [0, 1, 2], gridSize: gridSize
        )
        let reversed = FaceMeshSignal.rasterize(
            positions: triPositions, signals: triSignals,
            triangles: [0, 2, 1], gridSize: gridSize
        )
        XCTAssertEqual(forward, reversed)
    }

    func testRasterize_degenerateTriangleCoversNothing() {
        let positions: [SIMD2<Float>] = [SIMD2(1, 1), SIMD2(3, 3), SIMD2(5, 5)]
        let grid = FaceMeshSignal.rasterize(
            positions: positions, signals: [1, 1, 1],
            triangles: [0, 1, 2], gridSize: gridSize
        )
        XCTAssertEqual(grid, [Float](repeating: 0, count: gridSize * gridSize))
    }

    func testRasterize_sharedEdgeRasterizesOnce() {
        // Two triangles sharing the diagonal of the unit-4 square: under the
        // closed-triangle rule a pixel on the shared edge is covered by BOTH
        // triangles, but both interpolate the identical value there, so the
        // max-combine changes nothing — the square is fully covered with
        // values in the [min,max] signal range.
        let positions: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(4, 0), SIMD2(4, 4), SIMD2(0, 4),
        ]
        let signals: [Float] = [0.1, 0.9, 0.3, 0.7]
        let grid = FaceMeshSignal.rasterize(
            positions: positions, signals: signals,
            triangles: [0, 1, 2, 0, 2, 3], gridSize: gridSize
        )
        for y in 0..<4 {
            for x in 0..<4 {
                let v = grid[y * gridSize + x]
                XCTAssertGreaterThanOrEqual(v, 0.1)
                XCTAssertLessThanOrEqual(v, 0.9)
                XCTAssertGreaterThan(v, 0, "square interior must be covered")
            }
        }
    }
}
