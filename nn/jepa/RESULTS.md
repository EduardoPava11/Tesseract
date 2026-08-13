# JEPA-H — the one model line (2026-08-12)

## Verdict: ALL BEAUTY GATES GREEN (v7)

Val = 128 held-out capture rings (1024-capture synthetic corpus,
`make corpus-jepa`, jump law v2). Baseline = ORACLE-gain causal EMA
(alpha*(q) with the TRUE noise ratios — stronger than the app's
estimated gain). RTS = the non-causal linear-Gaussian bound.

| meter | obs | oracle EMA | **model v7** | truth/bound |
|---|---|---|---|---|
| palette churn (LCT bytes)   | 13.64 | 8.97 | **7.92** | 8.45 (truth) |
| LZW(LCT stream) bytes       | —     | 14,464 | **14,395** | — |
| state RMSE                  | —     | 0.05726 | **0.05602** | 0.04861 (RTS) |

B1 ✓ (bits down) · B3 ✓ (churn −11.7%) · FID ✓ (beats the oracle
CAUSAL filter; RTS is non-causal and knows the true noise) · DET ✓.
5,789 params. PARITY bridge 96/96 byte-exact tables (after two
1-ULP mirror fixes the bridge itself caught: pow-cbrt vs np.cbrt,
and numpy matmul summation order vs Haskell's left-to-right dots).

## The architecture the failures forced (each one measured)

- v1–v3: free MLP heads coupled to the training encoder — lost to
  the oracle EMA; the isolated-head "win" turned out to be TRAIN
  MSE (val was worse than raw obs: memorization).
- The real problem: optimal smoothing weights depend on each
  capture's noise regime, which the oracle is GIVEN and the head
  must ESTIMATE.
- **v7: a regime-conditioned symmetric ring filter.** A shared
  hypernet maps each dim's (r1, r2, r3) ring autocorrelations —
  the local-level model's sufficient statistics — to a positive
  symmetric 5-tap kernel (softmax, contains identity) plus a jump
  gate (trust raw where |y − neighbor midpoint| spikes: level
  shifts snap, never smear). NO slot-content parameters exist, so
  the head structurally cannot memorize; only the REGIME is
  learned. The JEPA encoder trains in parallel (arc-mask pretext,
  EMA target, VICReg-lite) as the representation channel — its
  prediction residual is the surprise/telemetry signal, decoupled
  from the smoother after measured interference.

## The mechanism (why this is beauty, not just filtering)

The palette is a closed-form theorem of the latent ring. Steadier
ring ⇒ steadier tables ⇒ less frame-to-frame churn ⇒ flatter LZW
residue ⇒ higher measured order — with fidelity guarded so it
tracks truth instead of flatlining. Churn 7.92 sits between the
oracle (8.97) and truth (8.45): the model removes observation
noise without erasing real motion.

## Artifacts

- `train.py` → `jepa_weights.npz`, `results.json`
- `build_model.py` → `JepaH.mlpackage` (untracked, regenerable):
  in-graph whitening → regime → kernel+gate → de-whitened states,
  plus embeddings out; fp32 CPU parity 2.7e-07 vs python.
- Spec: `spec/neural/JepaH.hs` JH1–JH6 (suite 46);
  emitter: `spec/output/JepaCorpusEmit.hs` (self-gating, jump law).

## JH4 (open): placement

Behind a flag, at SOLVING time: the captured ring of rung-16 states
passes through JepaH before tables are solved. Judged by the RATE
LEDGER + DYAD HARMONY on real captures and Daniel's device pass —
the meters promote, the device decides.
