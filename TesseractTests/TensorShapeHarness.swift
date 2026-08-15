// TensorShapeHarness.swift
// Tesseract
//
// THE CAPTURE TENSOR: measuring the shape before building it.
//
// Daniel's specification (2026-08-14):
//   "16x16 is a unit. we take a measurement every 5fps. to make
//    16x16 == 256 centroids. you will need to find an equivalent
//    float resolution so that when we do the 32x32 in parallel they
//    are equivalent in that 2(32x32)==1(16x16) and so that we are
//    compressing signal. This task CAN be explored as 2x2x2 <-> 1,
//    hence the MLX model. Furthermore, 4(64x64)==2(32x32)==1(16x16).
//    What we capture should be a proprietary tensor, the shape is the
//    form, the function is the app's sole purpose."
//
// THE COUNTING, stated once so the numbers below are checkable.
// Over one 3.2 s loop the three rungs hold, per channel:
//
//   rung 16   16 frames x (16 x 16) =   4096 cells    5 fps
//   rung 32   32 frames x (32 x 32) =  32768 cells   10 fps
//   rung 64   64 frames x (64 x 64) = 262144 cells   20 fps
//
// so the ratio is 1 : 8 : 64, which is the 2x2x2 atom applied once
// and twice. EQUIVALENCE means each rung carries the SAME total
// information, so bits-per-cell must fall by exactly 8 per step.
// That is a forced triple, not a chosen one, and this harness prints
// it and then tests whether it survives contact with real data.
//
// It asserts nothing. Its output is the product. Delete it once the
// tensor is ruled.
//
// Run:
//   xcodebuild test -only-testing:TesseractTests/TensorShapeHarness

import XCTest
@testable import Tesseract

final class TensorShapeHarness: XCTestCase {

    private let fineFrames = 64
    private let fineSide = 64

    // MARK: - A capture with real structure at every scale

    /// Four channels. R, G, B and DEPTH, because depth is a tool and
    /// not a passenger: it gets measured on the same ladder.
    private struct Capture {
        var r: [[Double]], g: [[Double]], b: [[Double]], d: [[Double]]
    }

    private func capture() -> Capture {
        var s = 20260814
        func next() -> Double {
            s = (1103515245 * s + 12345) % 2147483648
            return Double(s) / 2147483648.0
        }
        var r: [[Double]] = [], g: [[Double]] = [], b: [[Double]] = [], d: [[Double]] = []
        for f in 0..<fineFrames {
            // A subject that moves, so the coarse rungs see change,
            // plus fine texture that ONLY the fine rung can see.
            let cx = 22.0 + 20.0 * Double(f) / Double(fineFrames)
            let cy = 32.0 + 9.0 * sin(Double(f) * 0.12)
            var rf = [Double](), gf = [Double](), bf = [Double](), df = [Double]()
            for y in 0..<fineSide {
                for x in 0..<fineSide {
                    let dx = Double(x) - cx, dy = Double(y) - cy
                    let rad = (dx * dx + dy * dy).squareRoot()
                    let subject = rad < 17
                    // Depth: near on the subject, far on the ground,
                    // with a soft edge so the mixture has something
                    // real to fit.
                    let depth = subject ? 0.25 + 0.05 * next()
                                        : 0.80 + 0.10 * next()
                    // Fine texture lives BELOW the coarse rungs: this
                    // is the detail the 8:1 pooling throws away, and
                    // it is what the fine rung's bits have to carry.
                    let grain = 0.03 * (next() - 0.5)
                    let ramp = 0.10 * Double(x + y) / Double(2 * fineSide)
                    rf.append(min(1, max(0, (subject ? 0.72 : 0.34) + ramp + grain)))
                    gf.append(min(1, max(0, (subject ? 0.52 : 0.38) + ramp + grain)))
                    bf.append(min(1, max(0, (subject ? 0.44 : 0.46) + ramp + grain)))
                    df.append(depth)
                }
            }
            r.append(rf); g.append(gf); b.append(bf); d.append(df)
        }
        return Capture(r: r, g: g, b: b, d: d)
    }

    // MARK: - kappa: the 2x2x2 contraction, exact

