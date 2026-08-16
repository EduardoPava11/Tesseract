// TilingEnergyTests.swift
// Tesseract
//
// The gate on the value head. Every expected number below was PRINTED
// by spec/statistics/TilingEntropy.hs, at full Double precision, on
// its own six pinned probe frames. The probe generators are
// reproduced here rather than in app source because Meter/ is
// measurement over real captures and a fixture nothing calls would be
// dead weight in the app.
//
// ★ THE PROBE TABLE IN MerkleSearch.hs WAS WRONG WHEN THIS LANDED,
// and this file is how it was caught. That spec listed the random
// frame at (E = 0.00, E_wall = 82.64) and claimed the numbers came
// from "TilingEntropy's own pinned frames". They do not: TE prints
// (194.94, 0.26) for randomFrame 3, and no random frame can score
// E = 0 (the expected divergence of a uniform draw is about
// (K−1)/(2 ln 2) ≈ 184 bits). MT8, the load-bearing axiom, survives
// the correction untouched, because balanced still strictly dominates
// random on both axes. MT7's exact-equality half did not survive and
// was restated against the measurement. See spec/neural/MerkleSearch.hs.

import XCTest
@testable import Tesseract

final class TilingEnergyTests: XCTestCase {

    private let side = 64
    private var cells: Int { side * side }

    // MARK: - The probe frames (TilingEntropy §5, verbatim)

    /// The house LCG. `uniforms seed` is the tail of `iterate lcg
    /// seed`, so the FIRST uniform is lcg(seed)/2³¹, not seed/2³¹.
    private func uniforms(seed: Int, count: Int) -> [Double] {
        var s = seed
        return (0..<count).map { _ in
            s = (1103515245 * s + 12345) % 2147483648
            return Double(s) / 2147483648.0
        }
    }

    private let bayerOrder = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    private var solidFrame: [UInt8] { [UInt8](repeating: 255, count: cells) }

    private var neelFrame: [UInt8] {
        (0..<cells).map { p in
            let x = p % side, y = p / side
            return bayerOrder[(y % 4) * 4 + (x % 4)] < 8 ? 255 : 0
        }
    }

    /// Every colour exactly 16 times: the palette laid flat on the plane.
    private var balancedFrame: [UInt8] { (0..<cells).map { UInt8($0 % 256) } }

    private func randomFrame(_ seed: Int) -> [UInt8] {
        uniforms(seed: seed, count: cells).map { UInt8(min(255, Int($0 * 256))) }
    }

    /// Indices 0..127 only, so every spin is figure and E_wall saturates.
    private func faceFrame(_ seed: Int) -> [UInt8] {
        uniforms(seed: seed, count: cells).map { UInt8(min(127, Int($0 * 128))) }
    }

    private func threeRegion(_ seed: Int) -> [UInt8] {
        let face = faceFrame(seed)
        return (0..<cells).map { p in
            let x = p % side, y = p / side
            if y < 20 { return 255 }
            if y < 44 { return bayerOrder[(y % 4) * 4 + (x % 4)] < 8 ? 255 : 64 }
            return face[p]
        }
    }

    // MARK: - The frames themselves match the spec's

    /// If the LCG walk drifted by one step every energy below would be
    /// wrong for an invisible reason, so the first eight draws of two
    /// probes are pinned directly.
    func testProbeFramesReproduceTheSpecsOwn() {
        XCTAssertEqual(Array(randomFrame(3).prefix(8)),
                       [138, 55, 80, 64, 161, 123, 32, 121])
        XCTAssertEqual(Array(faceFrame(7).prefix(8)),
                       [76, 38, 42, 88, 127, 13, 125, 124])
    }

    // MARK: - TE1/TE3: the state space and the range

    func testStateSpaceAndRange() {
        XCTAssertEqual(TilingEnergy.omegaBits, 32768)
        XCTAssertEqual(TilingEnergy.bonds, 8064)
        XCTAssertEqual(TilingEnergy.balanced, 16)
        XCTAssertEqual(TilingEnergy.balanced * TilingEnergy.colors,
                       TilingEnergy.cells)
        for f in [solidFrame, neelFrame, balancedFrame, faceFrame(7),
                  randomFrame(3), threeRegion(5)] {
            let e = TilingEnergy.energy(TilingEnergy.histogram(f))
            XCTAssertGreaterThanOrEqual(e, -1e-9)
            XCTAssertLessThanOrEqual(e, TilingEnergy.omegaBits + 1e-9)
            let w = TilingEnergy.wallEnergy(f)
            XCTAssertGreaterThanOrEqual(w, -1e-9)
            XCTAssertLessThanOrEqual(w, Double(TilingEnergy.bonds) + 1e-9)
        }
    }

