# tesseract-isp

> **DEPRECATED (2026-07-15):** Tesseract is now a **front-camera-only** app; the
> rear-camera Bayer-DNG track this package specifies has been removed. The Swift
> port of this spec (64-DNG RGBT burst mode) is preserved on the
> `archive/rear-rgbt` branch. The package is kept as a read-only reference —
> the photon-time estimators and uncertainty carrier remain correct and may be
> revived if a raw-count sensor path ever returns. Live specs for the app are
> in `spec/`.

Physics-grounded Haskell specification of the Tesseract iPhone app's custom ISP.

Two 48MP ProRAW DNGs -> a 4D GIF along axes **(R, G, B, T)**, where `T` is a
per-pixel physical quantity derived from exposure, gain, and photon wavelength —
not a frame index. Uncertainty is propagated through every pyramid scale, and
the Heisenberg energy-time bound clamps the T-axis precision from below.

This package is the **spec**. The Swift / Metal implementation in the Tesseract
app should match the types, laws, and golden JSON vectors produced here.

## Layout

```
src/ISP/
  Sensor/Physics.hs     -- lambda per channel, E=hc/lambda, Heisenberg floor
  Sensor/Noise.hs       -- Poisson+Gaussian, NoiseProfile (alpha, beta)
  Sensor/Anscombe.hs    -- variance stabilization
  Sensor/Uncertainty.hs -- Uncertain a carrier
  Bayer.hs              -- (R, Gr, Gb, B) quad + CFA
  Time.hs               -- TimeEstimator: Poisson | Effective | Heisenberg
  DNG.hs                -- minimal DNG/TIFF reader
  Pyramid.hs            -- scale hierarchy, S*K = 4096
  Tesseract.hs          -- (R, Gr, Gb, B, T) -> (R, G, B, T) projection
  Palette.hs            -- 4D K-means, delta-E, 256-color quantization
  GIF.hs                -- GIF89a encode (JuicyPixels)
  Pipeline.hs           -- type-indexed Stage GADT
  Laws/                 -- QuickCheck properties

app/Main.hs             -- tesseract-isp-run <dng1> <dng2> -o out.gif
golden/Main.hs          -- tesseract-isp-golden -> JSON vectors for Swift
test/Spec.hs            -- runs every Laws module
fixtures/dng/           -- tiny synthetic DNGs
```

## Build & test

```
cd Tesseract/isp-spec
cabal update
cabal build all
cabal test
cabal run tesseract-isp-run -- fixtures/dng/a.dng fixtures/dng/b.dng -o /tmp/out.gif
cabal run tesseract-isp-golden
```

## Statistical tools

`T_pixel` estimators (user-selectable at run time):

- **Poisson interarrival** (default): `T = t_exposure / N_hat` — MLE under Poisson.
- **Effective integration**: `T = N_hat / Phi_ref` — calibration rescaling.
- **Heisenberg precision**: carried as `sigma_T_floor = lambda / (4 pi c sqrt(N))`.

Mixed Poisson-Gaussian noise is handled with the Anscombe transform, giving
unit-variance residuals so the orthonormal Haar pyramid preserves
Cramer-Rao-efficient estimates across scales.

## Reference

Wavelength anchors (Bayer filter peak transmission):

| Channel | lambda (nm) | FWHM (nm) | Peak T (%) |
|---------|-------------|-----------|------------|
| R       | 640         | 55        | 75         |
| Gr / Gb | 546         | 66        | 82         |
| B       | 427         | 76        | 88         |

Physical constants (CODATA 2019):

- `h  = 6.62607015e-34 J*s`
- `c  = 299792458 m/s`
- `hc = 1.98644586e-25 J*m`
- `hbar = h / (2*pi)`