    /// Pool a cube by 2 in x, y and t. Side and frame count halve
    /// together, which is the ladder's own law (TL4).
    private func contract(_ cube: [[Double]], side: Int) -> ([[Double]], Int) {
        let frames = cube.count
        let hs = side / 2, hf = frames / 2
        var out: [[Double]] = []
        for t in 0..<hf {
            var frame = [Double](repeating: 0, count: hs * hs)
            for y in 0..<hs {
                for x in 0..<hs {
                    var sum = 0.0
                    for dt in 0..<2 {
                        for dy in 0..<2 {
                            for dx in 0..<2 {
                                sum += cube[t * 2 + dt][(y * 2 + dy) * side + x * 2 + dx]
                            }
                        }
                    }
                    frame[y * hs + x] = sum / 8.0
                }
            }
            out.append(frame)
        }
        return (out, hs)
    }

    // MARK: - Information actually present

    /// Shannon entropy in bits per cell after quantizing to `levels`.
    private func entropy(_ cube: [[Double]], levels: Int) -> Double {
        var hist = [Int](repeating: 0, count: levels)
        var n = 0
        for frame in cube {
            for v in frame {
                var q = Int(v * Double(levels))
                if q >= levels { q = levels - 1 }
                if q < 0 { q = 0 }
                hist[q] += 1
                n += 1
            }
        }
        var h = 0.0
        for c in hist where c > 0 {
            let p = Double(c) / Double(n)
            h -= p * (log(p) / log(2.0))
        }
        return h
    }

    /// RMSE of quantizing to `bits` and reading back.
    private func quantError(_ cube: [[Double]], bits: Int) -> Double {
        let levels = 1 << bits
        var se = 0.0
        var n = 0
        for frame in cube {
            for v in frame {
                var q = Int(v * Double(levels - 1) + 0.5)
                if q >= levels { q = levels - 1 }
                if q < 0 { q = 0 }
                let back = Double(q) / Double(levels - 1)
                se += (v - back) * (v - back)
                n += 1
            }
        }
        return (se / Double(n)).squareRoot()
    }

    /// sigma: rebuild the fine cube from the coarse one plus ONE SIGN
    /// BIT per child (x +/- g). This is the octave form, and the bit
    /// is exactly what an MLX model would learn to place.
    /// Returns (rmse using the ideal per-parent g, bits spent).
    private func octaveRebuild(fine: [[Double]], fineSide: Int,
                               coarse: [[Double]], coarseSide: Int) -> (rmse: Double, bits: Int) {
        var se = 0.0
        var n = 0
        var bits = 0
        let cf = coarse.count
        for ct in 0..<cf {
            for cy in 0..<coarseSide {
                for cx in 0..<coarseSide {
                    let parent = coarse[ct][cy * coarseSide + cx]
                    // The ideal g for this parent: the mean absolute
                    // deviation of its 8 children. A model learns this
                    // from context; here we hand it the best possible
                    // value so the measurement is an UPPER BOUND on
                    // what one bit can do.
                    var dev = 0.0
                    var kids: [(Int, Int, Double)] = []
                    for dt in 0..<2 {
                        for dy in 0..<2 {
                            for dx in 0..<2 {
                                let f = ct * 2 + dt
                                let p = (cy * 2 + dy) * fineSide + cx * 2 + dx
                                let v = fine[f][p]
                                kids.append((f, p, v))
                                dev += abs(v - parent)
                            }
                        }
                    }
                    let g = dev / 8.0
                    for (_, _, v) in kids {
                        let sign: Double = v >= parent ? 1 : -1
                        let rebuilt = parent + sign * g
                        se += (v - rebuilt) * (v - rebuilt)
                        n += 1
                        bits += 1
                    }
                }
            }
        }
        return ((se / Double(n)).squareRoot(), bits)
    }

