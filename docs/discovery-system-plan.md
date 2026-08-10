# The Discovery System 𝔇 in Tesseract — build plan

2026-08-10. Daniel's axiomatization (𝔇 = G∘F, A1–A6, D1–D3, T1–T4) built into
the Tesseract app in Swift + Metal, with ~/WITNESS as the formal template.
Aligned decisions (Daniel, this session):

- **v1 target class 𝒯 = in-house extremal problems** (calibration layer of
  "both, layered"): true extrema in the spec's own finite universes, so 𝔇's
  first discoveries become new pinned constants in the spec suite.
- **Orbit home = in-app, post-capture, headless.** The severed A/B machinery
  revives OFF-surface: N orbit steps in a detached task after each burst,
  logger + trace output. Surface stays preview + record + SET (SIMPLICITY).
- **κ = phase-coordinate archive**: bins over the exact phase observables
  (φ, m_st, s) — the archive IS the phase portrait.
- **★HIGHER-ORDER RULING (the decree, resolved):** capture-fitness is
  A4's experiment E — it may refute and raise CONJECTURES (D2), session-scoped.
  Exact synthetic verification is A2's V — only V-verified DISCOVERIES (D1)
  enter the persisted κ. Invariant: **κ_persisted ⊆ V-verified. Captures
  experiment; they never verify.** T2's Popper asymmetry = ★NO-CAPTURE-TRAINING,
  stated as law.

## What exists (from the two deep reads, 2026-08-10)

The full 𝔇 loop is present and severed at two points:
- κ: `EliteMap` (3×3, greedy beauty, 2 of 5 entropy axes, teacher-only) — live
  every capture at CameraManager.swift:1039. `spec/neural/MapElites.hs`
  (ME1–ME8) exists but is NOT enrolled in the 31-file suite.
- g: `GeneWeights.perturbed(scale:seed:)` + `SobolExplorer` — deterministic,
  CORE-preserving; domain collapsed (gene resets to `defaultWeights()` per
  capture; explorer index reset at :1034 breaks low-discrepancy across orbits).
- U: `recomputeGIF(gene:) → placeOrganism` (CameraManager.swift:466–537) —
  already shaped as U(gene) → κ′, off-main, zero callers.
- Entry severance: `state = .done` at CameraManager.swift:1044 (decree comment
  :1041–1043). MLX absent → gradient-free orbit only (fits A3–A6).
- V substrate (exact): byte contracts (GIFOutputContract/DyadGIFContract),
  DY1–DY8 (DY2: 8192 exact byte-triple equalities), PE4–PE8 integer Ising,
  TL1–TL9 UInt64-exact, PP1–PP7 (2¹⁶ tile universe), DYAD STATS certificate
  (GIF rebuilds its own tables byte-exact — a real V(φ,c)=1 in production).
- GPU: `Gene.metal` forward exists; Swift binding broken (depths buffer never
  bound :619; in/out aliased :587–590); NO parity test. The lawful-GPU recipe
  exists elsewhere: Q16 fixed point + integer atomics + MTL_FAST_MATH NO
  (`refineAccumulate`, bit-exact CPU==GPU, MetalRefineParityTests).
- FACE mode has no κ at all (v1 keeps κ LIVE-owned; FACE joins later).

## Phase 0 — Spec (Haskell authoritative; nothing lands in Swift before green)

1. **`spec/neural/Discovery.hs`** (new; WITNESS is the stylistic and
   conceptual template — hierarchy levels, autonomy ladder, witness-pinned
   axioms). Executable 𝔇 over a finite toy:
   - A1–A6 as types: sentences graded Σ₁/Π₁/Π₂⁺; V total computable, sound;
     g a seeded Markov kernel with full support (A6 checked as: every
     certificate of length ≤ n has emission probability ≥ ε(n) > 0, exact
     Rational arithmetic on the finite space).
   - D1 discovery / D2 conjecture / D3 the operator 𝔇(κ) = U(κ, (φ,c,V(φ,c))).
   - T1 on an EXACT finite probability space: rational Borel–Cantelli —
     the orbit's non-discovery probability after t steps is (1−ε)^t, computed
     in Rational, monotone → 0; witness at concrete t.
   - T2: the asymmetry as executable law — a true Π₁ toy sentence reaches
     conjecture status and never D1 without a proof-certificate; a false one
     is refuted by E (finite counterexample found).
   - T3: monad laws (unit, associativity) for 𝔇 = G∘F checked on a small
     finite category instance.
   - T4: μ_t → 1 on a bounded-Σ₁ target class, seeded runs.
   - **THE HIGHER-ORDER LAW (H1):** two-tier orbit — inner loop with E only
     (capture-shaped fitness, stochastic) produces conjecture sets; outer
     loop with V promotes; law: persisted κ ⊆ V-verified at every step, for
     every seed. This is the decree as a machine-checked invariant.
