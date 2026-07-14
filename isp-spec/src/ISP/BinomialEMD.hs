-- | 1D Earth-Mover (Wasserstein-1) distance between histograms, plus the
-- fingerprint-level beauty score derived from it.
--
-- Reference: Rubner, Tomasi, Guibas, /A Metric for Distributions with
-- Applications to Image Databases/ (1998). For 1D PMFs of equal length,
-- EMD = sum of absolute differences of CDFs.
--
-- Why EMD over KL: KL explodes whenever an observed bin is 0 but the target
-- places mass there. Our fingerprint regularly has 0 colors in outer bins.
-- EMD stays finite and respects bin ordering.
module ISP.BinomialEMD
  ( emd1D
  , maxEmd
  , beautyEMD
  , orderScoreBinomial
  ) where

import qualified Data.Vector as V
import ISP.BinomialBeauty
import ISP.Fingerprint (Fingerprint)
import ISP.FingerprintHistogram

-- | Wasserstein-1 distance between two normalized PMFs of equal length.
-- O(n). Both inputs should sum to 1 (or very close); no normalization is
-- performed here.
emd1D :: V.Vector Double -> V.Vector Double -> Double
emd1D p q
  | V.length p /= V.length q =
      error "emd1D: length mismatch"
  | otherwise =
      let diffs = V.zipWith (-) p q
          cdfDiff = V.scanl1 (+) diffs
      in V.sum (V.map abs cdfDiff)

-- | Upper bound on @emd1D p q@ when both are PMFs of length @n@:
-- achieved when one PMF is concentrated at bin 0 and the other at bin n-1.
-- Equals @n - 1@ for that case; more generally @fromIntegral (n - 1)@.
maxEmd :: Int -> Double
maxEmd n = fromIntegral (max 0 (n - 1))

-- | EMD from the fingerprint's count-histogram to the target model.
--
-- The observed histogram is rebinned to the model's bin count before
-- comparison so lengths match.
beautyEMD :: BinomialModel m => m -> Fingerprint -> Double
beautyEMD m fp =
  let observed = countHistogram (colorCounts fp)
      obsPMF   = let rebinned = rebinToLength (modelBins m) observed
                     s        = V.sum rebinned
                 in if s <= 0
                      then V.replicate (modelBins m) 0
                      else V.map (/ s) rebinned
      tgtPMF   = modelPMF m
  in emd1D obsPMF tgtPMF

-- | Birkhoff Order score in @[0,1]@: @1 - EMD / maxEMD@. Higher means the
-- observed histogram is closer to the target.
orderScoreBinomial :: BinomialModel m => m -> Fingerprint -> Double
orderScoreBinomial m fp =
  let n  = modelBins m
      mx = maxEmd n
  in if mx <= 0
       then 0
       else max 0 (1 - beautyEMD m fp / mx)
