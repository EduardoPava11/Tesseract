# Tesseract Haskell Specs

The Haskell layer is authoritative; Swift/Metal are ports. Every
mechanism gets a spec with named axioms BEFORE the port. Run:

    cd spec && make test            # the whole CORE suite
    make test-one F=temporal/DepthMixture.hs
    make corpus                     # emit the SK gene corpus → nn/sk-gene/
    make icon                       # render the app icon (~2m)

The Makefile is the registry of record — a file not in its lists is
either a generator (EmitDyadFixtures), deprecated (spec/deprecated/),
or should not exist. Layers (see Makefile for the full lists):

- **algebra/** — the 4⁴ tesseract lattice, direct sums, distances.
- **quantization/** — palettes and assignment: the DYAD-256 paired
  palette (DyadPalette, the aerial mirror law DY1–DY15, ★R4 RULED
  faithful-hue 2026-08-11), phase palette (PP1–PP16), bell/spectral
  palettes, the perfect quantizer, resolution ladder.
- **temporal/** — depth signals and cadences: the constant-free role
  law (DepthMixture DM1–DM12) and the mixture local-level law
  (MixtureStability MS1–MS7, ruled 2026-08-11), binomial cadences,
  the temporal loop.
- **spatial/** — Go-board territory reads over blocks (TesseractGo).
- **statistics/** — variance laws, phase energies (Ising/crossover),
  the tiling energy in bits (TilingEntropy TE1–TE10: E = N·log₂K −
  N·H₀, ground = every color exactly 16×), the Sethares dissonance
  kernel, Wasserstein palettes.
- **neural/** — the weave state a capture-assist model may read
  (WeaveState WS1–WS10), the ANE loop calculus (AL1–AL9), the SK gene arc
  (SKGeneCalculus SK1–SK10, SKGeneSemantics AX1–AX8, OctaveCodec
  CX1–CX7), the Mac-side debayer contract (BayerResidual).
- **ui/** — cell-grid mechanics (lint-gated via scripts/lint-grid.sh).
- **harmony/** — set-list dissonance ordering.
- **output/** — the GIF machine's export contracts, frame geometry,
  tri-scale ladder (TL1–TL12), corpus/icon emitters.

House rules: spec files are standalone (verbatim copies over imports;
parity gates catch drift); no naked constants (every threshold derived
from data or structure — DepthMixture is the pattern); gates print
✓/✗ and the harness fails on any ✗.

2026-08-11 unification: the pre-pivot gene-NN/MAP-Elites/VoxelCube/
KataGo-era specs were removed (git history keeps them); the suite now
contains only files with living Swift ports, Mac-lab contracts, or
standing theory referenced by the docs.
