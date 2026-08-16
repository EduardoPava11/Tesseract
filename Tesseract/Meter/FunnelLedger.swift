// FunnelLedger.swift
// Tesseract
//
// ★ HOW THE SIGNAL GETS FUNNELED, MEASURED STRATUM BY STRATUM.
//
// Daniel, 2026-08-15: "I am ready to explore the color space fully.
// that means we should do a series of serious tests. so I know how the
// information from the signal gets funneled. For example a raw reading
// of a series of related numbers can be summarized into one bigger
// number. categorize compression into its components."
//
// This file is the second half of a contract that has been half
// written since 2026-08-12. spec/output/RateLadder.hs declares the
// ladder and says, in as many words, that the content-dependent strata
// "declare 1 here -- their factors are MEASURED per capture by the
// RATE LEDGER, not assumed". The RATE LEDGER that shipped (S0,
// GIFMachine.swift:143) traces five end-to-end numbers: px, lzw, H0,
// K, M. It never decomposed anything. The factors RateLadder promised
// to measure were never measured.
//
// ── ★ THE DISTINCTION THIS LEDGER EXISTS TO DRAW ────────────────
//
// Daniel's phrasing is the whole design: "a raw reading of a series of
// related numbers can be SUMMARIZED into one bigger number." Not every
// 144:1 is that. A stratum can reach the same ratio four ways, and the
// rate ladder's bookkeeping cannot tell them apart:
//
//   DISCARD     read one of the 144 and drop the rest. The output is
//               a MEMBER of the input, not a function of it. Cheap,
//               aliases, and loses what it drops permanently.
//   SUMMARIZE   compute one number FROM all 144. The output is a
//               function of every input. This is the one Daniel named.
//   RECODE      keep every sample, spend fewer bits on each (VQ,
//               24 bits to 8). Loses precision, never coverage.
//   EXPAND      spend MORE bits than came in, deterministically. The
//               palette is this: 14 numbers become 6144 bits. It adds
//               no information and it is not a loss either.
//
// ★ AND THE FIRST STRATUM IS A DISCARD, WHICH IS WORTH KNOWING.
// `Quantize.metal`'s downsampleRGB does ONE `texture.read` per output
// pixel (Signal/FrameGeometry.swift, G11-G13). At 64² that is one
// sample kept and 143 dropped, with no prefilter. The ledger reports
// `boxMeanDivergence` beside it: the same frame summarized instead of
// sampled, and the energy difference between the two. That number is
// the price of the choice, and it had never been taken.
//
// ── THE OTHER HALF: THE LEDGER READ BACKWARDS ───────────────────
//
// TE10 says E = N·8 − N·H0 exactly, so the index plane's order-0 bill
// IS 2,097,152 − E. Set that beside what LZW actually spent and the
// coder's work splits into two named parts with no fitting:
//
//   index plane           2,097,152 b   the wire at maximal disorder
//   − E                                 what the palette's own
//                                       occupancy already saved
//   = order-0 bill                      an ideal symbol coder's spend
//   − LZW's actual spend                8 × lzwCost
//   = the context find                  what LZW got from RUNS that a
//                                       symbol coder could not
//
// Nothing here is fitted and nothing is a metaphor: E is the ledger
// read from the other end, which is TE10 stated as arithmetic.
//
// Meter/, so no exported byte depends on any of it.

import Foundation

enum FunnelLedger {

    /// What KIND of narrowing a stratum performs. The rate alone
    /// cannot say, and the difference is the point.
    enum Kind: String, Sendable {
        case discard    = "DISCARD"
        case summarize  = "SUMMARIZE"
        case recode     = "RECODE"
        case expand     = "EXPAND"
        case retain     = "RETAIN"
    }

