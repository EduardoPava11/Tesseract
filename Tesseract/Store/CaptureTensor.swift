// CaptureTensor.swift
// Tesseract
//
// ★ THE RETAINED TENSOR (Daniel's specification 2026-08-14, "what we
// capture should be a proprietary tensor; the shape is the form, the
// function is the app's sole purpose"), and its ENCODE, which runs on
// the Neural Engine (Daniel, same day: "I need ANE to be able to
// encode+compress the signal information").
//
// Laws: spec/output/CaptureTensor.hs CT1–CT11 owns the bytes;
// spec/neural/TensorEncoder.hs TA1–TA9 owns the engine placement;
// Octave.hs owns the ladder, FeedCompression.hs the wire format,
// OctaveCodec.hs the wired codec. Nothing is re-derived here.
//
// ── WHAT THIS FILE IS TO CubeStore ──────────────────────────────
//
// CubeStore keeps 8-bit sRGB + f32 depth per voxel: 1,835,024 B, no
// transform, no compression. It is the format CR1 shipped with, and
// the tensor REPLACES it by ruling. This file is that replacement;
// the swap of the call sites is staged so CR3 (identity re-weave
// reproduces the archived GIF byte for byte) can be proved on the
// tensor before anything stops writing the cube.
//
// ── THE FORM ────────────────────────────────────────────────────
//
//   header    16 B   magic, frames, side, flags
//   depth   1.00 MiB f32, FINE RUNG ONLY. κ is exact (Octave OV),
//                    so the coarse depth rungs are a pure function of
//                    this one; storing all three would be storing the
//                    same numbers three times. Never quantised (CT6).
//   l16      24 KiB  the coarse picture, 3 × fp16 per cell. This is
//                    the rung whose 256 cells per tick ARE the 256
//                    centroids, and fp16 spends 48 of the 64 bits CT2
//                    had already forced — so the engine's native
//                    precision costs the palette nothing (TA5).
//   sig     1.5 KiB  ONE significance bit per (rung-16 cell, channel).
//                    A quiet root terminates 8 + 64 descendants with
//                    that single symbol (CT8, the zerotree).
//   loud   variable  per loud root: g32, g64 (fp16), then 8 + 64
//                    sign bits.
//
// ★ WHY g IS STORED RATHER THAN PREDICTED. CT4 leaves g a parameter
// and CT10 says a predictor for it reads the parent and the previous
// tick; that predictor is trained in nn/jepa. Storing the subtree's
// OWN measured deviation instead costs 4 B per loud root and buys two
// things worth more than those bytes: the decode needs no trained
// weights, so a tensor retained today is still decodable after any
// future retrain; and the app introduces no naked k and j while the
// predictor does not yet exist. A trained predictor becomes format
// v2, never a second runtime path.

import Foundation

enum CaptureTensor {

    static let magic = "TSRTENS1"
    static let headerBytes = 16

    /// Rungs, cited from Octave OV1 / FeedCompression FC1.
    static let fineFrames = 64
    static let fineSide = 64
    static let channels = 3

    /// CT8: a rung-16 root owns 8 rung-32 children and 64 rung-64
    /// descendants. Not a choice — the 2×2×2 atom, twice.
    static let children32 = 8
    static let children64 = 64

    // MARK: - Levels

    /// One rung of the ladder. Interleaved by channel so the layout
    /// matches the engine's NCHW-with-frames-as-batch view after a
    /// single transpose, and so pooling touches contiguous memory.
    struct Level {
        var frames: Int
        var side: Int
        var data: [Float]          // ((t*side + y)*side + x)*3 + c

        var cells: Int { frames * side * side }

        init(frames: Int, side: Int, data: [Float]) {
            self.frames = frames; self.side = side; self.data = data
        }

        init(frames: Int, side: Int, repeating v: Float = 0) {
            self.init(frames: frames, side: side,
                      data: [Float](repeating: v,
                                    count: frames * side * side * 3))
        }

        @inline(__always)
        func at(_ t: Int, _ y: Int, _ x: Int, _ c: Int) -> Float {
            data[((t * side + y) * side + x) * 3 + c]
        }

        @inline(__always)
        mutating func set(_ t: Int, _ y: Int, _ x: Int, _ c: Int, _ v: Float) {
            data[((t * side + y) * side + x) * 3 + c] = v
        }
    }

