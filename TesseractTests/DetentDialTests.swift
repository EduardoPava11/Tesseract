// DetentDialTests.swift
// Tesseract
//
// Swift mirrors of spec/ui/DetentDial.hs (DD1–DD10). The Haskell is
// authoritative; these tests hold the PORT to it — the spec's own
// fixtures are replayed value for value (DD3's jitter and out-and-back
// paths, DD2's 0.25° sweep), and every derived count is re-measured
// against its source law rather than compared to a written number.
//
// Double-vs-Rational parity is EXACT here: every boundary angle a
// shipping dial can produce is 360/k for k ∈ {3, 8, 12, 16} — 120, 45,
// 30, 22.5 — all exactly representable in binary, and the sweep steps
// 0.25° which is exact too. No epsilon is needed for the circle laws.
//
// Pure logic — runs on the simulator.

import XCTest
@testable import Tesseract

final class DetentDialTests: XCTestCase {

    private let allLaws = DialLaw.allCases

    // MARK: - DD1: detent counts are DERIVED, never written

    func testDD1_countsAreDerived() {
        // Each equals a FRESH measurement of its source law's own data.
        XCTAssertEqual(DialLaw.allocation.detents, [DyadPalette.ladder.count])
        XCTAssertEqual(DialLaw.rungPick.detents, [Rung.allCases.count])
        XCTAssertEqual(DialLaw.roleSplit.detents,
                       [RoleAlloc.figureBits + RoleAlloc.groundBits + 1])
        XCTAssertEqual(DialLaw.colourDisc.detents,
                       [Rung.allCases.map(\.side).min()!, DyadPalette.ladder.count])
        for law in allLaws {
            XCTAssertTrue(law.detents.allSatisfy { $0 > 0 },
                          "\(law.rawValue): every count positive")
        }
    }

    func testDD1_roleAllocIsAConsequence() {
        // (7,4) is DERIVED: 2^7 = the palette's figure half, and the
        // ground stratum sits `cubeAxes` generations above the leaves
        // because one κ step pools 2×2×2.
        XCTAssertEqual(RoleAlloc.figureBits, Int(log2(Double(DyadPalette.primaryCount))))
        XCTAssertEqual(1 << RoleAlloc.figureBits, DyadPalette.primaryCount)
        XCTAssertEqual(RoleAlloc.cubeAxes, Int(log2(Double(Rung.fine.cells / Rung.mid.cells))))
        XCTAssertEqual(Rung.fine.cells / Rung.mid.cells, 1 << RoleAlloc.cubeAxes)
        XCTAssertEqual(RoleAlloc.groundBits, RoleAlloc.figureBits - RoleAlloc.cubeAxes)
        XCTAssertEqual(RoleAlloc.totalBits, RoleAlloc.figureBits + RoleAlloc.groundBits)
    }

    // MARK: - DD2: totality

    func testDD2_totality() {
        for law in allLaws {
            for k in law.detents {
                // The spec's sweep: 1440 samples at 0.25°.
                let sweep = (0..<1440).map { Double($0) / 4 }
                let idx = sweep.map { DetentDial.detentAt(k: k, angle: $0) }
                XCTAssertTrue(idx.allSatisfy { $0 >= 0 && $0 < k },
                              "\(law.rawValue) k=\(k): every angle lands in a detent")
                XCTAssertEqual(Set(idx).sorted(), Array(0..<k),
                               "\(law.rawValue) k=\(k): every detent reachable")
            }
        }
    }

    func testDD2_theCircleIsTotalBeyondOneTurn() {
        // Winding past the turn wraps; a negative angle is the same
        // detent as its positive turn (the port's ℤ_k, not the spec's
        // [0,360) restriction — a finger can wind either way).
        let k = DialLaw.allocation.detents[0]
        for i in 0..<k {
            let a = DetentDial.snapAngle(k: k, index: i)
            XCTAssertEqual(DetentDial.detentAt(k: k, angle: a + 360), i)
            XCTAssertEqual(DetentDial.detentAt(k: k, angle: a - 360), i)
            XCTAssertEqual(DetentDial.detentAt(k: k, angle: a + 720), i)
        }
    }

