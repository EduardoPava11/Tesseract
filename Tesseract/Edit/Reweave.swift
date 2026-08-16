// Reweave.swift
// Tesseract
//
// ★ THE EDIT ENTRY POINT (docs/model-placement.md; spec
// quantization/RoleAllocation.hs §3, ui/EditMachine.hs EM8-EM13).
//
// Daniel: "this is an EDIT app so we only need the models to inform
// the weave so that we can edit to make different GIFs."
//
// The contract, from the spec (RoleAllocation's tick contract): a GIF
// is a PURE FUNCTION of (capture, edit). CR1 retains the capture
// (CubeStore); this is the function. There is exactly one encoder —
// `DyadPipeline.process` — so reweaving is not a second pipeline, it
// is the same pipeline applied to a retained cube instead of a live
// one (EM12/EM13: weave = watch + keep, differing only in retention).
//
// CR3 IS THE GATE, AND IT IS SCOPED TO THE PICTURE (Daniel's ruling,
// 2026-08-15). `reweave(cube, .identity)` must reproduce the archived
// GIF's INDEX FRAMES AND PALETTE TABLES exactly, or retention is not
// evidence that the cube is the data the artifact came from.
// CubeStoreTests holds that gate; it passes today, and it is what that
// file has always actually asserted.
//
// ★ WHY "BYTE FOR BYTE" WAS THE WRONG GATE, stated because the old
// wording is quoted in several places: the capture path calls
// `GIFMachine.makeGIF(frames:)` and emits the PHASE F and SK GENES
// provenance sections; this path reaches `finish(..., frames: [])`, so
// those sections cannot be written at all. Byte equality was already
// false, by construction, on the day it was claimed. Reconstructing
// them would require the tensor to decode to rawRGB exactly, which
// CT11 declares it does not — so the strict reading would have
// permanently blocked the tensor from replacing the cube.
//
// Under the ruling the frame-derived provenance may differ and the
// picture may not. That is what unblocks the CaptureTensor call-site
// swap, which was staged behind CR3 and nothing else.
//
// ★ SCOPE, STATED HONESTLY. The Edit's five axes are the spec's, and
// all five are REPRESENTABLE here. TWO of the eight positions on the
// first axis were executable in the sense that only the identity was;
// as of 2026-08-16 the whole eFig axis is:
//
//   eFig         ★ EXECUTABLE. All eight depths. Applying one
//                re-emits the table at a coarser tree depth, which is
//                PT5's prefix law (truncate index = coarsen palette)
//                turned into a lookup: PairTree.Figures records every
//                level now, and `truncated(toFigureDepth:)` maps leaf
//                j to `levels[d][j >> (7 - d)]`. The blocker this
//                header used to name, "the shipped solver exposes
//                depth-4 nodes only", is closed.
//   eGnd         truncation on the sigma half. Still refused: it is
//                exactly the sigma-address question the architecture
//                routes to a MEASUREMENT (lambda_F / lambda_B,
//                step S5), not to a dial default.
//   eCoarse/eMid/eFine  the octave weights are a SIMPLEX over three
//                parallel reads (Octave OV6/OV8), and the app runs
//                only the fine read today. A weight on a read that
//                does not exist cannot be honoured.
//
// A refusal is the right answer for an unimplemented edit: silently
// returning the identity result would make the surface lie about what
// the dial did, which is worse than a dial that says "not yet".

import Foundation

enum Reweave {

    /// A point of RoleAllocation's edit space (spec §3, `data Edit`).
    /// Five axes, each 0…7 — the same 8^5 the spec enumerates.
    struct Edit: Equatable, Sendable {
        var fig: Int      // figure truncation depth   0…7
        var gnd: Int      // ground truncation depth   0…7
        var coarse: Int   // octave weight, 16³ rung   0…7
        var mid: Int      // octave weight, 32³ rung   0…7
        var fine: Int     // octave weight, 64³ rung   0…7

        /// The edit that names today's shipping path (spec
        /// `identityEdit`): the shipping allocation (7, 4) and the
        /// fine read alone — coarse and mid enter at zero because the
        /// weights are a simplex and the app runs one read.
        static let identity = Edit(fig: 7, gnd: 4, coarse: 0, mid: 0, fine: 7)

        var isIdentity: Bool { self == .identity }

        /// Every axis inside the spec's range. The dial's own detent
        /// counts are a UI law and a different object (DetentDial);
        /// this is the byte law.
        var isRepresentable: Bool {
            [fig, gnd, coarse, mid, fine].allSatisfy { (0...7).contains($0) }
        }
    }

    enum Refusal: Error, Equatable, Sendable {
        case outOfSpace            // not a point of the edit space
        case emptyCube
        case notYetLawful(String)  // representable, not executable
        case encodeFailed
    }

    // MARK: - The function

    /// A GIF from a retained capture and an edit. The ONLY entry point
    /// for making a different GIF from the same capture.
    typealias Export = (data: Data, measure: BirkhoffMeasure)

    static func reweave(cube: CubeStore.Cube, edit: Edit,
                        settings: ExportSettings = ExportSettings.load())
        -> Result<Export, Refusal> {
        guard !cube.rgb.isEmpty else { return .failure(.emptyCube) }
        guard edit.isRepresentable else { return .failure(.outOfSpace) }
        if let why = unsupported(edit) { return .failure(.notYetLawful(why)) }

        guard let export = GIFMachine.makeGIF(rgb: cube.rgb, depths: cube.depths,
                                              settings: settings,
                                              figureDepth: edit.fig)
        else { return .failure(.encodeFailed) }
        return .success(export)
    }

    /// Convenience: re-weave the cube retained for an archived GIF.
    static func reweave(gifURL: URL, edit: Edit)
        -> Result<Export, Refusal> {
        guard let cube = CubeStore.load(forGIF: gifURL) else {
            return .failure(.emptyCube)
        }
        return reweave(cube: cube, edit: edit)
    }

    /// Why an edit cannot be executed yet, or nil if it can. Kept as
    /// one total function so the surface can SAY what is missing
    /// instead of graying a control with no reason.
    static func unsupported(_ e: Edit) -> String? {
        if e.isIdentity { return nil }
        // ★ eFig IS EXECUTABLE as of 2026-08-16. The blocker this
        // header named, "the shipped solver exposes depth-4 nodes
        // only", is gone: PairTree.Figures now records every level and
        // `truncated(toFigureDepth:)` applies PT5's prefix law as a
        // lookup. The dial re-emits the table at a coarser tree depth,
        // which is exactly what the spec says it means.
        if e.gnd != Edit.identity.gnd {
            return "eGnd is the sigma-address question the architecture "
                 + "routes to the lambdaF/lambdaB MEASUREMENT (step S5), "
                 + "not to a dial default"
        }
        // ★ THIS RETURN USED TO BE UNCONDITIONAL, which was harmless
        // while ONLY the identity executed and became a bug the moment
        // eFig did: any non-identity edit fell through to the octave
        // refusal even with all three octave dials at identity. The
        // guard now names the axis it is actually about.
        if e.coarse != Edit.identity.coarse
            || e.mid != Edit.identity.mid
            || e.fine != Edit.identity.fine {
            return "octave weights need the coarse and mid reads to exist "
                 + "(Octave OV6/OV8 simplex; the app runs the fine read only)"
        }
        return nil
    }

    /// The axes that would move bytes today if they were executable —
    /// what the surface may offer once each lands. Ordered as the
    /// architecture sequences them.
    static let plannedAxes: [String] = ["gnd", "fig", "coarse", "mid", "fine"]
}
