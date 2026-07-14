-- | Histograms derived from a 16x16x64 Fingerprint.
--
-- 'colorCounts' counts each palette index's usages in the 16x16 grid.
-- 'countHistogram' is the histogram of those counts — bin k = "# colors
-- used exactly k times". This is what we compare against a 'BinomialModel'.
module ISP.FingerprintHistogram
  ( colorCounts
  , countHistogram
  , rebinToLength
  , histogramPMF
  , uniformHistogram
  ) where

import qualified Data.Vector as V
import ISP.ColorDouble (paletteSize)
import ISP.Fingerprint (Fingerprint (..))
import ISP.Oklab (planeData)

-- | Count how many cells use each palette index. Length = palette size.
--
-- Invariants:
--
--   * @V.sum (colorCounts fp) == 256@ (the 16x16 cell count)
--   * @V.length (colorCounts fp) == paletteSize (fpPalette fp)@
colorCounts :: Fingerprint -> V.Vector Int
colorCounts fp =
  let n    = paletteSize (fpPalette fp)
      idxs = planeData (fpIndices fp)
  in V.generate n $ \k ->
       V.length (V.filter (== k) idxs)

-- | Histogram of color-counts: bin /k/ = number of colors whose count is /k/.
-- Length = @max count + 1@.
--
-- Invariants:
--
--   * @V.sum (countHistogram c) == V.length c@  (one bucket per color)
--   * @sum [ k * h[k] | k <- bins ] == V.sum c@ (total cells preserved)
countHistogram :: V.Vector Int -> V.Vector Int
countHistogram counts
  | V.null counts = V.empty
  | otherwise =
      let m = V.maximum counts
      in V.generate (m + 1) $ \k ->
           V.length (V.filter (== k) counts)

-- | Re-sample an integer histogram into exactly @n@ bins, preserving total
-- mass and relative position. Used to align observed histograms with model
-- PMFs of a given length. Treats the source as piecewise-constant over @[0,1)@.
rebinToLength :: Int -> V.Vector Int -> V.Vector Double
rebinToLength n src
  | n <= 0        = V.empty
  | V.null src    = V.replicate n 0
  | V.length src == n = V.map fromIntegral src
  | otherwise =
      let m  = V.length src
          s  = V.map fromIntegral src :: V.Vector Double
      in V.generate n $ \i ->
           let lo = fromIntegral (i * m)     / fromIntegral n
               hi = fromIntegral ((i + 1) * m) / fromIntegral n
               jl = floor lo :: Int
               jh = min (m - 1) (floor hi)
           in if jl == jh
                then (hi - lo) * (s V.! jl)
                else   (fromIntegral (jl + 1) - lo) * (s V.! jl)
                     + V.sum (V.slice (jl + 1) (max 0 (jh - jl - 1)) s)
                     + (hi - fromIntegral jh) * (s V.! jh)

-- | Convert an integer histogram to a normalized PMF.
histogramPMF :: V.Vector Int -> V.Vector Double
histogramPMF h
  | V.null h  = V.empty
  | otherwise =
      let s = fromIntegral (V.sum h) :: Double
      in if s <= 0 then V.replicate (V.length h) 0
                   else V.map ((/ s) . fromIntegral) h

-- | Uniform histogram over a palette of given size, assigning the expected
-- per-color count. Used as the anti-beauty baseline.
uniformHistogram :: Int -> Int -> V.Vector Int
uniformHistogram cells paletteN =
  let q = cells `div` paletteN
  in V.replicate paletteN q
