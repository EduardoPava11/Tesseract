// Dissonance.swift
// Tesseract
//
// Swift port of spec/statistics/Dissonance.hs (authoritative; DS1–DS16
// green) — the Sethares/Plomp–Levelt kernel, the 4:5:6 octave chart's
// quadratic form, per-loop/per-slice tuning, and the depth→urgency
// bond field. Constants are the reference implementation's:
// b1 = 3.51 (NOT the video brief's 3.5), b2 = 5.75, x* = 0.24,
// s1 = 0.0207, s2 = 18.96.
//
// Daniel's rulings (2026-08-10): tuning reads at the ladder's rung-16
// cadence — 16 reads per loop at 5 Hz, 4 base frames each (TL8/TL9
// equivalence); URGENCY IS A WEIGHT (the color-weight slot), not a
// directional sign — this module computes the field, consumers treat
// it exactly like depth mass. Telemetry only in v1: no GIF byte
// depends on this module; the felt channel lands after device feel.

import Foundation

/// The dissonance kernel and the octave chart — pure, deterministic.
enum DissonanceKernel {

    // MARK: - §1 kernel (DS1–DS3)

    static let b1 = 3.51
    static let b2 = 5.75
    static let xStar = 0.24
    static let s1 = 0.0207
    static let s2 = 18.96

    /// The dimensionless shape: zero at 0 and ∞, one interior peak.
    static func g(_ x: Double) -> Double {
        exp(-b1 * x) - exp(-b2 * x)
    }

    /// Closed-form peak location: ln(b2/b1)/(b2−b1) ≈ 0.220350.
    static let xHat = log(b2 / b1) / (b2 - b1)

    /// Audio critical-band scaling: x = s(f_min)·Δf, CB = s1·f + s2.
    static func sOf(_ fMin: Double) -> Double {
        xStar / (s1 * fMin + s2)
    }

    /// Pair kernel d(p,q) = w₁w₂ · g(s(f_min)·Δf).
    static func dPair(f1: Double, w1: Double, f2: Double, w2: Double) -> Double {
        w1 * w2 * g(sOf(min(f1, f2)) * abs(f2 - f1))
    }

    // MARK: - §3 the 4:5:6 octave chart

    /// (m_R, m_G, m_B) — the just triad; R fundamental at P&L's 500 Hz.
    static let harmonics = [4, 5, 6]
    static let fFund = 125

    /// The 12 chart frequencies, channel-major: R{500,1k,2k,4k},
    /// G{625,1.25k,2.5k,5k}, B{750,1.5k,3k,6k}.
    static let freqs12: [Double] =
        harmonics.flatMap { m in (0...3).map { l in Double(m * fFund << l) } }

    /// The constant kernel matrix G (symmetric, zero diagonal, ≥ 0).
    static let gMat: [[Double]] = freqs12.map { fi in
        freqs12.map { fj in
            fi == fj ? 0 : g(sOf(min(fi, fj)) * abs(fj - fi))
        }
    }

    /// Loop dissonance as the quadratic form ½·aᵀG·a (DS8).
    static func quadD(_ a: [Double]) -> Double {
        0.5 * bilinX(a, a)
    }

    /// Cross-dissonance a₁ᵀG·a₂ — X_ear; polarization:
    /// D(T₁∪T₂) = D(T₁) + D(T₂) + X (DS9).
    static func bilinX(_ a: [Double], _ b: [Double]) -> Double {
        var total = 0.0
        for i in 0..<12 {
            var row = 0.0
            for j in 0..<12 { row += gMat[i][j] * b[j] }
            total += a[i] * row
        }
        return total
    }

    // MARK: - Tuning (guarded sequential detune; DS10-adjacent)

    /// 1/1200 octave = 0.3° of hue.
    static let gridN = 1200
    /// Hue-collapse guard: ≥ 1 semitone between comb pitch classes.
    static let guardGamma = 1.0 / 12.0

    static func beta(of k: Int) -> Double {
        pow(2, Double(k) / Double(gridN))
    }

    static func frac1(_ x: Double) -> Double { x - x.rounded(.down) }

    static func classAt(m: Int, k: Int) -> Double {
        frac1(log2(Double(m)) + Double(k) / Double(gridN))
    }

    static func circDist(_ p: Double, _ q: Double) -> Double {
        let dd = abs(frac1(p - q))
        return min(dd, 1 - dd)
    }

