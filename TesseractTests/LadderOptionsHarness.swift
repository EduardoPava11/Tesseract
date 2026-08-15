// LadderOptionsHarness.swift
// Tesseract
//
// A DECISION HARNESS, not a gate. It runs each candidate for the open
// ladder rulings on a real-shaped 64³ cube and prints what each one
// actually does to the artifact, so the choice is made on measured
// consequences instead of on adjectives.
//
// It asserts almost nothing on purpose. Its output is the product.
// Delete it once the rulings are made.
//
// Run:
//   xcodebuild test -only-testing:TesseractTests/LadderOptionsHarness

import XCTest
@testable import Tesseract

final class LadderOptionsHarness: XCTestCase {

    // The real export shape.
    private let frames = 64
    private let side = 64

    // MARK: - A realistic capture

    private func skinStats(seed: Int = 1) -> DyadPalette.Stats {
        var s = seed
        func next() -> Double {
            s = (1103515245 * s + 12345) % 2147483648
            return Double(s) / 2147483648.0
        }
        let samples = (0..<324).map { _ -> (UInt8, UInt8, UInt8) in
            (UInt8(140 + Int(next() * 80)), UInt8(110 + Int(next() * 60)),
             UInt8(90 + Int(next() * 50)))
        }
        return DyadPalette.analyze(samples)
    }

    /// A subject that MOVES: a warm blob drifting across a cooler
    /// ground, so the coarse rungs have real structure to commit to
    /// and the fine rung has real detail to disagree about.
    private func capture() -> (labs: [[OKLabColor]], masks: [[Bool]],
                               fars: [[Bool]], prims: [[OKLabColor]],
                               nodes: [[OKLabColor]]) {
        let tree = PairTree.solveFigures(stats: skinStats())
        let prims = Array(repeating: tree.figures, count: frames)
        let nodes = Array(repeating: tree.nodes16, count: frames)
        var s = 20260814
        func next() -> Double {
            s = (1103515245 * s + 12345) % 2147483648
            return Double(s) / 2147483648.0
        }
        var labs: [[OKLabColor]] = []
        var masks: [[Bool]] = []
        for f in 0..<frames {
            // The blob drifts along a diagonal over the loop.
            let cx = 20.0 + 24.0 * Double(f) / Double(frames)
            let cy = 32.0 + 8.0 * sin(Double(f) * 0.1)
            var frame: [OKLabColor] = []
            var mask = [Bool](repeating: false, count: side * side)
            for y in 0..<side {
                for x in 0..<side {
                    let dx = Double(x) - cx, dy = Double(y) - cy
                    let r = (dx * dx + dy * dy).squareRoot()
                    let isSubject = r < 18
                    mask[y * side + x] = isSubject
                    // Subject: warm, with fine texture. Ground: cooler
                    // and smoother, so the two scales differ in how
                    // much detail they carry.
                    let base = isSubject ? 0.68 : 0.42
                    let tex = isSubject ? 0.06 : 0.015
                    let ramp = 0.05 * Double(x + y) / Double(2 * side)
                    frame.append(OKLabColor(
                        l: base + ramp + tex * (next() - 0.5),
                        a: (isSubject ? 0.055 : 0.005) + 0.01 * (next() - 0.5),
                        b: (isSubject ? 0.085 : 0.020) + 0.01 * (next() - 0.5)))
                }
            }
            labs.append(frame)
            masks.append(mask)
        }
        let fars = Array(repeating: [Bool](repeating: false, count: side * side),
                         count: frames)
        return (labs, masks, fars, prims, nodes)
    }

    // MARK: - Measurements

    /// Mean OKLab distortion of an assignment against its own palette.
    private func distortion(_ idx: [[UInt8]], _ c: (labs: [[OKLabColor]],
                                                    masks: [[Bool]], fars: [[Bool]],
                                                    prims: [[OKLabColor]],
                                                    nodes: [[OKLabColor]])) -> Double {
        var total = 0.0
        var n = 0
        for f in 0..<frames {
            for p in 0..<(side * side) {
                let i = Int(idx[f][p])
                let leaf = i < 128 ? i : 255 - i
                total += DyadPalette.dLab2(c.prims[f][leaf], c.labs[f][p])
                n += 1
            }
        }
        return total / Double(n)
    }

    /// Departure from a perfect bijection over a 256-cell unit:
    /// 0 = every palette entry used exactly once, 1 = all one entry.
    private func departure(_ counts: [Int]) -> Double {
        let excess = counts.reduce(0) { $0 + abs($1 - 1) }
        return Double(excess) / 510.0
    }