    /// BALANCED sigma: the same one bit per child, but constrained to
    /// exactly 4 up and 4 down. Then the eight children average to the
    /// parent EXACTLY, so the coarse colour can never drift (the
    /// property OctaveCodec CX2 and the atlas call load-bearing).
    /// The constraint also costs FEWER bits: log2(C(8,4)) = 6.13 per
    /// parent instead of 8, because the choice set is smaller.
    /// Returns (rmse, meanDrift, bitsPerParent).
    private func balancedRebuild(fine: [[Double]], fineSide: Int,
                                 coarse: [[Double]], coarseSide: Int)
        -> (rmse: Double, drift: Double, bitsPerParent: Double) {
        var se = 0.0, n = 0, drift = 0.0, parents = 0
        for ct in 0..<coarse.count {
            for cy in 0..<coarseSide {
                for cx in 0..<coarseSide {
                    let parent = coarse[ct][cy * coarseSide + cx]
                    var kids: [Double] = []
                    for dt in 0..<2 {
                        for dy in 0..<2 {
                            for dx in 0..<2 {
                                let f = ct * 2 + dt
                                let p = (cy * 2 + dy) * fineSide + cx * 2 + dx
                                kids.append(fine[f][p])
                            }
                        }
                    }
                    // Least squares under the balance constraint: the
                    // four largest go up, the four smallest go down,
                    // and g is half the gap between the two halves.
                    let sorted = kids.sorted()
                    let lowMean = sorted[0..<4].reduce(0, +) / 4
                    let highMean = sorted[4..<8].reduce(0, +) / 4
                    let g = (highMean - lowMean) / 2
                    var rebuiltSum = 0.0
                    for v in kids {
                        let up = v >= sorted[4]
                        let rebuilt = parent + (up ? g : -g)
                        rebuiltSum += rebuilt
                        se += (v - rebuilt) * (v - rebuilt)
                        n += 1
                    }
                    drift += abs(rebuiltSum / 8 - parent)
                    parents += 1
                }
            }
        }
        let bits = (log(70.0) / log(2.0))   // C(8,4) = 70 choices
        return ((se / Double(n)).squareRoot(), drift / Double(parents), bits)
    }

    /// How far the FREE-sign form lets the coarse colour drift.
    private func freeDrift(fine: [[Double]], fineSide: Int,
                           coarse: [[Double]], coarseSide: Int) -> Double {
        var drift = 0.0, parents = 0
        for ct in 0..<coarse.count {
            for cy in 0..<coarseSide {
                for cx in 0..<coarseSide {
                    let parent = coarse[ct][cy * coarseSide + cx]
                    var kids: [Double] = []
                    for dt in 0..<2 {
                        for dy in 0..<2 {
                            for dx in 0..<2 {
                                let f = ct * 2 + dt
                                let p = (cy * 2 + dy) * fineSide + cx * 2 + dx
                                kids.append(fine[f][p])
                            }
                        }
                    }
                    var dev = 0.0
                    for v in kids { dev += abs(v - parent) }
                    let g = dev / 8.0
                    var sum = 0.0
                    for v in kids { sum += parent + (v >= parent ? g : -g) }
                    drift += abs(sum / 8 - parent)
                    parents += 1
                }
            }
        }
        return drift / Double(parents)
    }

    /// THE DIAL. The edit tool's detail control scales g. This asks
    /// the only question that matters at the surface: when the user
    /// turns that dial, does the picture's COLOUR move, or only its
    /// texture? Returns, per dial setting, how far the average colour
    /// of a region travels, in 8-bit levels.
    private func dialSweep(fine: [[Double]], fineSide: Int,
                           coarse: [[Double]], coarseSide: Int,
                           balanced: Bool, dial: Double) -> Double {
        var drift = 0.0
        var parents = 0
        for ct in 0..<coarse.count {
            for cy in 0..<coarseSide {
                for cx in 0..<coarseSide {
                    let parent = coarse[ct][cy * coarseSide + cx]
                    var kids: [Double] = []
                    for dt in 0..<2 {
                        for dy in 0..<2 {
                            for dx in 0..<2 {
                                let f = ct * 2 + dt
                                let p = (cy * 2 + dy) * fineSide + cx * 2 + dx
                                kids.append(fine[f][p])
                            }
                        }
                    }
                    var sum = 0.0
                    if balanced {
                        let sorted = kids.sorted()
                        let lo = sorted[0..<4].reduce(0, +) / 4
                        let hi = sorted[4..<8].reduce(0, +) / 4
                        let g = (hi - lo) / 2 * dial
                        for v in kids { sum += parent + (v >= sorted[4] ? g : -g) }
                    } else {
                        var dev = 0.0
                        for v in kids { dev += abs(v - parent) }
                        let g = dev / 8.0 * dial
                        for v in kids { sum += parent + (v >= parent ? g : -g) }
                    }
                    drift += abs(sum / 8 - parent)
                    parents += 1
                }
            }
        }
        return drift / Double(parents) * 255.0     // in 8-bit levels
    }