    /// One comb: harmonic m detuned by β, 4 octave partials.
    static func comb(m: Int, beta: Double, amps: [Double]) -> [(Double, Double)] {
        (0...3).map { l in (Double(m * fFund) * beta * Double(1 << l), amps[l]) }
    }

    static func crossTerm(_ ps: [(Double, Double)], _ qs: [(Double, Double)]) -> Double {
        var total = 0.0
        for p in ps { for q in qs { total += dPair(f1: p.0, w1: p.1, f2: q.0, w2: q.1) } }
        return total
    }

    /// Guarded argmin over interior local minima of the detune curve.
    /// Returns nil when every local minimum violates the pitch-class
    /// guard (audit note: the spec's total call sites are proven
    /// non-empty on witnesses; the port must not crash on real data —
    /// nil means "leave the comb untuned", k = 0).
    static func guardedArgmin(placedClasses: [Double], m: Int,
                              curve: [Double]) -> Int? {
        var best: (v: Double, k: Int)? = nil
        for k in 1..<(curve.count - 1) {          // interior only
            let v = curve[k]
            guard v < curve[k - 1], v < curve[k + 1] else { continue }
            let cls = classAt(m: m, k: k)
            guard placedClasses.allSatisfy({ circDist(cls, $0) >= guardGamma })
            else { continue }
            if best == nil || v < best!.v || (v == best!.v && k < best!.k) {
                best = (v, k)
            }
        }
        return best?.k
    }

    /// Per-read tuning (δG*, δB*) of the G and B combs against the
    /// occupancy 12-vector — Sethares scale design for color. The
    /// uniform-occupancy witness pins (269, 836) (spec §3).
    static func designTuning(amps12: [Double]) -> (kG: Int, kB: Int) {
        let aR = Array(amps12[0..<4])
        let aG = Array(amps12[4..<8])
        let aB = Array(amps12[8..<12])
        let rComb = comb(m: 4, beta: 1, amps: aR)
        let curveG = (0..<gridN).map { k in
            crossTerm(rComb, comb(m: 5, beta: beta(of: k), amps: aG))
        }
        let kG = guardedArgmin(placedClasses: [0], m: 5, curve: curveG) ?? 0
        let placed = rComb + comb(m: 5, beta: beta(of: kG), amps: aG)
        let curveB = (0..<gridN).map { k in
            crossTerm(placed, comb(m: 6, beta: beta(of: k), amps: aB))
        }
        let kB = guardedArgmin(placedClasses: [0, classAt(m: 5, k: kG)],
                               m: 6, curve: curveB) ?? 0
        return (kG, kB)
    }

    // MARK: - §4 temporal port: depth → urgency (zero tuned constants)

    /// σ(d) = σ_base·(2−d), σ_base = 63/8 (BinomialCadence, shipped).
    static let sigmaBase = 63.0 / 8.0

    /// Bond coordinate: x = x*·(σ_max/σ_min − 1). Near/far spans one
    /// exact octave, so full contrast lands at x = x* (DS12).
    static func xBond(_ dA: Double, _ dB: Double) -> Double {
        let dMin = min(dA, dB), dMax = max(dA, dB)
        return xStar * ((2 - dMin) / (2 - dMax) - 1)
    }

    /// Bond urgency: mass-weighted roughness of the cadence beat.
    static func urgencyBond(w1: Double, w2: Double,
                            dA: Double, dB: Double) -> Double {
        w1 * w2 * g(xBond(dA, dB))
    }
}

/// Per-burst dissonance telemetry — the tuning trace at the rung-16
/// cadence and the urgency field. URGENCY IS A WEIGHT (Daniel,
/// 2026-08-10): `voxelUrgency` fills the same conceptual slot as
/// depth mass; consumers may multiply it into stats weights exactly
/// as depths are today. Nothing here touches a GIF byte.
struct DissonanceTelemetry: Equatable {
    /// Whole-loop tuning of the G and B combs (1/1200-octave indices).
    let loopTuning: (kG: Int, kB: Int)
    /// One tuning per 20 cs slice — 16 reads per loop at 5 Hz
    /// (TL8/TL9: 64@20fps == 32@10×2 == 16@5×4).
    let sliceTunings: [(kG: Int, kB: Int)]
    /// Loop scalar Ū: total bond urgency over the 11776-bond torus.
    let urgencyTotal: Double
    /// Û envelope: per-slice urgency (temporal bonds charged to their
    /// source slice) — the loop's dramaturgy curve.
    let urgencyEnvelope: [Double]
    /// The 16³ per-voxel urgency field (slice-major, row-major) —
    /// the weight field, normalized mass in [0,1] per voxel.
    let voxelUrgency: [Double]