    // MARK: - DD3: a tick is a CROSSING, not a touch sample

    /// The spec's fixtures, value for value.
    private var arc: Double { 360.0 / Double(DialLaw.allocation.detents[0]) }   // 45°
    private var jitterInsideOneArc: [Double] { (1...40).map { arc * Double($0) / 100 } }
    private var outAndBack: [Double] { [arc / 4, arc / 2, arc * 3 / 2, arc / 2, arc / 4] }

    func testDD3_tickIsACrossing() {
        let k = DialLaw.allocation.detents[0]
        XCTAssertEqual(DetentDial.ticks(k: k, path: jitterInsideOneArc), 0,
                       "40 samples inside one arc emit NOTHING")
        XCTAssertEqual(DetentDial.ticks(k: k, path: outAndBack), 2,
                       "out and back is exactly two crossings")
        XCTAssertEqual(DetentDial.detentAt(k: k, angle: outAndBack.first!),
                       DetentDial.detentAt(k: k, angle: outAndBack.last!),
                       "the path returns where it began")
    }

    func testDD3_trackerEmitsOnlyOnChange() {
        let k = DialLaw.allocation.detents[0]
        var t = DialTracker(k: k, index: 0)
        var emitted = 0
        for a in jitterInsideOneArc where t.sample(angle: a) { emitted += 1 }
        XCTAssertEqual(emitted, 0, "a 120 Hz drag inside one arc costs nothing (DD6)")
        XCTAssertEqual(t.index, 0)

        var t2 = DialTracker(k: k, index: DetentDial.detentAt(k: k, angle: outAndBack[0]))
        var crossings = 0
        for a in outAndBack where t2.sample(angle: a) { crossings += 1 }
        XCTAssertEqual(crossings, 2)
        XCTAssertEqual(t2.index, DetentDial.detentAt(k: k, angle: outAndBack.last!))
    }

    func testDD3_radialTrackerAlsoTicksOnCrossingOnly() {
        // The colour disc's second axis obeys the same law.
        let k = DialLaw.colourDisc.detents[1]
        var t = DialTracker(k: k, index: 0)
        let band = 1.0 / Double(k)
        var emitted = 0
        for n in 1...40 where t.sample(radiusFraction: band * Double(n) / 100) { emitted += 1 }
        XCTAssertEqual(emitted, 0, "wandering inside one ring emits nothing")
        XCTAssertTrue(t.sample(radiusFraction: band * 1.5), "leaving the ring is a tick")
        XCTAssertEqual(t.index, 1)
    }

    // MARK: - DD4: a dial is big enough for its own law

    func testDD4_radiusLaw() {
        for law in allLaws {
            let r = law.minRadiusCells
            XCTAssertGreaterThan(r, 0, "\(law.rawValue): radius positive")
            XCTAssertLessThanOrEqual(2 * r, Double(TesseractLattice.cols),
                                     "\(law.rawValue): the dial fits the canvas width")
            // The law itself: k arcs of ≥ one touch floor each.
            XCTAssertEqual(r,
                           Double(law.maxDetents * TesseractLattice.touchFloorCells) / DetentDial.tauLower,
                           accuracy: 1e-12)
            // Every arc really does clear the floor at that radius
            // (τ > tauLower, so the true circumference is larger still).
            let circumference = DetentDial.tauLower * r
            XCTAssertGreaterThanOrEqual(circumference / Double(law.maxDetents),
                                        Double(TesseractLattice.touchFloorCells) - 1e-9,
                                        "\(law.rawValue): each detent clears the touch floor")
        }
    }

    func testDD4_tauLowerIsAStrictLowerBound() {
        XCTAssertLessThan(DetentDial.tauLower, 2 * Double.pi,
                          "tauLower must UNDER-state τ so the radius law over-sizes")
        XCTAssertGreaterThan(DetentDial.tauLower, 2 * Double.pi - 0.01,
                             "…but stay tight enough to be useful")
    }

