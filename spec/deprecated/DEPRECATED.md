# Deprecated Specs

## SurfaceMachine.hs (deprecated 2026-08-14)

### What it was
The six-state surface machine from Daniel's 2026-08-12 ruling: "the app
should be made of a strict grid; squares make words; the grid is a state
machine that surfaces what the app is doing." One square word per state,
WAKING to WATCHING to WEAVING to SOLVING to SEALED, plus REFUSED. Laws
SM1 through SM5, all green.

### Why it was removed
The 2026-08-13 decree "EDIT is the whole app" produced EditMachine.hs,
which SUPERSEDES this state set. The replacement is forced, not
preferred. The two edge relations disagree IN DIRECTION on five pairs
(waking to watching, solving to sealed, sealed to watching, exportFailed
to watching, unknown to waking), and both specs state EXACT-SET laws, so
no union of the two relations can satisfy both. One word also collides:
Refused Unknown speaks "REFUSED" under EditMachine and spoke "ERROR"
here, and EM6 requires distinctness.

The Swift port and its tests were deleted at the same commit that landed
EditMachine.swift. This file was not, so for two days the CORE suite ran
BOTH machines and reported 59 green while two of those specs contradicted
each other. A test runner cannot see that. Only the registry can.

### What replaced it
`spec/ui/EditMachine.hs` (EM1 to EM13) and `Tesseract/UI/EditMachine.swift`.
SM1 to SM5 are not discarded, they are re-proved over the larger machine:

- SM1 (distinct square words)          becomes EM6
- SM2 (the capture arc admits no skips) becomes EM3
- SM4 (terminals are the hardware refusals) becomes EM7
- SM5 (one scene per state)            becomes the ContentView switch
- SM3 (the working states refuse interruption) SPLITS into EM4 and EM5

The split is the one law that bent, and the reason is ownership rather
than latency. EM4: a solve that is a CAPTURE must complete, because
SOLVING owns the only copy of a moment that will never recur. EM5: a
solve that is a TICK must be abandonable, because TUNING owns a pure
function of data already safely held, so discarding a tick costs nothing
but the compute already spent. Under the tick decree the solve is the
steady state rather than an event, so an inherited SM3 would mean the
dials never answer.

Full derivations live in the headers of both EditMachine files. Do not
reintroduce a second surface machine.

## KataGoClient.hs (deprecated 2026-04-15)

### What it was
KataGo is a Go-playing neural network. The idea was to treat each 19x19
color-comparison block as a Go position and run KataGo's NN to get:
- **policy** (move probabilities) → "where to dither"
- **ownership** (territory strength) → "how strongly to dither"

The insight: contested territory (ownership near 0) = pixels at color
boundaries = good dithering candidates. High-policy positions = the
most impactful dithering targets.

### Why it was removed
1. **Opaque.** The NN is a black box. You cannot see what it computes
   or verify why it chose a particular dithering pattern. The Go board
   analogy is elegant but the NN evaluation breaks the chain of
   transparency that makes the rest of the spec verifiable.

2. **Over-engineered.** Territory counting and liberty analysis from
   GoBoard.swift already give us exactly what we need:
   - Liberties = boundary pixels = dithering candidates
   - Complexity = (liberties + empty) / total = dithering budget
   - Territory score = channel balance
   These are O(n) operations on 361 pixels. Transparent. Testable.

3. **Dead weight in practice.** The KataGo ownership result was computed
   in CameraManager.swift but never actually fed back into quantization.
   The contested-pixel count appeared in a status message only. The real
   dithering was always driven by GoBoard territory analysis.

4. **22.5 MB model** bundled into the app for marginal benefit on ~30%
   of blocks, with a 10-second async load at encode time.

### What replaced it
`GoBoard.swift` territory + liberties analysis. Same Go-board metaphor,
fully transparent, no NN. The spec function is now:

```haskell
deriveGuide :: GoEv -> DGuide
deriveGuide ev = DGuide (gLibs ev) (gCmplx ev)
```

Liberties ARE the dithering candidates. Complexity IS the budget.
Nothing hidden. Everything countable.

### Files removed from Swift app
- `GoEvaluator.swift` — CoreML KataGo wrapper
- `KataGoModel19x19fp16m1w8LiCh.mlpackage` — 22.5 MB model
- `gtp_logs/` — GTP protocol debug logs
- `needsNNEval()` from GoBoard.swift
- All KataGo references from CameraManager.swift
