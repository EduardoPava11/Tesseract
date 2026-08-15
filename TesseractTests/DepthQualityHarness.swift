// DepthQualityHarness.swift
// Tesseract
//
// DEPTH PICKS THE RESOLUTION. Daniel's ruling (2026-08-14):
//   "you will need to look at the quality of the depth measurements
//    since we would need to use the 16x16, 32x32, 64x64 stack IN
//    relation to depth, in order to pick resolution size. NOT color."
//
// This is the measurement that decides the path. Depth's job is not
// colour, it is the BOUNDARY: FeedCompression FC6 already says "RGB
// says what colour; depth says WHOSE". So the quality of a depth
// measurement is exactly how well it PLACES THE FIGURE/GROUND EDGE,
// and the question is at which rung it can still do that.
//
// Ground truth is known here by construction, which is the only way
// boundary error can be measured at all. The depth field is then
// degraded the way a TrueDepth stream actually is (sensor noise,
// quantisation, and dropouts at the silhouette where hair and edges
// return nothing), so the numbers are not measured on an ideal signal.
//
// It asserts nothing. Its output is the product.
//
// Run:
//   xcodebuild test -only-testing:TesseractTests/DepthQualityHarness

import XCTest
@testable import Tesseract

final class DepthQualityHarness: XCTestCase {

    private let frames = 64
    private let side = 64

    // MARK: - A depth field with a KNOWN boundary

    private struct Scene {
        var depth: [[Double]]        // degraded, what the app would see
        var valid: [[Bool]]          // false where the sensor dropped out
        var truth: [[Bool]]          // ground truth: true = subject
    }

    /// nearDepth and farDepth are the two phases; the subject is a
    /// disc that moves, so the boundary is not a fixed set of cells.
    private func scene(noise: Double, dropoutEdge: Double) -> Scene {
        var s = 20260814
        func next() -> Double {
            s = (1103515245 * s + 12345) % 2147483648
            return Double(s) / 2147483648.0
        }
        var depth: [[Double]] = [], valid: [[Bool]] = [], truth: [[Bool]] = []
        for f in 0..<frames {
            let cx = 24.0 + 16.0 * Double(f) / Double(frames)
            let cy = 32.0 + 8.0 * sin(Double(f) * 0.11)
            var df = [Double](), vf = [Bool](), tf = [Bool]()
            for y in 0..<side {
                for x in 0..<side {
                    let dx = Double(x) - cx, dy = Double(y) - cy
                    let r = (dx * dx + dy * dy).squareRoot()
                    let subject = r < 18
                    tf.append(subject)
                    // The true depth: two phases with a physically
                    // soft edge (a face is round, not a cardboard cutout).
                    let edge = max(0, min(1, (r - 16) / 4))
                    let trueDepth = 0.30 + 0.50 * edge
                    // Sensor noise plus 12-bit quantisation.
                    let noisy = trueDepth + noise * (next() - 0.5) * 2
                    let quant = (noisy * 4096).rounded() / 4096
                    // Dropouts cluster at the silhouette, which is
                    // exactly where the boundary decision is made.
                    let atEdge = abs(r - 18) < 2.5
                    let dropped = atEdge && next() < dropoutEdge
                    vf.append(!dropped)
                    df.append(max(0, min(1, quant)))
                }
            }
            depth.append(df); valid.append(vf); truth.append(tf)
        }
        return Scene(depth: depth, valid: valid, truth: truth)
    }

    // MARK: - kappa on depth, honouring validity

    /// Pool depth by 2 in x, y and t, averaging ONLY valid cells. A
    /// block with no valid cell stays invalid: pooling must not invent
    /// a depth where the sensor returned none.
    private func contract(_ d: [[Double]], _ v: [[Bool]], side: Int)
        -> (depth: [[Double]], valid: [[Bool]], side: Int) {
        let hs = side / 2, hf = d.count / 2
        var od: [[Double]] = [], ov: [[Bool]] = []
        for t in 0..<hf {
            var df = [Double](repeating: 0, count: hs * hs)
            var vf = [Bool](repeating: false, count: hs * hs)
            for y in 0..<hs {
                for x in 0..<hs {
                    var sum = 0.0, n = 0
                    for dt in 0..<2 {
                        for dy in 0..<2 {
                            for dx in 0..<2 {
                                let f = t * 2 + dt
                                let p = (y * 2 + dy) * side + x * 2 + dx
                                if v[f][p] { sum += d[f][p]; n += 1 }
                            }
                        }
                    }
                    df[y * hs + x] = n > 0 ? sum / Double(n) : 0
                    vf[y * hs + x] = n > 0
                }
            }
            od.append(df); ov.append(vf)
        }
        return (od, ov, hs)
    }

    // MARK: - Quality of the boundary decision at one rung