    /// ★ THE FUNNEL IS A DAG, NOT A CHAIN, and pretending otherwise is
    /// how a telescoping check becomes meaningless. Three paths leave
    /// the sensor and only one of them carries the pixels:
    ///
    ///   pixel      768² colour -> 64² -> 8-bit indices -> LZW.
    ///              This one telescopes, and RL2 is checked on it.
    ///   codebook   the same 64² colour -> 14 numbers -> 768 table
    ///              bytes. It FORKS off at the latent and rejoins at
    ///              assignment as the thing indices point INTO.
    ///   depth      256² depth -> 64² -> ONE BIT per voxel, the role
    ///              bit. 32:1, and the steepest terminus in the app.
    enum Path: String, Sendable {
        case pixel    = "pixel"
        case codebook = "codebook"
        case depth    = "depth"
    }

    struct Stratum: Sendable {
        let name: String
        /// The axiom or decree that governs this arrow.
        let law: String
        let kind: Kind
        let path: Path
        let bitsIn: Int
        let bitsOut: Int

        /// In : out. Below 1 for an expansion, and that is not a bug.
        var ratio: Double {
            bitsOut == 0 ? .infinity : Double(bitsIn) / Double(bitsOut)
        }
    }

    struct Ledger: Sendable {
        let strata: [Stratum]

        /// The three energies of the emitted cube (TE11-TE15).
        let energy: TilingEnergy.CubeValue

        /// Σ over frames of that frame's own E. Compare with
        /// `energy.eHist`, which pools: TE9 says pooling cannot be
        /// more ordered than the parts on average.
        let perFrameEnergySum: Double

        /// 8 × lzwCost: what the coder actually spent on the indices.
        let lzwBits: Int

        /// The whole file, including tables and provenance.
        let fileBits: Int

        /// What CR1 keeps: 7 bytes per voxel. The surplus the edit
        /// spends is this minus the index plane.
        let retainedBits: Int

        /// The ratio the deviation ruling stands on.
        var surplusRatio: Double {
            Double(retainedBits) / Double(indexPlaneBits)
        }

        /// ★ The S0 finding, in the units of the thing itself: the
        /// mean absolute channel difference between the point sample
        /// the app takes and the box mean it does not, over one frame,
        /// in 8-bit levels. Zero on a constant field, by construction.
        let boxMeanDivergence: Double

        /// The cube actually measured. ★ These were a hard-coded 64
        /// and 4096 in the first draft, which made every derived
        /// figure wrong for any cube that was not full length, and
        /// made `contextFindBits` reconstitute the plane VACUOUSLY
        /// (it is defined as order0 − lzw, so the sum is an identity
        /// whatever the plane is). Carrying the real shape is what
        /// lets a test compare against something it did not compute.
        let frameCount: Int
        let pixelsPerFrame: Int

        // MARK: - The decomposition (TE10)

        /// The index plane at maximal disorder: frames · N · 8.
        var indexPlaneBits: Int { frameCount * pixelsPerFrame * 8 }

        /// What an ideal order-0 coder would spend, per-frame
        /// statistics. TE10 makes this an identity, not an estimate.
        var order0Bits: Double { Double(indexPlaneBits) - perFrameEnergySum }

        /// What LZW found beyond order-0, i.e. the value of RUNS.
        /// Negative would mean LZW did worse than a symbol coder,
        /// which is possible and would be worth knowing.
        var contextFindBits: Double { order0Bits - Double(lzwBits) }

        func path(_ p: Path) -> [Stratum] { strata.filter { $0.path == p } }

        /// RL2, checked where it is true: the product of a PATH's
        /// declared ratios equals that path's end-to-end ratio. It
        /// telescopes because each stratum's output is literally the
        /// next one's input, which is a property of the path and not
        /// of the stratum list.
        func telescoped(_ p: Path) -> Double {
            path(p).reduce(1) { $0 * $1.ratio }
        }

        func endToEnd(_ p: Path) -> Double {
            let s = path(p)
            guard let first = s.first, let last = s.last, last.bitsOut != 0
            else { return .infinity }
            return Double(first.bitsIn) / Double(last.bitsOut)
        }

        /// True when every adjacent pair in the path actually connects.
        /// If this is false the telescoping identity is vacuous, so it
        /// is checked rather than assumed.
        func isConnected(_ p: Path) -> Bool {
            let s = path(p)
            guard s.count > 1 else { return true }
            return zip(s, s.dropFirst()).allSatisfy { $0.bitsOut == $1.bitsIn }
        }

