# THE OCCUPANCY WORKFLOW — all 256 alive at every frame, across three rungs

Daniel, 2026-08-14: *"I am trying to ensure that 256 colors are used at
every frame, to maximize the impact of color. Because I am using a multi
scale in x,y,t for the 16×16×16 == 32×32×32 == 64×64×64 I require strict
consideration of the data pipeline."* And: *"we need a workflow for this,
since the scales are different — a 16×16 has more information compressed
than a 64×64."*

This is the strategy document. `spec/statistics/TilingEntropy.hs` (TE1–TE10)
is the algebra it is denominated in; `spec/neural/WeaveState.hs` (WS1–WS10)
is the state it is measured with. Nothing here has been implemented — every
step below changes pixels and therefore owes spec axioms, a ledger delta,
and a device pass.

---

## 0. Why the scales need a workflow and not a switch

The Local Color Table is 768 bytes — **6144 bits, fixed at every rung** —
while the index payload scales with the cells. Measured with the encoder's
own LZW law:

| rung | frame | index LZW | + table | bits/cell | table share |
|------|-------|-----------|---------|-----------|-------------|
| 16²  | balanced (a permutation) | 2324 b | 8468 b  | **33.1** | **72.6%** |
| 16²  | collapsed to 2 entries   |  297 b | 6441 b  | 25.2 | 95.4% |
| 32²  | balanced, coherent       | 7446 b | 13590 b | 13.3 | 45.2% |
| 32²  | balanced, random         | 10174 b| 16318 b | 15.9 | 37.7% |
| 64²  | balanced, coherent       | 15894 b| 22038 b | 5.4  | 27.9% |
| 64²  | balanced, random         | 44686 b| 50830 b | 12.4 | 12.1% |
| 64²  | collapsed to 2 entries   | 1125 b | 7269 b  | 1.8  | 84.5% |

Three readings, all load-bearing:

1. **Daniel is right about density.** A rung-16 cell carries 6× the wire a
   rung-64 cell does. At rung 16 the palette is three-quarters of the
   payload: *the palette IS the image*.
2. **Therefore unused entries hurt most where the frame is smallest.** A dead
   entry at rung 64 wastes 24 bits out of ~22000 (0.1%). At rung 16 it
   wastes 24 bits out of 8468 (0.3%) *and* it is 1/256th of the only real
   content the frame has. Occupancy is a coarse-rung problem first.
3. **Balance is not the same as incompressibility.** At rung 64, balanced
   costs 15894 b when arranged coherently and 44686 b when scrambled — the
   arrangement is worth 2.8×, and the scrambled version is *larger than the
   raw 32768-bit payload* (LZW expands noise). Using all 256 is free; using
   all 256 *incoherently* is not. E_hist and E_wall are independent strata
   (WS3), and this table is what that independence is worth in bytes.

At rung 16 there is one more fact with no slack in it: 16² = 256 = K, so a
balanced frame is a **bijection** — every colour exactly once. Its index
stream has no repeated symbol, so LZW cannot compress it at all (2324 b for
both the coherent and the scrambled arrangement, above). That is the price
of the coarsest rung's perfection, it is 2324 bits, and it is not negotiable
by any arrangement.

---

## 1. The principle: AUTHOR FINE, VALIDATE COARSE

Pooling runs 64 → 32 → 16, so the coarse frame is *derived*; the constraint
must be authored where the data is (the fine rung) and validated where the
value is (the coarse rung).

★ **CORRECTED 2026-08-14 by the architecture workflow — this section claimed a
theorem it does not have.** See `docs/weave-architecture.md` §1.1. The claim
was that phase-balancing the dither makes the 16 → 4 → 1 nesting free. Three
findings refute it:

- `poolAt` is a stride-2 **SUM** over all eight block members; the phase moves
  the block ORIGIN, it does not select a sublattice, and TL11 proves the eight
  phases sum to a [1,2,1]³ tent (`spec/output/TriScaleLadder.hs:313-320,
  :350-357, :359-386`). "The 2×2×2 pool IS a phase selection" misreads
  TL10–TL12.
- The shipped coarse reads pool the FEED and then call `assign`
  (`DyadPipeline.swift:1032-1044`), so a coarse index is `quantize(mean)`,
  never a decimated fine index. On a near-monochrome wall the pooled field is
  one point and takes ONE index at every coarse rung, however the fine frame
  is dithered. Occupancy does not descend at all.
- The 2000/2000 matching evidence covers a one-step 4:1 spatial selection at
  phase 0. Two κ steps across all eight phases is a 3-index axial
  transportation problem; axial polytopes are not integral and Hall/Birkhoff
  does not extend.

**AUTHOR FINE, VALIDATE COARSE survives as a DIRECTION** — the constraint
belongs in the dither, not in a per-rung repair pass — but the free-inheritance
claim is downgraded from THEOREM to OPEN. Rung 32 becomes the certificate that
measures the gap rather than a rung that inherits it.

---

## 2. The steps

Each step declares: what changes, what it costs, its gate, and the ruling
owed. Steps are ordered by evidence, not by ambition — O0 and O1 change no
pixels and must land before anything else is judged.

### O0 — CENSUS (no pixel changes)

Per-frame, per-rung occupancy census on the existing device GIF: entries
used, the occupancy histogram, E_hist in bits, the table's share of the
wire, and the split by pixel class (figure / band / far).

