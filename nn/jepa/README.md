# nn/jepa — THE model. One path. Beauty is the objective.

Daniel's ruling (2026-08-12): ONE model — MLX-trained JEPA-H,
ported to iPhone. Not a zoo of task heads. Performance is in
service of BEAUTY, and beauty is measured by the meters the app
already ships in every GIF.

## The one path

    synthetic trajectory corpus  (the app's own stochastic laws)
        -> MLX JEPA-H            (hierarchical: the rungs 16/32/64
                                  over the 3.2s loop's latent ring;
                                  predict in EMBEDDING space; EMA
                                  target; lawful masking = the
                                  polyphase/time-arc partitions)
        -> beauty gates          (closed-loop, see below)
        -> coremltools           -> JepaH.mlpackage -> iPhone

No other model artifacts. Assignment stays with DyadAssign (exact
law + its shipped engine). The retired nn/descent lab contributes
its LAWS (DL6/DL7) and its training recipes only.

## What the JEPA-H is FOR (the deployed effect)

It learns the dynamics of the capture's generating latent — the
13-number stats stream, the mixture state, the rung-16 pooled
fields — and its predictions STEADY the palette: warm starts and
surprise-gated smoothing of the slow state. A steadier generating
state means less palette churn frame-to-frame, flatter LZW
residue, higher measured order. That is the mechanism by which a
predictive model buys beauty.

## Beauty gates (the ONLY promotion criteria)

Closed-loop on synthetic captures — run the exact pipeline with
and without the model in the loop, and require:

  B1  M rises            (RATE LEDGER: M = (8 - K)/8, the
                          Birkhoff-Rigau meter already in the wire)
  B2  harmony holds/rises (DYAD HARMONY, Ou & Luo — already wired)
  B3  churn falls        (palette temporal churn: mean byte delta
                          between consecutive LCTs — the DY8
                          flicker concern, made a number)
  B4  fidelity holds     (PHASE F distortion does not regress)

Latent-space losses train the model; ONLY these meters promote it.
Accuracy-vs-teacher is not a promotion criterion for this line.
Final gate, as ever: Daniel's device pass.

## Order of work (spec first, one artifact per step)

  JH0  spec/neural/JepaH.hs — the trajectory law (stats drift under
       the derived-gain/MS dynamics), the ring/rung masking
       partitions, the embedding contract, anti-collapse invariants
  JH1  trajectory corpus emitter (extends the self-gating pattern;
       TRAJECTORIES, not i.i.d. trees)
  JH2  MLX JEPA-H training + beauty gates in-lab (the lab can
       compute M and churn itself: LZW + LCT deltas in python)
  JH3  JepaH.mlpackage fold + parity
  JH4  placement behind a flag; device pass decides