    /// One octave down: the 2×2×2 spacetime mean. This is κ, and it
    /// is NOT new here — `Octave.hs` already owns it: OV4 gates
    /// `pool ∘ up = id` and that all three reads share one mean, and
    /// OV12 gates that the 2×2×2 atom IS three composed 2 → 1 means.
    /// `SKGeneCalculus.hs` SK6 proves the same retraction on the Haar
    /// octave (`K̂ ∘ Ŝ = id`), and `OctaveCodec.hs` CX1 proves a
    /// strictly stronger form, `κ(σ_g(x)) = x` for ANY g.
    ///
    /// TA1 adds only the part those files do not say: that this mean
    /// FACTORS into a temporal pair-average and a spatial 2×2 which
    /// commute, which is what lets the ANE graph run it as conv +
    /// avg_pool, and why the twin here can be written the simple way.
    static func poolDown(_ l: Level) -> Level {
        var out = Level(frames: l.frames / 2, side: l.side / 2)
        for t in 0..<out.frames {
            for y in 0..<out.side {
                for x in 0..<out.side {
                    for c in 0..<3 {
                        var s: Float = 0
                        for dt in 0..<2 {
                            for dy in 0..<2 {
                                for dx in 0..<2 {
                                    s += l.at(2 * t + dt, 2 * y + dy,
                                              2 * x + dx, c)
                                }
                            }
                        }
                        out.set(t, y, x, c, s / 8)
                    }
                }
            }
        }
        return out
    }

    /// The child's parent: nearest, ×2 in all three axes (CT4). This
    /// is σ's STRUCTURAL half, replication, in `Octave.hs`'s own
    /// words. ★ It is not the whole of σ: the stored tensor's free
    /// sign bit is exactly the part that does NOT retract, which is
    /// CT1's split. So `parentUp` may be read as σ, and
    /// `parentUp ∘ poolDown` may NOT — CT11 bounds the difference.
    static func parentUp(_ l: Level) -> Level {
        var out = Level(frames: l.frames * 2, side: l.side * 2)
        for t in 0..<out.frames {
            for y in 0..<out.side {
                for x in 0..<out.side {
                    for c in 0..<3 {
                        out.set(t, y, x, c, l.at(t / 2, y / 2, x / 2, c))
                    }
                }
            }
        }
        return out
    }

    static func residual(_ fine: Level, _ parent: Level) -> Level {
        var out = fine
        for i in 0..<out.data.count { out.data[i] -= parent.data[i] }
        return out
    }

    static func magnitude(_ l: Level) -> Level {
        var out = l
        for i in 0..<out.data.count { out.data[i] = abs(out.data[i]) }
        return out
    }

    // MARK: - The transform (the CPU twin of the ANE graph)

    /// EXACTLY what the ANE graph emits, and exactly what the format
    /// stores. The signs are the stored decision; g32 and g64 are the
    /// stored step sizes, both landing on the rung-16 grid because a
    /// zerotree ROOT is what owns them (CT8).
    struct Transform {
        var l16: Level          // the coarse picture = the 256 centroids
        var sign32: [Bool]      // rung-32 grid, ((t*32+y)*32+x)*3 + c
        var sign64: [Bool]      // rung-64 grid
        var g32: Level          // 16-grid: mean |r32| over the root's 8
        var g64: Level          // 16-grid: mean |r64| over the root's 64
        var dev16: Level        // (8·g32 + 64·g64)/72 — CT7's statistic
    }

    /// CT7's statistic from the two step sizes. The mean deviation
    /// over all 72 descendants a root owns: their COUNTS are the
    /// weights, so there is no constant to choose.
    static func deviation(g32: Level, g64: Level) -> Level {
        var out = g32
        let wN = Float(children32), wF = Float(children64)
        let total = wN + wF
        for i in 0..<out.data.count {
            out.data[i] = (wN * g32.data[i] + wF * g64.data[i]) / total
        }
        return out
    }

    /// Everything the encoder needs, in the order the graph computes
    /// it. TensorANE.transform is the engine twin of exactly this.
    static func transform(_ fine: Level) -> Transform {
        let l32 = poolDown(fine)
        let l16 = poolDown(l32)
        let r64 = residual(fine, parentUp(l32))
        let r32 = residual(l32, parentUp(l16))

        let g32 = poolDown(magnitude(r32))
        let g64 = poolDown(poolDown(magnitude(r64)))
        return Transform(l16: l16,
                         sign32: r32.data.map { $0 >= 0 },
                         sign64: r64.data.map { $0 >= 0 },
                         g32: g32, g64: g64,
                         dev16: deviation(g32: g32, g64: g64))
    }

    // MARK: - The derived threshold (CT7)