**Why first:** every later step is scored against it, and it resolves a live
discrepancy. The shipped code's per-frame ceiling is 128 (figure) + 16
(band σ via `canonical16`) + 1 (far → 255) = **145 of 256**, but the palette
audit reports 164 used. Either the two numbers have different scopes (cube
vs frame) or a path is unaccounted for. No baseline is trustworthy until
that closes.

**Gate:** the census reproduces the audit's ground-half number (10 of 128)
from first principles. **Ruling owed:** none.

### O1 — RATE ACCOUNTING (no pixel changes)

Publish the §0 table per capture in the RATE LEDGER: bits/cell and table
share at each rung. Turns "the scales are different" into a number the later
steps move.

**Gate:** the ledger's own LZW is the only source. **Ruling owed:** none.

### O2 — THE FAR LAW (biggest single lever)

`assignRoles` sends every far pixel to `DyadPalette.backgroundIndex` = 255 —
**one entry for what is usually most of the frame.** DY6 records a different
law: far pixels take the σ-mirror of their own nearest primary. Restoring it
takes the far σ ceiling from 1 to 128.

**Cost:** changes every background pixel. **Gate:** measure the staged ŷ
spread over far pixels first — if the γ-staged far field really is
near-constant, the mirror buys nothing and the constant is correct.
**Ruling owed:** which law is current.

### O3 — THE σ PREFIX (the diagonal-vs-flat ruling)

`pairDitherFrame` quantizes σ blur targets at the 16 depth-4 nodes and emits
`255 − canon[best]` — at most 16 of 128 σ entries, by construction. The
comment states the intent: *"the background's palette rate drops 8:1 exactly
where its spatial rate does."* That is the diagonal ladder, and it is
exactly what forbids all-256 for the background.

Lifting it to the full 128 leaves keeps the blur — the blur comes from the
4×4×4 spacetime pooling, not from palette depth — and raises the σ ceiling
16 → 128.

**Cost:** one loop bound; changes every band pixel. **Gate:** ledger delta +
device pass; v7's "no blue haze" ruling must survive visually.
**Ruling owed:** diagonal ladder or flat 256. They are mutually exclusive
for the σ half, and this is the decision the whole workflow turns on.

### O4 — PHASE-BALANCED DITHER (the multiscale constraint)

Author the 16 → 4 → 1 nesting in the dither: spread each colour's
occurrences evenly over the polyphase classes, so every coarse rung inherits
balance without a repair pass.

**Cost:** constrains dither placement; distortion rises by the placement
gap. **Gate:** rung-32 and rung-16 occupancy come out balanced *without*
touching them. **Ruling owed:** none if O3 rules flat; moot if it rules
diagonal.

### O5 — TRANSPORT (only if O2–O4 fall short)

Hard balance as a transportation problem: every entry receives exactly N/K
pixels (16/4/1), uniform marginals, solved by Sinkhorn or auction — fixed
iterations, the ANE shape. Constrains **assignment**, never the generated
table, so the analytic tree's provenance law (the table stays a pure
function of the traced 13 numbers) is untouched.

**Cost:** distortion rises by the transport gap; the solve is per frame.
**Gate:** E_hist = 0 exactly, and the distortion cost measured against the
nearest-neighbour baseline. **Ruling owed:** whether guaranteed balance is
worth measured distortion.

### O6 — ACCEPTANCE ★ RETIRED 2026-08-14

The bijection below requires figure mass = ground mass exactly (aliveness per
frame is capped at min(128, m_F·N) + min(128, m_g·N), so at m_g = 0.75 rung 16
caps at 192/256 — the role mass split, not the alphabet width, is the binding
constraint). Replaced by the CONDITIONAL ground state: uniform *within* each
half, residual floor E₀ = N(1 − h(m_g)) = 773 / 193 / 48.3 b at rungs
64 / 32 / 16, declared and budgeted. See `docs/weave-architecture.md` §2.8.

Superseded text follows.

### O6 — ACCEPTANCE: the rung-16 bijection

The test the whole workflow exists for: pool the finished cube to rung 16
and check the frame is a **permutation of the 256** — every colour exactly
once, E_hist = 0, no repair applied. If that holds, all-256 holds at every
rung above it by the nesting, and it holds by construction rather than by
inspection.

---

## 3. Risks

- **The two goals point opposite ways on one axis and not on the other.**
  All-256 drives H₀ → 8 bits/px, which is the *maximum* zeroth-order wire
  cost — directly against the rate ladder's declared direction. The escape
  is real but narrow: keep the arrangement coherent and the 2.8× in §0 is
  recovered at rung 64. At rung 16 there is no escape, and 2324 bits is the
  bill.
- **O3 reverses a shipped ruling.** The diagonal ladder is not an accident
  to be repaired; it is v7 + P2 working as designed. Lifting it is a
  direction change and should be recorded as one.
- **Provenance.** Balance enforced on the palette side would break the
  analytic tree's "table is a pure function of the traced numbers" law.
  Every step above therefore acts on assignment or placement, never on
  generation.
- **Rung 16 has zero slack.** Any upstream deviation destroys the bijection
  outright — there is no partial credit at the coarsest rung. That is why
  O4 authors the constraint instead of repairing it.
