// FaceMeshSignal.swift
// Tesseract
//
// PURE logic for the FACE capture mode — no ARKit, only simd.
// Implements the mathematical contract in spec/temporal/FaceCadence.hs:
//
//   nose  = vertex with max z  (face-local, +z out of face)
//   R     = max_i ‖v_i − nose‖
//   s_i   = 1 − ‖v_i − nose‖ / R   ∈ [0,1]      (R = 0 ⇒ all s_i = 1)
//
// Axioms:
//   FC1: s_nose = 1 exactly
//   FC2: all signals in [0,1]
//   FC3: equal distances ⇒ equal signals
//   FC4: scale invariant (v_i ↦ λ v_i, λ > 0, leaves s unchanged)
//   FC5: rasterized pixel value ∈ [min,max] of its triangle's vertex signals
//   FC6: uncovered pixels are exactly 0
//
// The rasterizer takes PRE-PROJECTED 2D positions (grid pixel units,
// pixel centers at integer + 0.5) and interpolates the per-vertex signal
// barycentrically with a consistent top-left edge rule.

import simd

enum FaceMeshSignal {

    // MARK: - Nose Selection

    /// Index of the nose vertex: maximum z (face-local, +z out of face).
    /// Ties break to the lowest index (deterministic). Empty ⇒ nil.
    static func noseIndex(vertices: [SIMD3<Float>]) -> Int? {
        guard !vertices.isEmpty else { return nil }
        var best = 0
        for i in 1..<vertices.count where vertices[i].z > vertices[best].z {
            best = i
        }
        return best
    }

    // MARK: - Per-Vertex Signal

    /// s_i = 1 − ‖v_i − nose‖ / R with R = max distance to the nose.
    /// R = 0 (all vertices coincide) ⇒ all signals are 1. No NaN, ever.
    static func vertexSignals(vertices: [SIMD3<Float>]) -> [Float] {
        guard let ni = noseIndex(vertices: vertices) else { return [] }
        let nose = vertices[ni]
        let dists = vertices.map { simd_length($0 - nose) }
        let r = dists.max() ?? 0
        guard r > 0 else {
            return [Float](repeating: 1, count: vertices.count)
        }
        return dists.map { max(0, min(1, 1 - $0 / r)) }
    }

    // MARK: - Triangle Rasterizer

    /// Rasterize triangles over an S×S grid with barycentric interpolation
    /// of per-vertex signals.
    ///
    /// - positions: pre-projected 2D vertex positions in grid pixel units
    ///   (a pixel (x, y) has its center at (x + 0.5, y + 0.5)).
    /// - signals: one signal per vertex, same count as positions.
    /// - triangles: flat index triples (count = 3 × triangle count).
    /// - gridSize: S (output is S² floats, row-major).
    ///
    /// Edge rule (spec/temporal/FaceCadence.hs, golden reference): closed
    /// triangles — a pixel center is covered iff all three normalized
    /// barycentric coordinates are ≥ 0, edges inclusive. A pixel on a
    /// genuinely shared edge is covered by both triangles, which
    /// interpolate the identical value there, so the max-combine is
    /// harmless. Winding is normalized per triangle; degenerate
    /// (zero-area) triangles are skipped.
    /// Overlapping triangles combine with max (order-independent;
    /// at projection folds the surface nearer the nose wins).
    /// Uncovered pixels stay exactly 0; covered values clamp to [0,1].
    static func rasterize(
        positions: [SIMD2<Float>],
        signals: [Float],
        triangles: [Int],
        gridSize: Int
    ) -> [Float] {
        var grid = [Float](repeating: 0, count: max(0, gridSize * gridSize))
        guard gridSize > 0, positions.count == signals.count else { return grid }

        let s = gridSize
        let triCount = triangles.count / 3

        for t in 0..<triCount {
            let i0 = triangles[3 * t]
            let i1 = triangles[3 * t + 1]
            let i2 = triangles[3 * t + 2]
            guard i0 >= 0, i1 >= 0, i2 >= 0,
                  i0 < positions.count, i1 < positions.count, i2 < positions.count
            else { continue }

            var a = positions[i0], b = positions[i1], c = positions[i2]
            var sa = signals[i0], sb = signals[i1], sc = signals[i2]

            // Normalize winding so the doubled signed area is positive.
            var area2 = cross2(b - a, c - a)
            if area2 == 0 { continue }  // degenerate
            if area2 < 0 {
                swap(&b, &c); swap(&sb, &sc)
                area2 = -area2
            }

            // Bounding box over pixel centers, clamped to the grid.
            let minX = min(a.x, b.x, c.x), maxX = max(a.x, b.x, c.x)
            let minY = min(a.y, b.y, c.y), maxY = max(a.y, b.y, c.y)
            let x0 = max(0, Int((minX - 0.5).rounded(.up)))
            let x1 = min(s - 1, Int((maxX - 0.5).rounded(.down)))
            let y0 = max(0, Int((minY - 0.5).rounded(.up)))
            let y1 = min(s - 1, Int((maxY - 0.5).rounded(.down)))
            guard x0 <= x1, y0 <= y1 else { continue }

            let invArea2 = 1 / area2

            for y in y0...y1 {
                let py = Float(y) + 0.5
                for x in x0...x1 {
                    let p = SIMD2<Float>(Float(x) + 0.5, py)
                    let w0 = cross2(c - b, p - b)  // barycentric weight of a
                    let w1 = cross2(a - c, p - c)  // barycentric weight of b
                    let w2 = cross2(b - a, p - a)  // barycentric weight of c

                    // Closed-triangle rule: all λ ≥ 0, edges inclusive.
                    guard w0 >= 0, w1 >= 0, w2 >= 0 else { continue }

                    let value = (w0 * sa + w1 * sb + w2 * sc) * invArea2
                    let idx = y * s + x
                    grid[idx] = max(grid[idx], min(1, max(0, value)))
                }
            }
        }

        return grid
    }

    // MARK: - Helpers

    /// 2D cross product z-component.
    private static func cross2(_ u: SIMD2<Float>, _ v: SIMD2<Float>) -> Float {
        u.x * v.y - u.y * v.x
    }
}
