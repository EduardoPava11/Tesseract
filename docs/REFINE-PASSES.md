# REFINE-PASSES — face-weighted centroid refinement on ANE + Metal

*Companion to `spec/quantization/CentroidRefine.hs` (WL1–WL5, exact) and
`docs/CENTERS.md`. The spine is pass 1; this document is pass 2.*

---

## 1. The three requirements, unified

1. **Face gets diversity, background gets fewer options.**
2. **Every step of the color push/pull is tracked.**
3. **The process runs as a CNN on the ANE, with Metal parity.**

These are not three features — they are one algorithm. The refinement is
a **fixed-K unrolled proximal iteration**, and each requirement pins one
of its degrees of freedom:

```
r⁰_i     = c_i                      canonical center (the spine)
r^{k+1}_i = r^k_i + η·( a_i·(m_i − r^k_i)  −  b_i·(r^k_i − c_i) )
                        └── PUSH ──┘          └── PULL ──┘
a_i = face mass of entry i          b_i = μ·(1 − a_i)
```

- The **face mass** `a_i` (from TrueDepth depth in LIVE, the ARKit
  anatomical signal in FACE — nose = 1, background = 0) is the push
  gain. Entries whose pixels are face chase their empirical colors;
  entries whose pixels are background have `a_i = 0` and **provably
  never move** (WL3) — the background's four epoch siblings stay
  collapsed on the canonical center, so it literally has fewer distinct
  options. Diversity is *earned by face mass*, not sprinkled.
- The **K steps are the trace.** K is fixed (not data-dependent), each
  step's `r^k` and delta are recorded, and WL5 proves the trace
  telescopes to the total displacement — complete provenance, nothing
  off the books. WL4 gives the exact geometric law each entry follows,
  so a trace can be *audited* against theory entry by entry.
- **Fixed K is also the ANE contract.** The Neural Engine cannot run
  data-dependent loop counts; a fixed-K unrolled graph is both the only
  legal form and (measured) the fast form. The provenance requirement
  and the hardware requirement are the same design decision.

WL1 (every iterate stays inside its lattice cell) is what keeps pass 2
subordinate to the spine: any refined table still re-quantizes to the
same indices (CN2/CN6 idempotence), the bijection survives, and the
epoch-sibling spread is bounded by the cell width — "alive" can never
become "broken."

## 2. Why this is a CNN (not a metaphor)

The whole pass is dense tensor algebra:

**Stage A — weighted segment means as 1×1 convolution.** The scatter
"average all pixels assigned to entry i" is ANE-hostile as a gather/
scatter but ANE-native as dense ops: one-hot the index stream
`O ∈ {0,1}^{64×64×64×256}` (fp16), then

```
m = (Oᵀ · (w ⊙ X)) / (Oᵀ · w)        w = face-mass map, X = source RGB
```

— elementwise multiplies and global sums per channel, i.e. **masked
global average pooling behind a 1×1 conv**. The palette histogram is a
matmul with a one-hot; that IS a convolution.

**Stage B — K refinement layers.** Each iteration is an affine map with
per-channel gains followed by a hard clamp to the cell:

```
r ← clip( (1 − η(a+b))·r + η(a·m + b·c),  cell_lo, cell_hi )
```

— K identical layers of scale-add-clip on a 256×3 tensor. Clip maps to
the ANE's clipped-activation primitive. (WL1 proves the clamp is inert
under the schedule η(a+b) ≤ 1, but it stays in the graph as a safety
invariant — enforcing in silicon what the spec proves on paper.)

**Stage C (the learned part) — the saliency CNN.** The raw face mass is
depth (LIVE) or the mesh mask (FACE). The upgrade is a small U-Net-style
CNN `(RGB, depth) → w ∈ [0,1]^{64×64}` that learns *where detail is
worth spending* — eyes and mouth over cheek, specular highlights over
flat skin. Train it in the `nn/` Mac lab exactly like the debayer
(MLX on Mac; the 5,616-param residual debayer with its 3e-7 Metal
parity harness is the template), export to Core ML, run on ANE.

