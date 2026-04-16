# Deprecated Specs

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