        /// The ledger as a table, for a test to print. This is the
        /// artifact Daniel asked for: the funnel, visible.
        var report: String {
            var out = ""
            for p in [Path.pixel, .codebook, .depth] {
                out += "\n  \(p.rawValue.uppercased()) PATH\n"
                out += "  stratum                    law            kind        "
                     + "bits in       bits out      ratio\n"
                out += "  " + String(repeating: "-", count: 92) + "\n"
                for s in path(p) {
                    out += "  " + pad(s.name, 26) + pad(s.law, 15)
                        + pad(s.kind.rawValue, 12)
                        + pad(String(s.bitsIn), 14) + pad(String(s.bitsOut), 14)
                        + String(format: "%.4f", s.ratio) + "\n"
                }
                out += String(format: "  telescoped %.6f   end to end %.6f   connected %@\n",
                              telescoped(p), endToEnd(p),
                              isConnected(p) ? "yes" : "NO (product is vacuous)")
            }
            out += "\n  THE CODER, DECOMPOSED (TE10)\n"
            out += String(format: "    index plane       %12d b\n", indexPlaneBits)
            out += String(format: "    E (per frame sum) %12.1f b   what occupancy saved\n",
                          perFrameEnergySum)
            out += String(format: "    order-0 bill      %12.1f b\n", order0Bits)
            out += String(format: "    LZW actual        %12d b\n", lzwBits)
            out += String(format: "    the context find  %12.1f b   what RUNS bought\n",
                          contextFindBits)
            out += String(format: "    whole file        %12d b\n", fileBits)
            out += String(format: "\n  THE SURPLUS (CR1, and the deviation ruling)\n")
            out += String(format: "    retained          %12d b\n", retainedBits)
            out += String(format: "    index plane       %12d b\n", indexPlaneBits)
            out += String(format: "    ratio             %12.2f : 1\n", surplusRatio)
            out += "\n  THE CUBE'S THREE ENERGIES (TE15)\n"
            out += String(format: "    E       %12.1f b  of 2097152   (low is diverse)\n",
                          energy.eHist)
            out += String(format: "    E_wall  %12.1f b  of  516096   (high is structured)\n",
                          energy.eWall)
            out += String(format: "    E_time  %12.1f b  of  262144   (high is coherent)\n",
                          energy.eTime)
            out += String(format: "\n  S0 point sample vs box mean: %.3f levels mean abs\n",
                          boxMeanDivergence)
            return out
        }

        private func pad(_ s: String, _ n: Int) -> String {
            s.count >= n ? s + " " : s + String(repeating: " ", count: n - s.count)
        }
    }

    // MARK: - The measurement

