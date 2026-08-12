# THE RATE LADDER — a stratified redesign of the color pipeline

**Daniel's ruling, 2026-08-12:** "Use the math and redesign the whole
pipeline. In small steps. Not an oversimplification — a strategy and
stratified approach. Example: 2×2×2 ↔ 1 is an 8:1 ratio of information."

**The organizing principle** (from the research survey, same day):
beauty math IS compression math. Birkhoff's M = O/C, operationalized by
Rigau–Feixas–Sbert as *order = the uncertainty a compressor removes*;
Schmidhuber's formal beauty = shortest description under the observer's
encoder; the gamut literature's law = compress chroma, preserve hue and
lightness, in a decorrelated space. The pipeline's input is a camera
(~10⁹ bits per capture) and its output is GIF89a (~10⁶ bits): the
pipeline is one long compressor, so every stage must **declare its
ratio, its metric, and its loss** — and the whole thing must carry a
**meter** so each redesign step is judged by measured compression
progress, not taste memos.

This is NOT a rewrite. Every law that exists stays (aerial invariant,
mixture role law, involution, Wada ground, seam-death, chaos blur).
The redesign is a *stratification*: name the strata, declare each
ratio, and fix the four places the audit found **accidental or
undeclared** loss.

---

## 1. The information audit (what the pipeline does today)

Per capture: 64 frames, 3.2 s loop. Bits are per cube unless noted.

| # | Stratum | Where (spec → port) | In → Out | Declared ratio | Kind |
|---|---------|--------------------|----------|----------------|------|
| S0 | **Acquisition** | FrameGeometry.hs → Quantize.metal downsample | 768²×24b×64f ≈ 906 Mb → 64²×24b×64f ≈ 6.3 Mb | **144:1** spatial | ⚠ point-sample (aliased — see §3.2) |
| S1 | **Metric** | DyadPalette §2 (OKLab) | 1:1 | **1:1** | recoding; the metric that makes all loss below perceptual (L ⟂ C) |
| S2 | **Aerial compander** | §6c γ(s)=1/(2−s) | chroma support | **≤2:1** chroma, depth-indexed | the chroma octave pays for the temporal octave (DY9) |
| S3 | **Statistical generator** | §4–§5 analyze→shells | 98,304 b/frame staged samples → 13 numbers ≈ 832 b | **≈118:1** per frame | ⚠ PC3 discarded undeclared (see §3.3) |
| S4 | **Involution / ground** | §3b, T[σi]=ground(T[i]) | 256 entries from 128 | **2:1** palette; σ half costs β_C bits-per-bit in ln-chroma | the Wada power law IS a compander (β prior 0.747) |
| S5 | **Vector quantization** | §6 nearest-primary, ANE DyadAssign | 24 b/px → 8 b/px | **3:1** at grid resolution | fp16 engine = XP2 near-tie law |
| S6 | **Spacetime pooling** | §6d chaos blur; TriScale TL1–TL12 | σ-side targets | **16:1** spatial today (4×4); the atom is **2×2×2 ↔ 1 = 8:1** | ⚠ no temporal pooling yet (see §3.4) |
| S7 | **Coverage code** | Bayer 4×4 × mixture posterior t | role information | **≤log₂17 ≈ 4.09 b**/tile representable coverage | constant-free (DepthMixture) |
| S8 | **Entropy coder** | GIFEncoder lzwEncode | index cube → wire bytes | **measured** (typ. 2–4:1) | ⚠ unmeasured until now — this is THE METER (see §3.1) |

End-to-end: ≈906 Mb → ≈1–2 Mb wire ≈ **500–900:1**, composed as the
product of the strata. The **composition law** is the redesign's spine:

```
R_total = Π_i R_i          (ratios telescope; every stratum declares its factor)
```