    /// ★ NO CHOSEN CONSTANT. The significance threshold is the
    /// crossover of a two-phase tied-variance mixture fitted to the
    /// capture's OWN subtree deviations — the same fitter, verbatim,
    /// that splits figure from ground (`DepthMixture`), applied to
    /// log-deviations because deviations are positive and their
    /// spread is multiplicative.
    ///
    /// A capture with no quiet population returns nil, and CT7 says
    /// that capture pays flat. That is the mixture's VERDICT, a branch
    /// of the law, not a degraded path: the encoder writes every sign
    /// because the data said every subtree speaks.
    static func significanceThreshold(_ dev16: Level) -> Float? {
        let logs = dev16.data.map { Double(Swift.max($0, 1e-12)) }.map(log)
        let fit = DepthMixture.fit(logs)
        guard !fit.isDegenerate, DepthMixture.isTwoPhase(logs, fit: fit)
        else { return nil }
        return Float(exp(fit.crossover))
    }

    // MARK: - Encode

    /// The 8 rung-32 children of a rung-16 root, in stored order.
    static func children32Of(_ t: Int, _ y: Int, _ x: Int) -> [(Int, Int, Int)] {
        var out: [(Int, Int, Int)] = []
        out.reserveCapacity(8)
        for dt in 0..<2 { for dy in 0..<2 { for dx in 0..<2 {
            out.append((2 * t + dt, 2 * y + dy, 2 * x + dx))
        } } }
        return out
    }

    /// The 64 rung-64 descendants of a rung-16 root, in stored order.
    static func children64Of(_ t: Int, _ y: Int, _ x: Int) -> [(Int, Int, Int)] {
        var out: [(Int, Int, Int)] = []
        out.reserveCapacity(64)
        for dt in 0..<4 { for dy in 0..<4 { for dx in 0..<4 {
            out.append((4 * t + dt, 4 * y + dy, 4 * x + dx))
        } } }
        return out
    }

    static func encode(colour: Level, depths: [[Float]]) -> Data? {
        guard colour.frames == fineFrames, colour.side == fineSide,
              depths.count == fineFrames,
              depths.allSatisfy({ $0.count == fineSide * fineSide })
        else { return nil }

        let tr = transform(colour)
        let threshold = significanceThreshold(tr.dev16)

        var out = Data(capacity: 1_100_000)
        out.append(contentsOf: Array(magic.utf8))
        appendLE(&out, UInt16(fineFrames))
        appendLE(&out, UInt16(fineSide))
        appendLE(&out, UInt16(threshold == nil ? 1 : 0))   // flags: bit0 = flat
        appendLE(&out, UInt16(0))

        // depth, fine rung only: the coarse rungs are κ-derivable.
        for frame in depths {
            for d in frame { appendLE(&out, d.bitPattern) }
        }

        // the coarse picture, fp16 (TA5)
        for v in tr.l16.data { appendLE(&out, Float16(v).bitPattern) }

        // significance + the loud roots' payloads
        var sig = BitWriter()
        var loud = BitWriter()
        let g16 = tr.dev16
        for t in 0..<g16.frames {
            for y in 0..<g16.side {
                for x in 0..<g16.side {
                    for c in 0..<3 {
                        let isLoud = threshold.map { g16.at(t, y, x, c) >= $0 }
                            ?? true
                        sig.write(isLoud)
                        guard isLoud else { continue }
                        writeSubtree(&loud, tr, t, y, x, c)
                    }
                }
            }
        }
        out.append(sig.finish())
        out.append(loud.finish())
        return out
    }

    private static func writeSubtree(_ w: inout BitWriter, _ tr: Transform,
                                     _ t: Int, _ y: Int, _ x: Int, _ c: Int) {
        w.writeBits(Float16(tr.g32.at(t, y, x, c)).bitPattern, count: 16)
        w.writeBits(Float16(tr.g64.at(t, y, x, c)).bitPattern, count: 16)
        for (a, b, d) in children32Of(t, y, x) {
            w.write(tr.sign32[((a * 32 + b) * 32 + d) * 3 + c])
        }
        for (a, b, d) in children64Of(t, y, x) {
            w.write(tr.sign64[((a * 64 + b) * 64 + d) * 3 + c])
        }
    }

    // MARK: - Decode

    struct Decoded {
        var colour: Level
        var depths: [[Float]]
    }

