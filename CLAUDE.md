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
- `spec/` — runghc axiom suite: `cd spec && make test` (currently 22/22).
  New mechanisms get a spec with axioms BEFORE the Swift port.
- `isp-spec/` — DEPRECATED rear-camera cabal ISP spec, read-only reference.
- `nn/` — Mac-side lab: MLX-trained 5,616-param residual debayer
  (`nn/debayer/`, +3.72 dB over bilinear) and its Metal parity harness
  (`nn/metal-harness/run.sh`, verified 3e-7 on M3 Max). Runs on Mac only.

## Export contract

Every GIF is 256×256 px (palette-index replication, never interpolation;
`decimate ∘ replicate = id`), 256-entry global color table, exactly 5 cs
frame delay = 20 fps. Byte-level contract locked by
`TesseractTests/GIFOutputContractTests`.

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