    // MARK: - TE2/TE3/TE7: the pinned energies

    func testEnergiesMatchTheSpecToSixDecimals() {
        // name, frame, E, E_exact, wallCount, E_wall, colours used
        let cases: [(String, [UInt8], Double, Double, Int, Double, Int)] = [
            ("balanced", balancedFrame,
             0.0, 0.0, 1984, 1573.0622753563964, 256),
            ("random", randomFrame(3),
             194.9430941564881, 188.67024698034948, 4005, 0.2608463653809565, 256),
            ("face", faceFrame(7),
             4182.212238948516, 3817.7129259476787, 0, 8064.0, 128),
            ("three", threeRegion(5),
             17910.680678043784, 17447.02286184301, 3048, 349.97663451134645, 129),
            ("neel", neelFrame,
             28672.0, 27832.336765765154, 8064, 8064.0, 2),
            ("solid", solidFrame,
             32768.0, 31922.010929645316, 0, 8064.0, 1),
        ]
        for (name, frame, e, eExact, wc, eWall, used) in cases {
            let h = TilingEnergy.histogram(frame)
            XCTAssertEqual(h.reduce(0, +), cells, name)
            XCTAssertEqual(h.filter { $0 > 0 }.count, used, name)
            XCTAssertEqual(TilingEnergy.energy(h), e, accuracy: 1e-6, name)
            XCTAssertEqual(TilingEnergy.energyExact(h), eExact, accuracy: 1e-6, name)
            XCTAssertEqual(TilingEnergy.wallCount(frame), wc, name)
            XCTAssertEqual(TilingEnergy.wallEnergy(frame), eWall, accuracy: 1e-6, name)
            // TE7: the Boltzmann twin is a debit on E, never a credit.
            XCTAssertLessThanOrEqual(TilingEnergy.energyExact(h), e + 1e-6, name)
        }
        XCTAssertEqual(TilingEnergy.groundMultiplicityBits,
                       31922.010929645316, accuracy: 1e-6)
    }

    /// TE2: the ground state is the balanced tiling, and it is
    /// surjective for free.
    func testGroundStateIsSurjectiveByLaw() {
        let h = TilingEnergy.histogram(balancedFrame)
        XCTAssertTrue(h.allSatisfy { $0 == TilingEnergy.balanced })
        XCTAssertEqual(TilingEnergy.energy(h), 0, accuracy: 1e-9)
        XCTAssertEqual(TilingEnergy.energyExact(h), 0, accuracy: 1e-9)
        XCTAssertEqual(TilingEnergy.energyPerCell(h), 0, accuracy: 1e-12)
        XCTAssertEqual(TilingEnergy.energyPerCell(TilingEnergy.histogram(solidFrame)),
                       8, accuracy: 1e-12)
    }

    // MARK: - TE4/TE5: the chain rule and the order parameter

    func testChainRuleSumsToTheEnergy() {
        for f in [solidFrame, neelFrame, balancedFrame, faceFrame(7),
                  randomFrame(3), threeRegion(5)] {
            let h = TilingEnergy.histogram(f)
            let levels = TilingEnergy.levelEnergies(h)
            XCTAssertEqual(levels.count, 8)
            XCTAssertTrue(levels.allSatisfy { $0 >= -1e-9 })
            XCTAssertEqual(levels.reduce(0, +), TilingEnergy.energy(h),
                           accuracy: 1e-6)
            // TE5: the root level IS N(1 − h(φ)).
            let figure = h[0..<128].reduce(0, +), ground = h[128...].reduce(0, +)
            XCTAssertEqual(levels[0],
                           Double(figure + ground) * (1 - TilingEnergy.hBin(figure, ground)),
                           accuracy: 1e-9)
        }
        // Pinned against the spec's printed decomposition. The root
        // level is the whole 4096 because faceFrame never leaves the
        // figure half, so φ = 0 and the σ split carries no entropy.
        let pinned = [4096.0, 0.22824180246607284, 2.2218382917170048,
                      2.291511488011947, 7.410192830700522, 12.446977695514894,
                      25.01466486222455, 36.59881197787898]
        let measured = TilingEnergy.levelEnergies(TilingEnergy.histogram(faceFrame(7)))
        XCTAssertEqual(measured.count, pinned.count)
        for (m, p) in zip(measured, pinned) {
            XCTAssertEqual(m, p, accuracy: 1e-9)
        }
        XCTAssertEqual(TilingEnergy.phi(TilingEnergy.histogram(faceFrame(7))), 0)
        XCTAssertEqual(TilingEnergy.phi(TilingEnergy.histogram(solidFrame)), 1)
    }