    private struct Quality {
        var separation: Double      // (muF - muB) / sigma, how distinct the phases are
        var decisiveness: Double    // 1 - mean binary entropy of the posterior
        var misclassified: Double   // against ground truth, at FINE resolution
        var edgeError: Double       // mean distance in fine cells of the placed edge
        var dropoutRate: Double
        var degenerate: Bool
    }

    /// Fit the role law at this rung, upsample the decision to the fine
    /// grid, and score it against the truth the scene was built from.
    private func quality(depth: [[Double]], valid: [[Bool]], rungSide: Int,
                         truth: [[Bool]], fineSide: Int) -> Quality {
        var samples: [Double] = []
        for f in 0..<depth.count {
            for p in 0..<(rungSide * rungSide) where valid[f][p] {
                samples.append(depth[f][p])
            }
        }
        let dropout = 1 - Double(samples.count)
                        / Double(depth.count * rungSide * rungSide)
        guard samples.count > 8 else {
            return Quality(separation: 0, decisiveness: 0, misclassified: 1,
                           edgeError: Double(fineSide), dropoutRate: dropout,
                           degenerate: true)
        }
        let fit = DepthMixture.fit(samples)
        if fit.isDegenerate {
            return Quality(separation: 0, decisiveness: 0, misclassified: 1,
                           edgeError: Double(fineSide), dropoutRate: dropout,
                           degenerate: true)
        }
        let separation = (fit.muF - fit.muB) / max(1e-9, fit.sigma)

        // Decisiveness: how close the posterior sits to 0 or 1. A rung
        // that hedges everywhere cannot own the decision.
        var hSum = 0.0
        var hN = 0
        for f in 0..<depth.count {
            for p in 0..<(rungSide * rungSide) where valid[f][p] {
                let t = min(1 - 1e-9, max(1e-9, fit.pull(depth[f][p])))
                hSum += -(t * log2(t) + (1 - t) * log2(1 - t))
                hN += 1
            }
        }
        let decisiveness = 1 - hSum / Double(max(1, hN))

        // Upsample this rung's decision to the fine grid and score it.
        let k = fineSide / rungSide
        let kt = frames / depth.count
        var wrong = 0, total = 0
        var edgeAcc = 0.0, edgeN = 0
        for f in 0..<frames {
            for y in 0..<fineSide {
                for x in 0..<fineSide {
                    let rf = f / kt, ry = y / k, rx = x / k
                    let p = ry * rungSide + rx
                    guard valid[rf][p] else { continue }
                    // The role law: pull below the crossover is figure.
                    let isSubject = depth[rf][p] < fit.crossover
                    let t = truth[f][y * fineSide + x]
                    if isSubject != t { wrong += 1; edgeAcc += Double(k); edgeN += 1 }
                    total += 1
                }
            }
        }
        return Quality(separation: separation,
                       decisiveness: decisiveness,
                       misclassified: total == 0 ? 1 : Double(wrong) / Double(total),
                       edgeError: edgeN == 0 ? 0 : edgeAcc / Double(max(1, edgeN)),
                       dropoutRate: dropout,
                       degenerate: false)
    }

    // MARK: - The report

    func testDepthDecidesTheResolution() {
        for (label, noise, dropout) in [("clean", 0.002, 0.0),
                                        ("realistic", 0.010, 0.35),
                                        ("harsh", 0.030, 0.60)] {
            let sc = scene(noise: noise, dropoutEdge: dropout)
            let r32 = contract(sc.depth, sc.valid, side: side)
            let r16 = contract(r32.depth, r32.valid, side: r32.side)

            let q64 = quality(depth: sc.depth, valid: sc.valid, rungSide: side,
                              truth: sc.truth, fineSide: side)
            let q32 = quality(depth: r32.depth, valid: r32.valid, rungSide: r32.side,
                              truth: sc.truth, fineSide: side)
            let q16 = quality(depth: r16.depth, valid: r16.valid, rungSide: r16.side,
                              truth: sc.truth, fineSide: side)

            print("")
            print("══════════════════════════════════════════════════════════════")
            print(" DEPTH QUALITY BY RUNG, scene = \(label)")
            print("   sensor noise \(noise), silhouette dropout \(Int(dropout * 100))%")
            print("══════════════════════════════════════════════════════════════")
            print("  rung   separation  decisive  misclass  edge err  dropout")
            print("  ────────────────────────────────────────────────────────")
            for (n, q) in [("64", q64), ("32", q32), ("16", q16)] {
                print(String(format: "  %-5@  %10.2f  %8.3f  %7.2f%%  %8.2f  %6.1f%%",
                             n as NSString, q.separation, q.decisiveness,
                             q.misclassified * 100, q.edgeError, q.dropoutRate * 100))
            }
        }
        print("")
        print("  separation  how far apart the two phases are, in sigmas.")
        print("  decisive    1 = the posterior commits, 0 = it hedges everywhere.")
        print("  misclass    against the truth the scene was BUILT from.")
        print("  edge err    how far the placed boundary sits, in fine cells.")
        print("══════════════════════════════════════════════════════════════")
        print("")
    }
}
