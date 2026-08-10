# Tesseract

iPhone camera app: 4⁴ = 256-entry (epoch, R, G, B) tesseract-palette GIFs.
Independent of SixFour.

## ★ FRONT-CAMERA ONLY — standing decree (Daniel, 2026-07-15)

This app uses the FRONT camera exclusively. Two modes:
- **LIVE** — TrueDepth synchronized RGB+depth; depth drives dither strength
  and the Gaussian epoch cadence.
- **FACE** — ARKit face mesh; anatomical signal (nose = 1, background = 0)
  fills the same pipeline slot (`spec/temporal/FaceCadence.hs`).

**Do NOT add rear-camera capture** (Bayer DNG, LiDAR, 48MP) without Daniel
explicitly saying "bring back the rear camera." Ambiguous RAW/DNG requests do
not count — front cameras emit no Bayer DNGs, and that contradiction is
Daniel's to resolve, not the implementer's. Rear work is preserved on
`archive/rear-rgbt` (photon-time RGBT burst) and `archive/dng-mode-v2`
(NN-debayer DNG mode); neither is merged, by design. RAW *processing*
capability (Haskell specs, the `nn/` Mac-side lab, pure Swift math) is
welcome on main; rear *capture in the app* is not.

## Architecture

Haskell is authoritative; Swift/Metal are ports (SixFour discipline).
- `spec/` — runghc axiom suite: `cd spec && make test` (35 files green
  as of 2026-08-10, incl. neural/MapElites.hs newly enrolled; the tally
  must stay at zero failures).
  New mechanisms get a spec with axioms BEFORE the Swift port.
- The app is a 64³ GIF MACHINE (spec/output/ExportMethods.hs): every
  export is 64 frames of 64×64 indices; METHODS (tesseract | refined |
  dyad) differ only in how indices/tables are made, selected by the
  persisted ExportSettings and resolved by eligibility. DYAD-256
  (spec/quantization/DyadPalette.hs): paired per-frame palettes,
  T[255−i] = comp(T[i]) in OKLab, face → primaries, background →
  σ-mirror pair-dither bleeding to 255. Assignment runs on the ANE
  (Tesseract/ML/DyadAssign.mlpackage, authored in nn/dyad-assign/,
  exact CPU fallback; placement laws XP1/XP2).
- The 16/32/64 ladder (spec/output/TriScaleLadder.hs →
  Tesseract/TriScaleLadder.swift, 2026-08-10): SixFour's color-head
  tri-scale pyramid ported to the export cube. Exact u64 lattice-level
  sums pooled over 2×2×2 spacetime blocks (64³→32³→16³); time law
  side × delay = 320 cs. MEASUREMENT ONLY — published as rungTelemetry
  on both capture managers; no GIF byte depends on it; trains nothing
  (★NO-CAPTURE-TRAINING). Distinct from quantization/ResolutionLadder
  (subject-gated per-cell resolution). TL8/TL9 (2026-08-10): 16³ ==
  32³ == 64³ in the information process, compute time = the
  equivalence; THE RESOLUTION OF DEPTH is rung 16 (64 draws per
  judgment, 4096 judgments/loop at 5 Hz; RGB rides 64-rung at 20 Hz).
  Gates: spec TL1–TL9 + TesseractTests/TriScaleLadderTests.
- THE DISSONANCE WEAVE (2026-08-10, design docs/dissonance-weave-design.md):
  Sethares/Plomp-Levelt roughness ported as ONE kernel, three ports —
  spec/statistics/Dissonance.hs (kernel, DS1–DS16; b1=3.51 b2=5.75
  x*=0.24 s1=0.0207 s2=18.96), spec/quantization/SpectralPalette.hs
  (octaves in RGB → color: channel combs (4,5,6)·125·2^ℓ Hz, tuning =
  argmin of the loop's own occupancy spectrum, σ-involution = tritone),
  spec/harmony/SetListDissonance.hs (F0-lock 0.3125 Hz; inter-loop
  (X_ear, χ_eye) dyad; set ordering). Depth → urgency: bond roughness
  on σ(d) cadence with ZERO tuned constants (near/far = exact octave ⇒
  x = x* theorem); urgency field 16³ at 5 Hz (TL9 clock).
  SWIFT PORT v1 LANDED (Dissonance.swift + DissonanceTests): kernel,
  G quadratic form, tuning at the rung-16 cadence (16 reads/loop,
  Daniel's TL8 ruling), urgency field published as `dissonance` on
  both managers. ★URGENCY IS A WEIGHT (the color-weight slot, no
  directional sign). Telemetry-only; felt channel decided after the
  device movement pass.
- `isp-spec/` — DEPRECATED rear-camera cabal ISP spec, read-only reference.
- `nn/` — Mac-side lab: MLX-trained 5,616-param residual debayer
  (`nn/debayer/`, +3.72 dB over bilinear) and its Metal parity harness
  (`nn/metal-harness/run.sh`, verified 3e-7 on M3 Max). Runs on Mac only.

## Export contract

Every GIF is 256×256 px (palette-index replication, never interpolation;
`decimate ∘ replicate = id`), exactly 5 cs frame delay = 20 fps.
Table scheme by method: dyad = 64 per-frame Local Color Tables (packed
byte 0x87, GCT = frame 0's table); tesseract/refined = one 256-entry
global table (0x00). Byte-level contracts locked by
`TesseractTests/GIFOutputContractTests` (lattice) and
`DyadGIFContractTests` (per-frame LCTs + involution in every table).
DYAD exports carry a "DYAD HARMONY" provenance comment (Ou & Luo pair
score over all frames).

## UI (SIMPLICITY DECREE, 2026-08-09)

Launch = loading screen until the first preview frame, then ONE
surface: preview + record + SET. All choices live in the settings
cover (CAMERA live/face, LOOK dyad/refine/tess, BLEED, MIRROR — all
persisted via ExportSettings). No mode chrome, no menus. The A/B
dual-explore step and the elite-map entry are deprecated (modules
compiled but unreachable).

## Build

- `xcodegen generate` then build scheme `Tesseract` (project not checked in).
- Signing on this Mac: team `9WANULVN2G` (cached wildcard profile signs
  offline; QFTX3897B7 has NO account here). `GENERATE_INFOPLIST_FILE: YES`
  is load-bearing.
- Camera code is COMPILE-ONLY off-device (simulator has no camera). Pure
  logic suites run on simulator: FaceMeshSignal, GIFUpscale,
  GIFOutputContract, WassersteinCoordinates.
- Known open items: first on-device FACE run (mirroring unverified);
  4 latent AxiomTests failures (AxiomTests.swift:467–554, test-vs-semantics
  question predating the pivot); DEBUG `FRONT-RAW PROBE` log line answers
  whether this device exposes any front RAW to third-party apps.