    // MARK: - TE6: label invariance

    func testEnergyIsInvariantUnderEveryRelabeling() {
        for f in [neelFrame, faceFrame(7), threeRegion(5)] {
            let h = TilingEnergy.histogram(f)
            let e = TilingEnergy.energy(h)
            XCTAssertEqual(TilingEnergy.energy(h.reversed()), e, accuracy: 1e-9)
            XCTAssertEqual(TilingEnergy.energy(h.sorted()), e, accuracy: 1e-9)
            // σ(i) = 255 − i, the decreed involution.
            XCTAssertEqual(TilingEnergy.energy((0..<256).map { h[255 - $0] }),
                           e, accuracy: 1e-9)
            // CL4's free relabelings: XOR by any mask.
            for mask in [1, 7, 64, 128, 255] {
                var x = [Int](repeating: 0, count: 256)
                for i in 0..<256 { x[i ^ mask] = h[i] }
                XCTAssertEqual(TilingEnergy.energy(x), e, accuracy: 1e-9)
            }
        }
    }

    // MARK: - TE8: order and anti-order cost the same

    func testWallEnergyIsBlindToTheSignOfOrder() {
        XCTAssertEqual(TilingEnergy.wallCount(solidFrame), 0)
        XCTAssertEqual(TilingEnergy.wallCount(neelFrame), TilingEnergy.bonds)
        XCTAssertEqual(TilingEnergy.wallEnergy(solidFrame),
                       Double(TilingEnergy.bonds), accuracy: 1e-9)
        XCTAssertEqual(TilingEnergy.wallEnergy(neelFrame),
                       Double(TilingEnergy.bonds), accuracy: 1e-9)
        XCTAssertLessThan(TilingEnergy.wallEnergy(randomFrame(3)), 10)
    }

    // MARK: - TE9: the cube telescopes

    func testCubeValueTelescopes() {
        let frames = [randomFrame(3), faceFrame(7), threeRegion(5), solidFrame]
        let v = TilingEnergy.value(cube: frames)
        // Ceiling of a 64-frame cube: 2,097,152 bits = 256 KiB.
        XCTAssertEqual(64 * cells * 8, 2_097_152)
        // A frame-mixed histogram cannot be more ordered than its parts
        // on average (concavity of H₀).
        let meanFrame = frames
            .map { TilingEnergy.energy(TilingEnergy.histogram($0)) }
            .reduce(0, +) / Double(frames.count)
        XCTAssertGreaterThanOrEqual(v.eHist + 1e-6, meanFrame - 1e-6)
        // The spatial stratum is the sum of the frames' disjoint bonds.
        XCTAssertEqual(v.eWall,
                       frames.map { TilingEnergy.wallEnergy($0) }.reduce(0, +),
                       accuracy: 1e-9)
    }

    // MARK: - The temporal stratum (TE11 to TE15)

    private let ticks = 16

    private var zeroFrame: [UInt8] { [UInt8](repeating: 0, count: cells) }

    /// Never moves: w_t = 0, the ordered end.
    private var stillCube: [[UInt8]] {
        [[UInt8]](repeating: faceFrame(7), count: ticks)
    }

    /// Every role inverts every tick: w_t = 1, the anti-ordered end.
    private var strobeCube: [[UInt8]] {
        (0..<ticks).map { $0 % 2 == 0 ? solidFrame : zeroFrame }
    }

    /// Roles independent tick to tick: w_t near one half, the cheap end.
    private var noiseCube: [[UInt8]] { (1...ticks).map { randomFrame(7 * $0 + 1) } }

    /// A half-plane rolling around the plane, closing exactly after
    /// `ticks`. Genuine motion, strictly between the two ceilings.
    private var driftCube: [[UInt8]] {
        let step = cells / ticks
        return (0..<ticks).map { i in
            (0..<cells).map { p in ((p + i * step) % cells) < cells / 2 ? 255 : 0 }
        }
    }