    func testDD4_footprintsAreLawful() {
        for law in allLaws {
            let side = law.sideCells
            XCTAssertGreaterThanOrEqual(side, TesseractLattice.touchFloorCells,
                                        "\(law.rawValue): a dial is itself a control (WG9)")
            XCTAssertGreaterThanOrEqual(Double(side), 2 * law.minRadiusCells,
                                        "\(law.rawValue): the footprint holds the law's diameter")
            XCTAssertEqual(side % 2, 0, "\(law.rawValue): even side ⇒ symmetric about its centre")
            XCTAssertLessThanOrEqual(side, TesseractLattice.cols,
                                     "\(law.rawValue): fits the 100-cell canvas width")
        }
        // The derived table, pinned: a change to any source law moves
        // these, and that is the point of pinning them here.
        XCTAssertEqual(DialLaw.rungPick.sideCells, 12)
        XCTAssertEqual(DialLaw.allocation.sideCells, 30)
        XCTAssertEqual(DialLaw.roleSplit.sideCells, 44)
        XCTAssertEqual(DialLaw.colourDisc.sideCells, 58)
    }

    // MARK: - DD5: the rung ladder IS the interaction ladder

    func testDD5_ladder() {
        let phases: [DialGesture] = [.dragging, .crossed, .released]
        let sides = phases.map(\.rung.side)
        XCTAssertEqual(sides, Rung.allCases.map(\.side).sorted(),
                       "the three phases ARE the three rungs")
        XCTAssertEqual(sides, sides.sorted(), "coarse → fine")
        XCTAssertLessThan(sides[0], sides[1])
        XCTAssertLessThan(sides[1], sides[2])
        // The division is the point: it makes the coarse render a
        // PREFIX of the fine one, never a different picture (OV13).
        XCTAssertEqual(sides[1] % sides[0], 0)
        XCTAssertEqual(sides[2] % sides[1], 0)
        XCTAssertEqual(Set(DialGesture.allCases.map(\.rung)).count, Rung.allCases.count,
                       "the map onto the rungs is a bijection")
    }

    func testDD5_rungPickIndexesTheSameLadder() {
        let ladder = DetentDial.rungLadder
        XCTAssertEqual(ladder.map(\.side), Rung.allCases.map(\.side).sorted())
        XCTAssertEqual(DialLaw.rungPick.detents[0], ladder.count)
        for i in 0..<ladder.count {
            let v = DialValue(law: .rungPick, indices: [i])
            XCTAssertEqual(v.rung, ladder[i], "detent \(i) names rung \(ladder[i].side)")
        }
        XCTAssertNil(DialValue(law: .allocation).rung, "only rungPick names a rung")
    }

    // MARK: - DD6: the detent pays for itself

    func testDD6_detentPaysForItself() {
        for law in allLaws {
            XCTAssertLessThan(DetentDial.costDetented(law), DetentDial.costContinuous,
                              "\(law.rawValue): detented is cheaper")
            XCTAssertLessThan(DetentDial.costDetented(law) * 10, DetentDial.costContinuous,
                              "\(law.rawValue): …and by more than 10×")
        }
        // Work is voxels, and the continuous knob is the full cube on
        // every one of ProMotion's samples.
        XCTAssertEqual(DetentDial.cost(side: Rung.fine.side), Rung.fine.cells)
        XCTAssertEqual(DetentDial.costContinuous,
                       DetentDial.touchSamplesPerSweep * Rung.fine.cells)
    }

    // MARK: - DD7: only colour is 2-DOF

    func testDD7_degreesOfFreedom() {
        XCTAssertEqual(allLaws.filter { $0.dof == 2 }, [.colourDisc],
                       "a knob cannot express a plane — exactly one dial does")
        for law in [DialLaw.allocation, .rungPick, .roleSplit] {
            XCTAssertEqual(law.dof, 1, "\(law.rawValue) is an angle alone")
        }
        for law in allLaws {
            XCTAssertGreaterThanOrEqual(law.dof, 1)
            XCTAssertEqual(law.dof, law.detents.count)
        }
    }