    /// Walk one capture's own numbers and lay out the funnel.
    ///
    /// `boxMeanDivergence` is passed in rather than computed here
    /// because it needs the SOURCE frame, which no longer exists by
    /// the time an Output does. A caller with no source passes zero
    /// and the row reads zero, which is the truth for that caller
    /// rather than a stand-in.
    static func measure(output: DyadPipeline.Output,
                        gifBytes: Int,
                        lzwBytes: Int,
                        outputSize: Int = 64,
                        boxMeanDivergence: Double = 0) -> Ledger {
        let frames = output.indexFrames.count
        let px = outputSize * outputSize

        // S0. Acquisition. The steepest step, and a DISCARD: one
        // texel read per output pixel (FrameGeometry G11-G13).
        let rgbSrcBits = frames * FrameGeometry.rgbCrop * FrameGeometry.rgbCrop * 24
        let rgbOutBits = frames * px * 24
        let depthSrcBits = frames * FrameGeometry.depthCrop * FrameGeometry.depthCrop * 32
        let depthOutBits = frames * px * 32

        // S1. Retention. 7 bytes per voxel, nothing lost, nothing
        // gained: this is the surplus the edit spends.
        let cubeBits = rgbOutBits + depthOutBits

        // S2. ★ THE SUMMARIZE. Every staged sample in a frame becomes
        // 14 numbers and 2 bits. This is the arrow Daniel named, and
        // it is by far the largest ratio in the ladder.
        let latentBits = frames * (14 * 64 + 2)

        // S3. ★ THE EXPAND. Those numbers regenerate all 768 table
        // bytes per frame, deterministically (CL1, PT7-PT9).
        let tableBits = output.tables.reduce(0) { $0 + $1.count * 8 }

        // S4. Assignment. Every pixel keeps its place and loses
        // precision: 24 bits of colour become an 8-bit index.
        let assignInBits = frames * px * 24
        let assignOutBits = frames * px * 8

        // S5. LZW, measured.
        let lzwBits = lzwBytes * 8

        // The role bit: depth's entire terminus in the artifact (AD7).
        let roleBits = frames * px * 1

        let strata: [Stratum] = [
            // The pixels. This path telescopes and RL2 is checked on it.
            Stratum(name: "S0 acquire RGB", law: "G11-G13", kind: .discard,
                    path: .pixel, bitsIn: rgbSrcBits, bitsOut: rgbOutBits),
            Stratum(name: "S4 assign indices", law: "RL1 / AD", kind: .recode,
                    path: .pixel, bitsIn: assignInBits, bitsOut: assignOutBits),
            Stratum(name: "S5 LZW", law: "RL5", kind: .recode,
                    path: .pixel, bitsIn: assignOutBits, bitsOut: lzwBits),

            // The codebook. Forks off the same 64² colour, narrows to
            // 14 numbers, then blooms back out to the table.
            Stratum(name: "S2 solve the latent", law: "CL1", kind: .summarize,
                    path: .codebook, bitsIn: rgbOutBits, bitsOut: latentBits),
            Stratum(name: "S3 grow the palette", law: "PT7-PT9", kind: .expand,
                    path: .codebook, bitsIn: latentBits, bitsOut: tableBits),

            // Depth. Steepest terminus in the app: 32 bits per voxel
            // arrive and ONE leaves.
            Stratum(name: "S0 acquire depth", law: "G11-G13", kind: .discard,
                    path: .depth, bitsIn: depthSrcBits, bitsOut: depthOutBits),
            Stratum(name: "S4b depth to role bit", law: "AD7 / DM", kind: .summarize,
                    path: .depth, bitsIn: depthOutBits, bitsOut: roleBits),
        ]

        let perFrame = output.indexFrames.reduce(0.0) {
            $0 + TilingEnergy.energy(TilingEnergy.histogram($1))
        }

        return Ledger(strata: strata,
                      energy: TilingEnergy.value(cube: output.indexFrames),
                      perFrameEnergySum: perFrame,
                      lzwBits: lzwBits,
                      fileBits: gifBytes * 8,
                      retainedBits: cubeBits,
                      boxMeanDivergence: boxMeanDivergence,
                      frameCount: frames,
                      pixelsPerFrame: px)
    }

    /// ★ THE S0 MEASUREMENT: what the point sample costs against the
    /// box mean of the same block, in 8-bit levels, averaged over the
    /// frame. Both read the SAME rotated address law, so the only
    /// difference measured is sample against summary.
    static func pointSampleDivergence(source: [(Float, Float, Float)],
                                      sourceSide: Int,
                                      outputSize: Int = 64,
                                      crop: (x: Int, y: Int) = (0, 0)) -> Double {
        var acc = 0.0
        for y in 0..<outputSize {
            for x in 0..<outputSize {
                let s = FrameGeometry.sourceRGB(x: x, y: y, outputSize: outputSize,
                                                crop: crop)
                guard s.x >= 0, s.x < sourceSide, s.y >= 0, s.y < sourceSide else { continue }
                let point = source[s.y * sourceSide + s.x]
                let mean = FrameGeometry.boxMean(source: source, sourceSide: sourceSide,
                                                 x: x, y: y, outputSize: outputSize,
                                                 crop: crop)
                acc += (abs(Double(point.0 - mean.0))
                        + abs(Double(point.1 - mean.1))
                        + abs(Double(point.2 - mean.2))) / 3 * 255
            }
        }
        return acc / Double(outputSize * outputSize)
    }
}