    private func rotateBy<T>(_ n: Int, _ xs: [T]) -> [T] {
        guard !xs.isEmpty else { return xs }
        let k = ((n % xs.count) + xs.count) % xs.count
        return Array(xs[k...]) + Array(xs[..<k])
    }

    /// Evens then odds: any permutation fixes eHist and eWall, and this
    /// one demonstrably moves eTime.
    private func deal<T>(_ xs: [T]) -> [T] {
        xs.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element }
            + xs.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element }
    }

    /// TE11: the loop is CLOSED. B_t = nf·N, so the last tick's bond is
    /// the 63 → 0 one and it counts like any other.
    func testTheLoopCloses() {
        XCTAssertEqual(TilingEnergy.timeBonds(frames: 64), 262_144)
        XCTAssertEqual(TilingEnergy.timeBonds(frames: ticks), ticks * cells)
        XCTAssertEqual(TilingEnergy.wallCountTime(cube: stillCube), 0)
        XCTAssertEqual(TilingEnergy.wallCountTime(cube: strobeCube),
                       TilingEnergy.timeBonds(frames: ticks))
        // Proof the wrap is COUNTED and not assumed: drop one frame so
        // the strobe has odd length, and the closing bond now joins two
        // EQUAL frames. Exactly one tick's worth of walls disappears.
        let odd = Array(strobeCube.dropLast())   // 15 frames, both ends solid
        XCTAssertEqual(odd.count, ticks - 1)
        XCTAssertEqual(TilingEnergy.wallCountTime(cube: odd),
                       TilingEnergy.timeBonds(frames: odd.count) - cells)
    }

    /// ★ TE12, Daniel's Ruling 7 answered: rotation of ℤ/64 IS an
    /// equivalence. EXACT on the integer observables; the float
    /// energies agree to reassociation noise, because rotating a sum of
    /// 16 Doubles reorders the additions.
    func testRotationIsAnEquivalence() {
        for cube in [stillCube, strobeCube, driftCube, noiseCube] {
            let base = TilingEnergy.value(cube: cube)
            let baseWalls = cube.map { TilingEnergy.wallCount($0) }.sorted()
            let baseTime = TilingEnergy.wallCountTime(cube: cube)
            for r in 0..<ticks {
                let rot = rotateBy(r, cube)
                // Integers: exactly fixed.
                XCTAssertEqual(rot.map { TilingEnergy.wallCount($0) }.sorted(),
                               baseWalls)
                XCTAssertEqual(TilingEnergy.wallCountTime(cube: rot), baseTime)
                // Floats: fixed to reassociation noise.
                let v = TilingEnergy.value(cube: rot)
                XCTAssertEqual(v.eHist, base.eHist, accuracy: 1e-9 * max(1, base.eHist))
                XCTAssertEqual(v.eWall, base.eWall, accuracy: 1e-9 * max(1, base.eWall))
                XCTAssertEqual(v.eTime, base.eTime, accuracy: 1e-9 * max(1, base.eTime))
            }
        }
    }

    /// ★ TE13, the whole point: a SHUFFLE is not an equivalence. The
    /// first two strata are symmetric in the frames and cannot see
    /// order at all; the third can. Before this stratum the app's only
    /// closed-form quality measure scored a GIF and its shuffle the same.
    func testAShuffleIsNotAnEquivalence() {
        for cube in [driftCube, noiseCube] {
            let base = TilingEnergy.value(cube: cube)
            let dealt = TilingEnergy.value(cube: deal(cube))
            // eHist is exactly fixed: the pooled histogram is integer
            // addition, so reordering cannot move it at all.
            XCTAssertEqual(dealt.eHist, base.eHist)
            // eWall is fixed as a multiset sum, to reassociation noise
            // (the same distinction TE12 draws).
            XCTAssertEqual(dealt.eWall, base.eWall,
                           accuracy: 1e-9 * max(1, base.eWall))
            // eTime is not fixed, and that is the point.
            XCTAssertNotEqual(dealt.eTime, base.eTime)
        }
    }

    /// TE14: order and anti-order cost the same in time too. The
    /// stratum measures COHERENCE, not motion, so "reward less change"
    /// is not what it says.
    func testTimeOrderAndAntiOrderCostTheSame() {
        let ceiling = Double(TilingEnergy.timeBonds(frames: ticks))
        XCTAssertEqual(TilingEnergy.timeEnergy(cube: stillCube), ceiling, accuracy: 1e-9)
        XCTAssertEqual(TilingEnergy.timeEnergy(cube: strobeCube), ceiling, accuracy: 1e-9)
        XCTAssertLessThan(TilingEnergy.timeEnergy(cube: noiseCube), ceiling / 1000)
        XCTAssertGreaterThan(TilingEnergy.timeEnergy(cube: driftCube),
                             TilingEnergy.timeEnergy(cube: noiseCube))
        XCTAssertLessThan(TilingEnergy.timeEnergy(cube: driftCube), ceiling)
    }

    /// TE15: three disjoint strata, one currency, and the ceilings the
    /// 64-tick artifact actually has.
    func testThreeStrataAndTheirCeilings() {
        XCTAssertEqual(64 * cells * 8, 2_097_152)
        XCTAssertEqual(64 * TilingEnergy.bonds, 516_096)
        XCTAssertEqual(TilingEnergy.timeBonds(frames: 64), 262_144)
        for cube in [stillCube, strobeCube, driftCube, noiseCube] {
            let v = TilingEnergy.value(cube: cube)
            XCTAssertGreaterThanOrEqual(v.eHist, -1e-6)
            XCTAssertLessThanOrEqual(v.eHist, Double(ticks * cells * 8) + 1e-6)
            XCTAssertGreaterThanOrEqual(v.eWall, -1e-6)
            XCTAssertLessThanOrEqual(v.eWall, Double(ticks * TilingEnergy.bonds) + 1e-6)
            XCTAssertGreaterThanOrEqual(v.eTime, -1e-6)
            XCTAssertLessThanOrEqual(v.eTime,
                                     Double(TilingEnergy.timeBonds(frames: ticks)) + 1e-6)
            XCTAssertEqual(v.bondEnergy, v.eWall + v.eTime, accuracy: 1e-9)
        }
    }

    /// The three-axis order: each axis read in its own direction, and a
    /// third axis widens the front rather than narrowing it.
    func testTheThreeAxisOrder() {
        let still = TilingEnergy.value(cube: stillCube)
        let noise = TilingEnergy.value(cube: noiseCube)
        // The still face beats the noise cube on the two bond strata and
        // loses on E, so neither dominates: both survive the front.
        XCTAssertFalse(TilingEnergy.dominates(still, noise))
        XCTAssertFalse(TilingEnergy.dominates(noise, still))
        // Domination is reflexively false and antisymmetric.
        XCTAssertFalse(TilingEnergy.dominates(still, still))
        let better = TilingEnergy.CubeValue(eHist: still.eHist - 1,
                                            eWall: still.eWall,
                                            eTime: still.eTime)
        XCTAssertTrue(TilingEnergy.dominates(better, still))
        XCTAssertFalse(TilingEnergy.dominates(still, better))
        // A cube that is worse on the temporal axis alone is dominated,
        // which is exactly what the old two-axis order could not see.
        let laterShuffle = TilingEnergy.CubeValue(eHist: still.eHist,
                                                  eWall: still.eWall,
                                                  eTime: still.eTime - 1)
        XCTAssertTrue(TilingEnergy.dominates(still, laterShuffle))
    }

    // MARK: - TE10: the calibration has no free scale

    func testEnergyIsTheBitsTheLedgerAlreadyReports() {
        for f in [solidFrame, neelFrame, balancedFrame, faceFrame(7),
                  randomFrame(3), threeRegion(5)] {
            let h = TilingEnergy.histogram(f)
            let n = Double(h.reduce(0, +))
            XCTAssertEqual(TilingEnergy.energy(h),
                           n * 8 - n * TilingEnergy.h0(h), accuracy: 1e-6)
        }
    }

    // MARK: - MT6/MT7/MT8: the front is where the pictures are

    private var probeValues: [(String, TilingEnergy.Value)] {
        [("balanced", TilingEnergy.value(frame: balancedFrame)),
         ("random", TilingEnergy.value(frame: randomFrame(3))),
         ("face", TilingEnergy.value(frame: faceFrame(7))),
         ("three", TilingEnergy.value(frame: threeRegion(5))),
         ("neel", TilingEnergy.value(frame: neelFrame)),
         ("solid", TilingEnergy.value(frame: solidFrame))]
    }

    /// MT6: grey is the CEILING of E, so descending it cannot go grey.
    func testGreyIsTheCeilingNotTheFloor() {
        let es = probeValues.map { $0.1.eHist }
        XCTAssertEqual(TilingEnergy.value(frame: solidFrame).eHist, es.max())
        XCTAssertEqual(TilingEnergy.value(frame: balancedFrame).eHist, es.min())
        XCTAssertGreaterThan(TilingEnergy.value(frame: solidFrame).eHist,
                             TilingEnergy.value(frame: faceFrame(7)).eHist)
    }

    /// MT7, RESTATED against the measurement. E_wall's blindness is
    /// EXACT: face, neel and solid all sit at 8064.0 to the bit. E's
    /// blindness is not exact but it is severe: balanced and random
    /// differ by 194.94 bits, which is 0.6% of E's own range, against
    /// the 32768 that separates balanced from solid. So E orders the
    /// two degenerate corners 168 times more weakly than it orders the
    /// picture, which is why a scalar descent on E lands on static.
    func testEachEnergyIsBlindToADifferentCorner() {
        let v = Dictionary(uniqueKeysWithValues: probeValues)
        XCTAssertEqual(v["face"]!.eWall, v["solid"]!.eWall, accuracy: 1e-9)
        XCTAssertEqual(v["face"]!.eWall, v["neel"]!.eWall, accuracy: 1e-9)
        XCTAssertNotEqual(v["face"]!.eHist, v["solid"]!.eHist)

        let gap = abs(v["balanced"]!.eHist - v["random"]!.eHist)
        XCTAssertEqual(gap, 194.9430941564881, accuracy: 1e-6)
        XCTAssertLessThan(gap / TilingEnergy.omegaBits, 0.01)
        let picture = abs(v["balanced"]!.eHist - v["solid"]!.eHist)
        XCTAssertGreaterThan(picture / gap, 160)
        // E_wall separates the corner E cannot, by 19% of its range.
        XCTAssertGreaterThan((v["balanced"]!.eWall - v["random"]!.eWall)
                                / Double(TilingEnergy.bonds), 0.19)
    }

    /// ★ MT8, the load-bearing one: the front excludes grey AND static
    /// by DOMINATION, not by tuning.
    func testTheFrontExcludesGreyAndStatic() {
        let v = Dictionary(uniqueKeysWithValues: probeValues)
        XCTAssertTrue(TilingEnergy.dominates(v["face"]!, v["solid"]!))
        XCTAssertTrue(TilingEnergy.dominates(v["face"]!, v["neel"]!))
        XCTAssertTrue(TilingEnergy.dominates(v["face"]!, v["three"]!))
        XCTAssertTrue(TilingEnergy.dominates(v["balanced"]!, v["random"]!))
        XCTAssertFalse(TilingEnergy.dominates(v["face"]!, v["balanced"]!))
        XCTAssertFalse(TilingEnergy.dominates(v["balanced"]!, v["face"]!))

        let f = TilingEnergy.front(probeValues) { $0.1 }.map { $0.0 }
        XCTAssertEqual(Set(f), ["face", "balanced"])
    }

    /// MT11: the front only improves. Adding a dominated candidate
    /// never evicts a survivor, and never joins.
    func testTheFrontIsMonotone() {
        let before = Set(TilingEnergy.front(probeValues) { $0.1 }.map { $0.0 })
        let worse = ("worse", TilingEnergy.Value(eHist: 40000, eWall: 10))
        let after = Set(TilingEnergy.front(probeValues + [worse]) { $0.1 }.map { $0.0 })
        XCTAssertFalse(after.contains("worse"))
        XCTAssertTrue(before.isSubset(of: after))
    }

    /// MT9: the value is bounded, which is what PUCT needs, and it
    /// discriminates, which is what makes it worth computing.
    func testTheValueIsBoundedAndDiscriminates() {
        for (name, v) in probeValues {
            XCTAssertGreaterThanOrEqual(v.eHist, 0, name)
            XCTAssertLessThanOrEqual(v.eHist, TilingEnergy.omegaBits, name)
            XCTAssertGreaterThanOrEqual(v.eWall, 0, name)
            XCTAssertLessThanOrEqual(v.eWall, Double(TilingEnergy.bonds), name)
        }
        XCTAssertGreaterThan(Set(probeValues.map { $0.1.eHist }).count, 1)
    }
}