## 3. Hardware placement (measured facts, arXiv:2606.22283)

| Fact | Consequence here |
|---|---|
| ~0.23 ms dispatch floor per ANE graph | never dispatch per-iteration; **fuse Stage A + all K Stage-B layers + Stage C into ONE graph** |
| fused fixed-iteration graphs: 10×/49× wins | the unrolled-K design is the fast path, not a compromise |
| no data-dependent trip counts | K fixed at 8 (spec schedule); trace length is a compile-time constant |
| fp16 condition numbers 10²–10⁴ | Stage A sums ~262k fp16 terms per entry — accumulate hierarchically (per-frame partial sums, then reduce 64 partials); never one long fp16 chain |
| placement rules: dense convs/pools eligible, gather/scatter falls back | the one-hot trick in Stage A exists precisely to stay ANE-resident |

**Metal's role is ground truth.** The same fold runs as a Metal
threadgroup reduction (and a scalar CPU version) — three implementations,
one law: `|ANE − Metal| ≤ fp16 tolerance`, Metal vs CPU exact. This is
the debayer parity workflow (`nn/metal-harness/run.sh`) applied to
refinement. The exact `Rational` trajectory from `CentroidRefine.hs` is
the fourth, paper-level reference the synthetic test vectors come from.

## 4. The trace format

Each refined GIF carries its own history in the GIF89a **comment
extension** (the encoder already writes one for the Birkhoff measure):

```
TRACE v1: K=8 η=1/2 μ=1/2
entry 137: a=0.81  c=(96,159,96)  m=(104,151,99)
  k1 (+3.2,-3.1,+1.2) … k8 (+0.1,-0.1,+0.0)   r=(103,152,99)
entry 42:  a=0.00  trace constant (background)
```

Self-contained provenance: any GIF can answer "how did this color get
here" without a sidecar. (Compact binary form later if size matters;
zero-face entries compress to one flag by WL3.)

## 5. Build-out order

1. ✅ `spec/quantization/CentroidRefine.hs` — WL1–WL5, exact, in the
   truthful suite (23/23).
2. ✅ Swift CPU reference: `CentroidRefiner.swift` (Stage A fold + K
   steps + trace + BOTH clamps — continuous cell and byte cell), wired
   into all three export paths (LIVE main, LIVE explore-export, FACE);
   `GIFEncoder` takes `refined:` + `traceComment:` (canonical default —
   the old byte-identical contract holds whenever pass 2 is absent).
   `CentroidRefinerTests` pins the Float trajectory to the WL4 closed
   form (1e-5), WL3 background constancy, out-of-cell containment in
   both spaces, and the encoder GCT/trace bytes. Result screen shows
   refined colors automatically (GIFPlayerView decodes the actual GIF);
   the pre-capture live preview stays canonical by design — refinement
   is a property of a capture, not of the stream.
3. ✅ Metal Stage A: `Refine.metal` + `RefineAccumulator.swift`,
   **bit-exact** with the CPU fold — per-pixel contributions quantized
   to 2¹⁶ fixed point with identical IEEE ops (MTL_FAST_MATH=NO), then
   INTEGER atomics, which commute: any GPU scheduling produces the same
   sums, so `MetalRefineParityTests` asserts equality (==), not
   tolerance, over a 64-frame dirty capture (NaNs, out-of-cell colors).
   Per-frame uint32 partials (< 2²⁸) combine in UInt64 on the CPU.
   Production uses `CentroidRefiner.refineAuto` — GPU when available,
   CPU fallback, provably indistinguishable. Stage B is shared code.
4. `nn/refine/` Mac lab: MLX one-hot/fused-graph prototype; then the
   saliency U-Net (data: captured bursts + mesh masks from FACE mode).
5. Core ML export, ANE residency check (Instruments), fp16-vs-Metal
   parity gate, then wire behind a setting.

Steps 2–3 make the feature real on device; 4–5 make it neural and
ANE-resident. Each step lands behind the same laws.