    /// Reading A: one rung-16 coarse frame is 16×16 = 256 coarse
    /// voxels. A coarse voxel has no index of its own, so it must be
    /// REDUCED from its 4×4×4 block; the mode is the honest reduction.
    private func coarseFrameOccupancy(_ idx: [[UInt8]]) -> [Double] {
        var out: [Double] = []
        for ct in 0..<(frames / 4) {
            var counts = [Int](repeating: 0, count: 256)
            for cy in 0..<(side / 4) {
                for cx in 0..<(side / 4) {
                    var hist = [Int](repeating: 0, count: 256)
                    for dt in 0..<4 {
                        for dy in 0..<4 {
                            for dx in 0..<4 {
                                let i = idx[ct * 4 + dt][(cy * 4 + dy) * side + cx * 4 + dx]
                                hist[Int(i)] += 1
                            }
                        }
                    }
                    var best = 0, bestN = -1
                    for i in 0..<256 where hist[i] > bestN { bestN = hist[i]; best = i }
                    counts[best] += 1
                }
            }
            out.append(departure(counts))
        }
        return out
    }

    /// Reading B: one 16×16 spatial tile of a fine frame is 256 real
    /// voxels, each with its own index. No reduction needed.
    private func tileOccupancy(_ idx: [[UInt8]]) -> [Double] {
        var out: [Double] = []
        for f in 0..<frames {
            for ty in 0..<(side / 16) {
                for tx in 0..<(side / 16) {
                    var counts = [Int](repeating: 0, count: 256)
                    for dy in 0..<16 {
                        let row: Int = (ty * 16 + dy) * side
                        for dx in 0..<16 {
                            let col: Int = tx * 16 + dx
                            let v: Int = Int(idx[f][row + col])
                            counts[v] += 1
                        }
                    }
                    out.append(departure(counts))
                }
            }
        }
        return out
    }

    private func stats(_ xs: [Double]) -> (mean: Double, lo: Double, hi: Double) {
        let m = xs.reduce(0, +) / Double(xs.count)
        return (m, xs.min() ?? 0, xs.max() ?? 0)
    }

    // MARK: - The override, per the ruling: each capture sets its line

    /// Returns (indexFrames, overrideRate, crossover, degenerate).
    private func overriding(_ c: (labs: [[OKLabColor]], masks: [[Bool]],
                                  fars: [[Bool]], prims: [[OKLabColor]],
                                  nodes: [[OKLabColor]]),
                            nested: [[UInt8]], free: [[UInt8]])
        -> (idx: [[UInt8]], rate: Double, crossover: Double, degenerate: Bool) {
        // The gap: how much worse the committed leaf is than the free
        // one, per voxel. Non-negative by construction.
        var gaps: [Double] = []
        gaps.reserveCapacity(frames * side * side)
        for f in 0..<frames {
            for p in 0..<(side * side) {
                let ci = Int(nested[f][p]), fi = Int(free[f][p])
                let cl = ci < 128 ? ci : 255 - ci
                let fl = fi < 128 ? fi : 255 - fi
                let dC = DyadPalette.dLab2(c.prims[f][cl], c.labs[f][p])
                let dF = DyadPalette.dLab2(c.prims[f][fl], c.labs[f][p])
                gaps.append(max(0, dC - dF))
            }
        }
        // The capture's own two piles: quibbles and fights.
        let fit = DepthMixture.fit(gaps)
        let cross = fit.crossover
        if fit.isDegenerate || !cross.isFinite {
            return (nested, 0, cross, true)
        }
        var out = nested
        var n = 0
        var k = 0
        for f in 0..<frames {
            for p in 0..<(side * side) {
                if gaps[k] > cross { out[f][p] = free[f][p]; n += 1 }
                k += 1
            }
        }
        return (out, Double(n) / Double(k), cross, false)
    }

    /// How far the believed tower is from a tower refitted to the
    /// picture that actually came out: the fraction of blocks whose
    /// best single value changed.
    private func towerCorrection(_ st: AdditiveCensus.Stratum,
                                 believed: [[UInt8]], realized: [[UInt8]]) -> Double {
        let k = st.blockSide
        guard k >= 1, side % k == 0, frames % k == 0 else { return 0 }
        let n = side / k, nT = frames / k
        var changed = 0, total = 0
        for bt in 0..<nT {
            for by in 0..<n {
                for bx in 0..<n {
                    func mode(_ cube: [[UInt8]]) -> Int {
                        var hist = [Int](repeating: 0, count: 8)
                        for dt in 0..<k {
                            for dy in 0..<k {
                                for dx in 0..<k {
                                    let v = AdditiveCensus.field(
                                        st, cube[bt * k + dt][(by * k + dy) * side + bx * k + dx])
                                    hist[v] += 1
                                }
                            }
                        }
                        var best = 0, bestN = -1
                        for i in 0..<8 where hist[i] > bestN { bestN = hist[i]; best = i }
                        return best
                    }
                    if mode(believed) != mode(realized) { changed += 1 }
                    total += 1
                }
            }
        }
        return total == 0 ? 0 : Double(changed) / Double(total)
    }