    /// The decode law, CT4 and CT9 exactly: child = parent + sign·g,
    /// and a quiet subtree is g = 0 — the SAME arithmetic, never a
    /// second reconstruction path.
    static func decode(_ data: Data) -> Decoded? {
        guard data.count > headerBytes,
              data.prefix(8).elementsEqual(magic.utf8) else { return nil }
        var p = data.startIndex + 8
        let frames = Int(readLE16(data, &p))
        let side = Int(readLE16(data, &p))
        _ = readLE16(data, &p)                       // flags
        _ = readLE16(data, &p)
        guard frames == fineFrames, side == fineSide else { return nil }

        let px = side * side
        var depths: [[Float]] = []
        depths.reserveCapacity(frames)
        for _ in 0..<frames {
            var f = [Float](); f.reserveCapacity(px)
            for _ in 0..<px { f.append(Float(bitPattern: readLE32(data, &p))) }
            depths.append(f)
        }

        var l16 = Level(frames: 16, side: 16)
        for i in 0..<l16.data.count {
            l16.data[i] = Float(Float16(bitPattern: readLE16(data, &p)))
        }

        let roots = 16 * 16 * 16 * 3
        let sigBytes = (roots + 7) / 8
        guard p + sigBytes <= data.endIndex else { return nil }
        var sig = BitReader(data, from: p)
        p += sigBytes
        var loud = BitReader(data, from: p)

        // A quiet subtree is g = 0 (CT9), so the levels START at the
        // parent and only loud roots write over them. That is the
        // decode law itself doing the silence, not a second path.
        var l32 = parentUp(l16)
        var pending: [(Int, Int, Int, Int, Float, [Bool])] = []

        for t in 0..<16 {
            for y in 0..<16 {
                for x in 0..<16 {
                    for c in 0..<3 {
                        guard sig.read() else { continue }
                        let g32 = Float(Float16(
                            bitPattern: loud.readBits(16)))
                        let g64 = Float(Float16(
                            bitPattern: loud.readBits(16)))
                        var s32 = [Bool](); s32.reserveCapacity(8)
                        for _ in 0..<children32 { s32.append(loud.read()) }
                        var s64 = [Bool](); s64.reserveCapacity(64)
                        for _ in 0..<children64 { s64.append(loud.read()) }
                        for (i, (a, b, d)) in children32Of(t, y, x).enumerated() {
                            let parent = l16.at(t, y, x, c)
                            l32.set(a, b, d, c,
                                    parent + (s32[i] ? g32 : -g32))
                        }
                        pending.append((t, y, x, c, g64, s64))
                    }
                }
            }
        }
        var fine = parentUp(l32)
        for (t, y, x, c, g64, s64) in pending {
            for (i, (a, b, d)) in children64Of(t, y, x).enumerated() {
                let parent = l32.at(a / 2, b / 2, d / 2, c)
                fine.set(a, b, d, c, parent + (s64[i] ? g64 : -g64))
            }
        }
        return Decoded(colour: fine, depths: depths)
    }

    // MARK: - The ledger

    /// Bytes one retained capture costs, from the shape and a loud
    /// fraction. The figure the SET cover shows, so "keep all" is a
    /// visible cost rather than a silent one.
    static func bytesPerCapture(loudFraction: Double) -> Int {
        let roots = 16 * 16 * 16 * 3
        let depth = fineFrames * fineSide * fineSide * 4
        let coarse = roots * 2
        let sig = (roots + 7) / 8
        let perLoud = 4 + (children32 + children64) / 8    // 4 B g + 9 B signs
        let loud = Int((loudFraction * Double(roots)).rounded(.up)) * perLoud
        return headerBytes + depth + coarse + sig + loud
    }

    // MARK: - Byte helpers

    private static func appendLE(_ d: inout Data, _ v: UInt16) {
        withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
    }
    private static func appendLE(_ d: inout Data, _ v: UInt32) {
        withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
    }
    private static func readLE16(_ d: Data, _ p: inout Data.Index) -> UInt16 {
        let v = UInt16(d[p]) | (UInt16(d[p + 1]) << 8)
        p += 2
        return v
    }
    private static func readLE32(_ d: Data, _ p: inout Data.Index) -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(d[p + i]) << (8 * i) }
        p += 4
        return v
    }
}

// MARK: - Bit streams

struct BitWriter {
    private var bytes: [UInt8] = []
    private var acc: UInt8 = 0
    private var used = 0

    mutating func write(_ bit: Bool) {
        if bit { acc |= UInt8(1) << (7 - used) }
        used += 1
        if used == 8 { bytes.append(acc); acc = 0; used = 0 }
    }

    mutating func writeBits(_ v: UInt16, count: Int) {
        for i in stride(from: count - 1, through: 0, by: -1) {
            write((v >> UInt16(i)) & 1 == 1)
        }
    }

    mutating func finish() -> Data {
        if used > 0 { bytes.append(acc); acc = 0; used = 0 }
        return Data(bytes)
    }
}

struct BitReader {
    private let data: Data
    private var index: Data.Index
    private var used = 0

    init(_ data: Data, from: Data.Index) {
        self.data = data
        self.index = from
    }

    mutating func read() -> Bool {
        guard index < data.endIndex else { return false }
        let bit = (data[index] >> (7 - UInt8(used))) & 1 == 1
        used += 1
        if used == 8 { used = 0; index = data.index(after: index) }
        return bit
    }

    mutating func readBits(_ count: Int) -> UInt16 {
        var v: UInt16 = 0
        for _ in 0..<count { v = (v << 1) | (read() ? 1 : 0) }
        return v
    }
}