2. **Enroll `spec/neural/MapElites.hs`** into the Makefile (NEURAL list),
   amended for the phase-coordinate archive: bins over (φ, m_st, s) exact
   observables (PE7's φ = k/16 exactness makes φ-binning exact); insertion
   law (improve-or-fill + the dormant boldness/repulsion diversity as A6's
   open-mindedness); reset/persistence law mirroring H1.
3. **`spec/quantization/PairPermutations.hs` — the v1 discovery target.**
   Add the extremal frame: PP5 currently samples 100 permutations for
   adjacency-minima at coverage k ∈ {2,4,6,8,10,12,14}. Define:
   - the claim type: (k, permutation witness, adjacency value) — a Σ₁
     certificate, V = exact integer adjacency check (already written);
   - pinned best-known constants with provenance ("discovered by 𝔇 orbit,
     seed s, step t"), witness included as literal — WITNESS's witness-pinned
     style. Small-k cases closed exhaustively where tractable.
   Same pattern optionally for PE5 wall-extremal tilings (second domain).
4. Makefile tally 31 → 33+; zero failures; `make test` stays the gate.

## Phase 1 — Swift core (the 𝔇 runtime, in-app)

5. **`Tesseract/Tesseract/Discovery.swift`** (~200 lines, pure):
   - `protocol DiscoveryDomain`: `Candidate`; `generate(context:seed:)`;
     `verify(Candidate) -> Verdict` (exact; the A2 side);
     `experiment(Candidate, samples:) -> pass/fail` (the A4 side);
     `certificate(Candidate) -> Data` (serializable witness).
   - `DiscoveryOrbit`: deterministic seed schedule (seed derived from step
     index — reproducible; fixes the SobolExplorer reset defect for orbit
     use); step = generate → verify/experiment → update; orbit log line per
     event: `𝔇 step=t verdict=discovery|conjecture|refuted|reject …`.
   - Verdicts typed by tier: `.discovery(certificate)` only from exact V;
     `.conjecture(support)` from E. H1 enforced in types: the persisted
     archive's insert accepts only `.discovery`.
6. **`TileExtremalDomain.swift`** — v1's 𝒯: candidates = 16-tile
   permutations at coverage k; g = seeded swap-mutations from κ elites;
   V = exact integer adjacency (port of PP's `adjacency`, golden-tested
   against the spec's printed values); discovery = strictly better than
   pinned best-known → certificate = the permutation, logged and persisted.
7. **`PhaseArchive.swift`** — κ v2 (supersedes EliteMap's binning, keeps its
   bones): bins over (φ, m_st, s) via `DyadEnergy.frame` exact observables;
   cell stores gene/candidate + certificate + stats — NOT the full GIF
   (today's EliteCell stores a 64-frame GIF per cell; the certificate is
   enough, memory drops ~100×). Persistence: JSON in Application Support,
   loaded at launch; **persisted entries are V-verified only** (H1).
   Session-scoped conjecture list lives beside it, never serialized.
8. **Wiring (the one-line revival, off-surface):** after `encodeGIF`
   completes and state = .done, spawn the orbit: N steps (N small, ~64,
   budgeted < ~1 s CPU) of the ACTIVE domain. Inner tier: lattice-world
   candidates may use this burst's frames as E (capture-fitness →
   conjectures, session-scoped). Outer tier: v1's TileExtremalDomain runs
   fully synthetic, so every yield is V-verified and archivable. Orbit log
   via logger; no UI; no GIF byte touched (export contract untouched —
   orbit provenance stays OUT of the GIF in v1).
9. **Tests:** `DiscoveryTests` (spec-parity: T1 decay constants, H1
   invariant under adversarial verdict injection, orbit determinism —
   same seed ⇒ identical κ), `TileExtremalDomainTests` (V golden vectors
   vs spec output; a planted known optimum is found within bounded steps),
   `PhaseArchiveTests` (exact binning: φ = k/16 cases land in exact bins;
   persistence round-trip; H1: conjectures never serialize).

## Phase 2 — Metal (the A6 accelerator)

10. **Repair `MetalPipeline.processWithGene`**: bind the depths buffer
    (:619 TODO), un-alias depthBuf/outBuf (:587–590), async dispatch.
    Add `GeneForwardParityTests` — CPU `GeneWeights.forward` vs GPU
    `geneForward`, exact-equality contract under MTL_FAST_MATH NO (the
    refineAccumulate recipe; same IEEE ops in program order).
11. **`Discovery.metal`** — massively parallel V and population step for
    the extremal domain: one candidate per thread (integer-only adjacency
    → bit-exact trivially), thousands of candidates per dispatch; GPU
    verdict buffer reduced CPU-side in fixed order. This is T1's ε
    multiplied by four orders of magnitude of throughput.
12. Parity gate for every Discovery kernel: CPU==GPU exact equality test
    in the MetalRefineParityTests pattern (XCTAssertEqual, no tolerance).

## Phase 3 — The higher-order loop and v2

13. **Conjecture promotion queue**: lattice-world conjectures (from E on
    captures) that survive M bursts get scheduled for exact synthetic
    verification (on-device idle, or Mac). On V-pass they become
    discoveries and enter persisted κ; on refutation they die and U
    demotes their generator region. 𝔇² — the outer orbit's sentences are
    the inner orbit's conjectures.
14. **v2 𝒯 = the lattice world**: dyad/phase/palette identities (e.g.
    conjectured energy bounds, harmony extremes, phase-boundary
    configurations), verified by the exact V substrate (DY laws, PE
    identities, byte contracts). Gated on: PHASE-16 sign-offs (Risk 7 /
    Risk 10, still open) and Phase 0–2 green.
15. Optional: `GeneCapsule` revival — discoveries ride exports as the
    TESSERACT04 extension block (certificate-in-the-GIF, matching the
    DYAD STATS self-certification pattern). Deferred; export contract
    changes need their own decree check.

## Gates & risks

- Every phase: spec green (`make test`, zero failures) → build-for-testing
  device generic (no simulator) → contract tests UNMODIFIED → device pass
  owed to Daniel (feel + orbit log inspection).
- Risks: orbit CPU budget per burst (bounded N, measured before shipping);
  κ persistence format versioning; Gene.metal float parity may need the
  Q16 route if IEEE-order equality proves fragile; FACE-mode κ deferred;
  the beauty objective is Float32 — it may steer E but never gets to be V.