    // MARK: - The report

    func testMeasureTheOpenRulings() {
        let c = capture()

        let nested = StrataDescent.assign(labs: c.labs, masks: c.masks, fars: c.fars,
                                          primaries: c.prims, nodes16: c.nodes, side: side)
        let free = (0..<frames).map { f in
            DyadPipeline.assignRoles(labs: c.labs[f], mask: c.masks[f],
                                     far: c.fars[f], labPrimaries: c.prims[f])
        }
        let ov = overriding(c, nested: nested, free: free)

        func row(_ name: String, _ idx: [[UInt8]]) -> String {
            let c16 = AdditiveCensus.conformance(AdditiveCensus.r16, indexFrames: idx, side: side)
            let c32 = AdditiveCensus.conformance(AdditiveCensus.r32, indexFrames: idx, side: side)
            let bits = GIFEncoder.lzwCost(indexFrames: idx)
            let d = distortion(idx, c)
            let used = Set(idx.flatMap { $0 }).count
            return String(format: "  %-22@  %6.3f  %6.3f  %9d  %9.6f  %4d",
                          name as NSString, c16, c32, bits, d, used)
        }

        print("")
        print("══════════════════════════════════════════════════════════════")
        print(" LADDER OPTIONS, MEASURED ON A 64×64×64 CAPTURE")
        print("══════════════════════════════════════════════════════════════")
        print("")
        print("  assignment              r16     r32       LZW b   distortion  used")
        print("  ────────────────────────────────────────────────────────────────")
        print(row("free (pre-S8)", free))
        print(row("nested (S8 today)", nested))
        print(row("override (ruled)", ov.idx))
        print("")
        print(String(format: "  override rate      %.2f%% of voxels", ov.rate * 100))
        print(String(format: "  crossover found    %.6f  (degenerate: %@)",
                     ov.crossover, ov.degenerate ? "YES" : "no"))
        print("")

        // ── Q: which 256-cell unit ──────────────────────────────────
        let coarse = coarseFrameOccupancy(ov.idx)
        let tiles = tileOccupancy(ov.idx)
        let cs = stats(coarse), ts = stats(tiles)
        print("──────────────────────────────────────────────────────────────")
        print(" THE 256-CELL UNIT: departure from bijection (0 = perfect)")
        print("──────────────────────────────────────────────────────────────")
        print(String(format: "  A coarse frame   %4d readings   mean %.3f   range %.3f..%.3f",
                     coarse.count, cs.mean, cs.lo, cs.hi))
        print(String(format: "  B spatial tile   %4d readings   mean %.3f   range %.3f..%.3f",
                     tiles.count, ts.mean, ts.lo, ts.hi))
        print("")
        print("  A, per coarse frame (this is 'how it moves' in time):")
        print("    " + coarse.map { String(format: "%.2f", $0) }.joined(separator: " "))
        print("")
        print("  B, frame 0's 4×4 tile grid (this is 'where' it moves):")
        for ty in 0..<4 {
            let r = (0..<4).map { String(format: "%.2f", tiles[ty * 4 + $0]) }
            print("    " + r.joined(separator: " "))
        }
        print("")

        // ── Q: does the tower need correcting ───────────────────────
        print("──────────────────────────────────────────────────────────────")
        print(" TOWER DRIFT after overrides (fraction of blocks that changed)")
        print("──────────────────────────────────────────────────────────────")
        print(String(format: "  rung 16 blocks   %.3f", towerCorrection(AdditiveCensus.r16,
                                                                       believed: nested,
                                                                       realized: ov.idx)))
        print(String(format: "  rung 32 blocks   %.3f", towerCorrection(AdditiveCensus.r32,
                                                                       believed: nested,
                                                                       realized: ov.idx)))
        print("")

        // ── Q: what a provenance line would cost ────────────────────
        let lineA = "DYAD OCCUPANCY v1 " + coarse.map { String(format: "%.3f", $0) }.joined(separator: " ")
        let lineB = "DYAD OCCUPANCY v1 " + tiles.map { String(format: "%.3f", $0) }.joined(separator: " ")
        print("──────────────────────────────────────────────────────────────")
        print(" COST OF CARRYING IT IN THE GIF")
        print("──────────────────────────────────────────────────────────────")
        print("  A coarse frame line   \(lineA.utf8.count) bytes")
        print("  B spatial tile line   \(lineB.utf8.count) bytes")
        print(String(format: "  (the whole GIF is about %d bytes of LZW)",
                     GIFEncoder.lzwCost(indexFrames: ov.idx) / 8))
        print("══════════════════════════════════════════════════════════════")
        print("")
    }
}