    // MARK: - DD8: the disc IS the palette in polar form

    func testDD8_discIsThePalette() {
        let floor = Rung.allCases.map(\.side).min()!
        XCTAssertEqual(DialLaw.colourDisc.positions, 128)
        XCTAssertEqual(DialLaw.colourDisc.positions * 2, floor * floor,
                       "the σ mirror completes the disc to the whole table")
        XCTAssertEqual(floor * floor, 2 * DyadPalette.primaryCount,
                       "256 = the bijection = both halves")
        // Neither axis was chosen: hue is the floor rung, chroma is the
        // balanced pairs. Their product being 128 is a CONSEQUENCE.
        XCTAssertEqual(DialLaw.colourDisc.detents[0], floor)
        XCTAssertEqual(DialLaw.colourDisc.detents[1], DyadPalette.ladder.count)
        XCTAssertEqual(DialLaw.colourDisc.detents.reduce(1, *), DyadPalette.primaryCount)
    }

    // MARK: - DD9: detents form ℤ_k — returnable by feel

    func testDD9_cyclic() {
        for law in allLaws {
            for k in law.detents {
                for i in 0..<k {
                    // A full turn is the identity from ANY origin.
                    var j = i
                    for _ in 0..<k { j = (j + 1) % k }
                    XCTAssertEqual(j, i, "k=\(k): k steps return to \(i)")
                    // And a snap lands in its own detent.
                    XCTAssertEqual(DetentDial.detentAt(k: k, angle: DetentDial.snapAngle(k: k, index: i)), i)
                }
            }
        }
    }

    func testDD9_valueStepsWrapOnEveryAxis() {
        for law in allLaws {
            for axis in 0..<law.dof {
                let k = law.detents[axis]
                for origin in 0..<k {
                    var v = DialValue(law: law, indices: (0..<law.dof).map { $0 == axis ? origin : 0 })
                    for _ in 0..<k { v = v.stepped(axis: axis, by: 1) }
                    XCTAssertEqual(v.index(axis: axis), origin,
                                   "\(law.rawValue) axis \(axis): k steps is the identity")
                    XCTAssertEqual(v.stepped(axis: axis, by: -1).index(axis: axis),
                                   (origin + k - 1) % k, "backwards wraps too")
                }
            }
        }
    }

    func testDD9_outOfRangeIsUnrepresentable() {
        let k = DialLaw.roleSplit.detents[0]
        XCTAssertEqual(DialValue(law: .roleSplit, indices: [k]).index(axis: 0), 0)
        XCTAssertEqual(DialValue(law: .roleSplit, indices: [-1]).index(axis: 0), k - 1)
        XCTAssertEqual(DialValue(law: .roleSplit, indices: [3 * k + 2]).index(axis: 0), 2)
        // Missing / extra axes are absorbed, never stored.
        XCTAssertEqual(DialValue(law: .colourDisc, indices: []).indices.count, 2)
        XCTAssertEqual(DialValue(law: .rungPick, indices: [1, 9, 9]).indices.count, 1)
        XCTAssertEqual(DialTracker(k: k, index: -1).index, k - 1)
    }

    // MARK: - DD10: NO DRIFT — the source laws still have this shape

    func testDD10_noDrift() {
        // AttractorRAG's ladder: eight BALANCED pairs.
        XCTAssertEqual(DyadPalette.ladder.count, 8)
        XCTAssertEqual(Array(DyadPalette.ladder.prefix(2)), [1, 1])
        // Octave's rungs: three, stated coarse to fine, floor 16 (the
        // bijection), ceiling 64 (the only integer-delay cap).
        XCTAssertEqual(Rung.allCases.map(\.side).sorted(), [16, 32, 64])
        XCTAssertEqual(Rung.allCases.map(\.side).min(), 16)
        XCTAssertEqual(Rung.allCases.map(\.side).max(), 64)
        // RoleAllocation: 11 bits, figure outranking ground.
        XCTAssertEqual(RoleAlloc.figureBits + RoleAlloc.groundBits, 11)
        XCTAssertGreaterThan(RoleAlloc.figureBits, RoleAlloc.groundBits)
        // WidgetGrid WG9: the atom is 4 pt, so 44 pt is 11 cells.
        XCTAssertEqual(TesseractLattice.touchFloorCells, 11)
        XCTAssertEqual(TesseractLattice.touchFloorCells * TesseractLattice.gifPx, 44)
        // ProMotion, the hardware fact the cost proof rests on.
        XCTAssertEqual(DetentDial.touchSamplesPerSweep, 120)
    }