and Daniel's atom generates S6's factors: one rung of 2×2×2 spacetime
pooling is 8:1; rungs compose 8 → 64 → 512 (64³ → 32³ → 16³ is two
rungs = 512:1, TriScale's exact lattice sums).

## 2. The beauty ledger (why a meter, and which one)

Rigau's operational Birkhoff measure needs only bytes we already own:

```
H₀  = Shannon entropy of the emitted index histogram   (bits/px, ≤ 8)
K̂   = 8 × LZW_bytes / N                                (bits/px, the encoder's own output)
M   = (H_max − K̂) / H_max,  H_max = 8                  (order ratio; the compressor's discovery)
```

- M rises when the cube gets *lawfully simpler* (flat chaos blocks,
  stable palettes, coherent motion) and falls when we ship noise
  (aliasing, dither shimmer, palette churn).
- It is **the fitness function for every later step**: a stratum change
  ships only if the ledger moves the declared direction AND the device
  pass feels right. Two gates, neither alone.
- Zero new constants: H_max = 8 is the wire's own index width.

The ledger rides the provenance comment (comment bytes only — the
established PhaseTelemetry / DYAD ENERGY channel).

## 3. The redesign, stratum by stratum

### 3.1 S8 first — install the meter (Step 0, measurement only)
`RATE LEDGER v1 raw=… lzw=… H0=… K=… M=…` in the DYAD comment,
computed by the same lzwEncode that writes the wire. No pixel changes.
Everything after this step is judged against it.

### 3.2 S0 — lawful band-limiting (Step 2)
Today the 768²→64² decimation takes ONE point sample per 12×12 block.
Aliasing is *fake complexity*: it injects high-frequency noise the eye
never saw in the scene, inflating K̂ and burning σ-side flatness.
Redesign: box-pool the 12×12 block in the downsample kernels (the
[1,2,1]³ tent is available later via the TL10–12 polyphase identity —
the 8-phase orbit equals the tent at box cost, already proved).
Claim to verify on the ledger: K̂ drops at equal content. **Look
changes → device ruling required.**

### 3.3 S3 — eigenvalue rate allocation (Step 3)
The binomial ladder [1,1,2,4,8,16,32,64] spends all 128 codewords on
the PC1×PC2 ellipse; PC3 gets exactly zero — an undeclared allocation.
Transform-coding's classic law (reverse water-filling) says codewords
per axis go as √λ (bit difference b_i − b_j = ½log₂(λ_i/λ_j)); the
in-plane radii already scale by √λ₁, √λ₂, so the plane is lawful —
only the PC3 = 0 decision is naked. Redesign: (a) FIRST measure the
PC3 residual energy in telemetry; (b) if the ledger shows systematic
residual, lift shells to ellipsoids with PC3 extent √λ₃ — allocation
derived from the capture's own eigenvalues, no threshold. **Palette
changes → spec axioms + device ruling.**

### 3.4 S6 — complete the atom: spacetime chaos blur (Step 4)
The chaos blur pools 4×4 in space only (16:1). Daniel's atom is
2×2×2 ↔ 1 — the pooling should be SPACETIME, and the loop torus makes
temporal pooling exact (t-wrap by periodicity, TL10). Redesign: σ-side
targets become the mean over the 4×4×4 spacetime block (64:1 on chaos
pixels; equivalently three composed 8:1 rungs restricted to the
σ role). The rung count stays ONE (seam-death: the pair must not
depend on t — pinned yesterday, preserved here). The background then
holds still for 4-frame groups → LZW inter-frame runs collapse → K̂
drops measurably. **Look changes → spec §6d extension + device ruling.**

### 3.5 S5 — rate-distortion assignment (Step 5, flag-gated)
The ANE exchange loop (descent on F, the PP1 Haar 3:2:1 distortion)
already refines fully-far blocks behind CameraConfig.phaseChaosLoop.
Extend its scope to band blocks once S6 lands, still flag-gated,
still judged by the ledger + F telemetry. No new machinery — the
distortion measure and the engine both exist.

### 3.6 S9 — harmony validation (Step 6, telemetry first)
Ou & Luo (DYAD HARMONY) predicts the v7 same-hue ground raises the
harmony mean — the first device capture gives the before/after free.
The 2025 natural-hue-statistics result (preference is hue-DEPENDENT:
blue anchors combine broadly, red/green/purple anchors pair poorly)
suggests a hue-conditioned harmony v2 — **telemetry only** until data
from real captures argues for steering anything.

## 4. The step ladder (small steps, every one gated)

| Step | Stratum | Change | Pixels change? | Gates |
|------|---------|--------|----------------|-------|
| **S0** | S8 | RATE LEDGER v1 in the comment | no (comment bytes) | spec RL axioms + Swift test + build |
| **S1** | all | RateLadder.hs — the ratio algebra as law | no | runghc green |
| **S2** | S0 | box prefilter in downsample kernels | yes | FrameGeometry axioms, ledger K̂↓, **device ruling** |
| **S3** | S3 | PC3 residual telemetry → eigen-allocated ellipsoid shells | telemetry, then yes | DY axioms, ledger, **device ruling** |
| **S4** | S6 | spacetime chaos blur 4×4×4 (torus-exact) | yes | §6d axioms, seam-death, ledger K̂↓, **device ruling** |
| **S5** | S5 | ANE exchange loop scope → band blocks | flag-gated | AL axioms, F + ledger, **device ruling** |
| **S6** | S9 | hue-conditioned harmony v2 | no (telemetry) | spec + captures |

Standing rules: Haskell spec BEFORE every port; no naked constants —
every number is a measured moment, an eigenvalue, a lattice constant,
or the wire's own width; each step ships alone; the ledger's
before/after rides in the GIF itself, so the evidence archives itself
in the Library.

**Executed 2026-08-12: S0 + S1.** S2–S6 await Daniel's step-order
ruling and device passes.