    static func == (l: DissonanceTelemetry, r: DissonanceTelemetry) -> Bool {
        l.loopTuning == r.loopTuning
            && l.sliceTunings.elementsEqual(r.sliceTunings, by: ==)
            && l.urgencyTotal == r.urgencyTotal
            && l.urgencyEnvelope == r.urgencyEnvelope
            && l.voxelUrgency == r.voxelUrgency
    }
}

enum DissonanceField {

    /// Occupancy 12-vector (channel-major, each channel's 4 level
    /// fractions) of a run of index frames — exact u64 counts, then
    /// one normalization. The index decomposes by the 4⁴ bijection.
    static func occupancy12(frames: ArraySlice<QuantizedFrame>) -> [Double] {
        var counts = [UInt64](repeating: 0, count: 12)   // a0..3 b0..3 c0..3
        var total: UInt64 = 0
        for frame in frames {
            for idx in frame.paletteIndices {
                let i = Int(idx)
                counts[(i % 64) / 16] &+= 1               // a (R)
                counts[4 + (i % 16) / 4] &+= 1            // b (G)
                counts[8 + i % 4] &+= 1                   // c (B)
                total &+= 1
            }
        }
        guard total > 0 else { return [Double](repeating: 0.25, count: 12) }
        return counts.map { Double($0) / Double(total) }
    }

    /// The full per-burst computation. nil unless the burst is 64³.
    static func telemetry(frames: [QuantizedFrame]) -> DissonanceTelemetry? {
        let side = 64, rung = 16, cell = side / rung      // 4×4 px × 4 frames
        guard frames.count == side else { return nil }
        let pixels = side * side
        for f in frames {
            if f.paletteIndices.count != pixels { return nil }
            if f.depths.count != pixels { return nil }
        }

        // Tuning: whole loop + one read per 20 cs slice (rung-16 cadence).
        let loopTuning = DissonanceKernel.designTuning(
            amps12: occupancy12(frames: frames[0...]))
        let sliceTunings = (0..<rung).map { t in
            DissonanceKernel.designTuning(
                amps12: occupancy12(frames: frames[(t * cell)..<((t + 1) * cell)]))
        }

        // Voxel depth means + normalized mass (Q16 lift, TL9 capacity).
        let voxels = rung * rung * rung
        var mass = [Double](repeating: 0, count: voxels)
        var depth = [Double](repeating: 0, count: voxels)
        let capacity = Double(64 * 65535)
        for t in 0..<rung {
            for f in 0..<cell {
                let d = frames[t * cell + f].depths
                for y in 0..<side {
                    for x in 0..<side {
                        let s = d[y * side + x]
                        let q = s.isNaN ? 0 : min(max(Double(s), 0), 1)
                        let v = t * rung * rung + (y / cell) * rung + (x / cell)
                        mass[v] += (q * 65536).rounded(.down).clamped(to: 0...65535)
                        depth[v] += q
                    }
                }
            }
        }
        for v in 0..<voxels {
            depth[v] /= Double(64)                        // 64 samples/voxel
            mass[v] /= capacity                           // normalized [0,1]
        }

        // Bonds: 4-neighbor spatial per slice + time-wrapped temporal
        // (the NETSCAPE loop closes time into a torus) — 11776 total.
        var envelope = [Double](repeating: 0, count: rung)
        var voxelU = [Double](repeating: 0, count: voxels)
        func addBond(_ a: Int, _ b: Int, slice: Int) {
            let u = DissonanceKernel.urgencyBond(w1: mass[a], w2: mass[b],
                                                 dA: depth[a], dB: depth[b])
            envelope[slice] += u
            voxelU[a] += u / 2
            voxelU[b] += u / 2
        }
        for t in 0..<rung {
            for y in 0..<rung {
                for x in 0..<rung {
                    let v = t * rung * rung + y * rung + x
                    if x + 1 < rung { addBond(v, v + 1, slice: t) }
                    if y + 1 < rung { addBond(v, v + rung, slice: t) }
                    let tNext = ((t + 1) % rung) * rung * rung + y * rung + x
                    addBond(v, tNext, slice: t)
                }
            }
        }

        return DissonanceTelemetry(
            loopTuning: loopTuning,
            sliceTunings: sliceTunings,
            urgencyTotal: envelope.reduce(0, +),
            urgencyEnvelope: envelope,
            voxelUrgency: voxelU
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