    // MARK: - Port-only laws (the spec cannot state these)

    func testTouchPointsEnterTheCircleClockwiseFromTop() {
        // The gesture's angle convention IS CellGeom.turn's drawing
        // convention, so ink and finger agree by construction.
        let side = DialLaw.allocation.sideCells
        let c = Lattice.gif(side) / 2
        let cases: [(CGPoint, Double)] = [
            (CGPoint(x: c, y: 0), 0),
            (CGPoint(x: Lattice.gif(side), y: c), 90),
            (CGPoint(x: c, y: Lattice.gif(side)), 180),
            (CGPoint(x: 0, y: c), 270),
        ]
        for (p, deg) in cases {
            XCTAssertEqual(DetentDial.angle(at: p, sideCells: side), deg, accuracy: 1e-9)
        }
        XCTAssertEqual(DetentDial.radiusFraction(at: CGPoint(x: c, y: c), sideCells: side),
                       0, accuracy: 1e-12)
        XCTAssertEqual(DetentDial.radiusFraction(at: CGPoint(x: c, y: 0), sideCells: side),
                       1, accuracy: 1e-12)
        // Past the rim the radial axis saturates rather than escaping.
        XCTAssertEqual(DetentDial.ringAt(k: DialLaw.colourDisc.detents[1], radiusFraction: 4.0),
                       DialLaw.colourDisc.detents[1] - 1)
        XCTAssertEqual(DetentDial.ringAt(k: DialLaw.colourDisc.detents[1], radiusFraction: -1),
                       0)
    }

    func testTheAngularAxisAgreesWithTheRasterConvention() {
        // A touch at a detent's snap angle lands in that detent, at
        // every radius — the sprite reads the same function.
        let law = DialLaw.roleSplit
        let k = law.detents[0]
        let side = law.sideCells
        let c = Double(Lattice.gif(side) / 2)
        for i in 0..<k {
            // Aim at the MIDDLE of the arc: boundaries are shared by
            // construction, arc centres are not.
            let deg = DetentDial.snapAngle(k: k, index: i) + 360 / Double(k) / 2
            let rad = deg / 360 * 2 * Double.pi
            let p = CGPoint(x: c + sin(rad) * c / 2, y: c - cos(rad) * c / 2)
            XCTAssertEqual(DetentDial.detentAt(k: k, angle: DetentDial.angle(at: p, sideCells: side)), i)
        }
    }

    func testReadoutSpeaksTheDialsWord() {
        XCTAssertEqual(DialValue(law: .rungPick, indices: [1]).readout, "RUNG 2/3")
        XCTAssertEqual(DialValue(law: .colourDisc, indices: [0, 7]).readout, "COLOUR 1/16 8/8")
        for law in allLaws {
            XCTAssertTrue(law.word.allSatisfy { $0.isUppercase },
                          "\(law.rawValue): square words are uppercase (SM1)")
        }
    }

    func testValueRoundTripsAsData() throws {
        let v = DialValue(law: .colourDisc, indices: [5, 3])
        let data = try JSONEncoder().encode(v)
        XCTAssertEqual(try JSONDecoder().decode(DialValue.self, from: data), v)
        XCTAssertNotEqual(v, v.stepped(axis: 1, by: 1))
    }

    func testSelfCheckHoldsAtLaunch() {
        // The DEBUG launch assertions must not trip.
        DetentDial.selfCheck()
    }
}