    // MARK: - The report

    func testMeasureTheTensorShape() {
        let cap = capture()

        // Build the tower for every channel.
        let (r32, s32) = contract(cap.r, side: fineSide)
        let (r16, s16) = contract(r32, side: s32)
        let (d32, _) = contract(cap.d, side: fineSide)
        let (d16, _) = contract(d32, side: s32)

        let cells16 = r16.count * s16 * s16
        let cells32 = r32.count * s32 * s32
        let cells64 = cap.r.count * fineSide * fineSide

        print("")
        print("═══════════════════════════════════════════════════════════════")
        print(" THE CAPTURE TENSOR: measured shape")
        print("═══════════════════════════════════════════════════════════════")
        print("")
        print("  rung   frames   grid      cells    fps   ratio")
        print("  ──────────────────────────────────────────────")
        print("  16     \(r16.count)       \(s16)x\(s16)     \(cells16)      5     1")
        print("  32     \(r32.count)       \(s32)x\(s32)    \(cells32)     10     \(cells32 / cells16)")
        print("  64     \(cap.r.count)       \(fineSide)x\(fineSide)   \(cells64)     20     \(cells64 / cells16)")
        print("")
        print("  16x16 = \(s16 * s16) cells per tick = 256 centroids = the palette")
        print("")

        // ── The forced bit triple ───────────────────────────────────
        print("───────────────────────────────────────────────────────────────")
        print(" EQUIVALENT FLOAT RESOLUTION (forced, not chosen)")
        print("───────────────────────────────────────────────────────────────")
        print("  equivalence: cells(r) x bits(r) must be EQUAL at every rung.")
        print("  cells are 1 : 8 : 64, so bits must be 64 : 8 : 1.")
        print("")
        let budget = cells64 * 1
        print("  rung 16   \(cells16) cells x 64 bits = \(cells16 * 64) bits   (float64)")
        print("  rung 32   \(cells32) cells x  8 bits = \(cells32 * 8) bits   (uint8)")
        print("  rung 64   \(cells64) cells x  1 bit  = \(cells64 * 1) bits   (sign)")
        print("  each rung carries \(budget) bits = \(budget / 8192) KiB per channel per loop")
        print("")

        // ── Does the data justify those depths? ─────────────────────
        print("───────────────────────────────────────────────────────────────")
        print(" WHAT THE DATA ACTUALLY HOLDS (entropy, bits per cell)")
        print("───────────────────────────────────────────────────────────────")
        print("  measured at 256 levels, so 8.00 would be a full byte of news")
        print("")
        print(String(format: "  rung 16 red      %.2f      rung 16 depth   %.2f",
                     entropy(r16, levels: 256), entropy(d16, levels: 256)))
        print(String(format: "  rung 32 red      %.2f      rung 32 depth   %.2f",
                     entropy(r32, levels: 256), entropy(d32, levels: 256)))
        print(String(format: "  rung 64 red      %.2f      rung 64 depth   %.2f",
                     entropy(cap.r, levels: 256), entropy(cap.d, levels: 256)))
        print("")

        // ── What each rung loses at its assigned depth ──────────────
        print("───────────────────────────────────────────────────────────────")
        print(" COST OF THE ASSIGNED DEPTH (RMSE, signal is 0..1)")
        print("───────────────────────────────────────────────────────────────")
        for bits in [16, 12, 8, 6, 4, 2, 1] {
            let e16 = quantError(r16, bits: bits)
            let e32 = quantError(r32, bits: bits)
            let e64 = quantError(cap.r, bits: bits)
            print(String(format: "  %2d bits   r16 %.5f   r32 %.5f   r64 %.5f",
                         bits, e16, e32, e64))
        }
        print("")

        // ── The octave form: can 1 bit carry the fine rung? ─────────
        let o64 = octaveRebuild(fine: cap.r, fineSide: fineSide, coarse: r32, coarseSide: s32)
        let o32 = octaveRebuild(fine: r32, fineSide: s32, coarse: r16, coarseSide: s16)
        let od64 = octaveRebuild(fine: cap.d, fineSide: fineSide, coarse: d32, coarseSide: s32)
        print("───────────────────────────────────────────────────────────────")
        print(" 2x2x2 <-> 1 AS ONE SIGN BIT PER CHILD (what MLX would learn)")
        print("───────────────────────────────────────────────────────────────")
        print(String(format: "  32 -> 64 red     rmse %.5f   using %d bits", o64.rmse, o64.bits))
        print(String(format: "  16 -> 32 red     rmse %.5f   using %d bits", o32.rmse, o32.bits))
        print(String(format: "  32 -> 64 depth   rmse %.5f   using %d bits", od64.rmse, od64.bits))
        print("")
        print(String(format: "  compare: storing rung 64 red at 8 bits costs %d bits",
                     cells64 * 8))
        print(String(format: "           and its own quantiser error is %.5f",
                     quantError(cap.r, bits: 8)))
        print("")

        // ── Does the coarse colour drift? ───────────────────────────
        let bal64 = balancedRebuild(fine: cap.r, fineSide: fineSide,
                                    coarse: r32, coarseSide: s32)
        let bal32 = balancedRebuild(fine: r32, fineSide: s32,
                                    coarse: r16, coarseSide: s16)
        let balD = balancedRebuild(fine: cap.d, fineSide: fineSide,
                                   coarse: d32, coarseSide: s32)
        let drift64 = freeDrift(fine: cap.r, fineSide: fineSide,
                                coarse: r32, coarseSide: s32)
        print("───────────────────────────────────────────────────────────────")
        print(" FREE SIGNS vs BALANCED (4 up, 4 down): does colour drift?")
        print("───────────────────────────────────────────────────────────────")
        print(String(format: "  free      32->64 red    rmse %.5f   drift %.5f   8.00 b/parent",
                     o64.rmse, drift64))
        print(String(format: "  balanced  32->64 red    rmse %.5f   drift %.5f   %.2f b/parent",
                     bal64.rmse, bal64.drift, bal64.bitsPerParent))
        print(String(format: "  balanced  16->32 red    rmse %.5f   drift %.5f",
                     bal32.rmse, bal32.drift))
        print(String(format: "  balanced  32->64 depth  rmse %.5f   drift %.5f",
                     balD.rmse, balD.drift))
        print("")
        print(String(format: "  balanced costs %.2f%% more error and saves %.2f%% of the bits",
                     (bal64.rmse / o64.rmse - 1) * 100,
                     (1 - bal64.bitsPerParent / 8.0) * 100))
        print("")

        // ── The dial: what the user actually feels ──────────────────
        print("───────────────────────────────────────────────────────────────")
        print(" TURNING THE DETAIL DIAL: how far the COLOUR moves (8-bit levels)")
        print("───────────────────────────────────────────────────────────────")
        print("  dial      free signs     balanced signs")
        for dial in [0.0, 0.5, 1.0, 2.0, 4.0] {
            let f = dialSweep(fine: cap.r, fineSide: fineSide, coarse: r32,
                              coarseSide: s32, balanced: false, dial: dial)
            let b = dialSweep(fine: cap.r, fineSide: fineSide, coarse: r32,
                              coarseSide: s32, balanced: true, dial: dial)
            print(String(format: "  %4.1fx     %6.2f         %6.2f", dial, f, b))
        }
        print("")
        print("  the palette IS the 16x16 layer, so colour that moves")
        print("  here is the palette no longer describing the picture.")
        print("")

        // ── The whole tensor against what is stored today ───────────
        let tensorBits = 4 * (cells16 * 64 + cells32 * 8 + cells64 * 1)
        let tensorBytes = tensorBits / 8
        let todayBytes = fineFrames * fineSide * fineSide * 7   // CubeStore: 3B rgb + 4B depth
        print("───────────────────────────────────────────────────────────────")
        print(" TENSOR SIZE, 4 CHANNELS (R G B DEPTH), ONE 3.2s CAPTURE")
        print("───────────────────────────────────────────────────────────────")
        print("  three-scale tensor   \(tensorBytes) bytes = \(tensorBytes / 1024) KiB")
        print("  CubeStore today      \(todayBytes) bytes = \(todayBytes / 1024) KiB (one scale)")
        print(String(format: "  ratio                %.2fx", Double(todayBytes) / Double(tensorBytes)))
        print("═══════════════════════════════════════════════════════════════")
        print("")
    }
}
