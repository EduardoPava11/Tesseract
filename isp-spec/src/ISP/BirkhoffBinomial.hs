-- | Birkhoff aesthetic measure M = O/C, with Order redefined as
-- /closeness to a binomial / dyadic-bell target/ instead of /distance from
-- uniform/. Complexity stays as normalized Shannon entropy (Rigau, Feixas,
-- Sbert 2007).
--
-- The existing 'spec/output/GIFAnalysis.hs::birkhoffFrame' is unchanged;
-- this is a sibling scorer designed for the 16x16x64 fingerprint.
module ISP.BirkhoffBinomial
  ( orderB
  , complexityB
  , birkhoffB
  , shannonEntropyNorm
  ) where

import qualified Data.Vector as V
import ISP.BinomialBeauty
import ISP.BinomialEMD (orderScoreBinomial)
import ISP.ColorDouble (paletteSize)
import ISP.Fingerprint (Fingerprint (..))
import ISP.FingerprintHistogram (colorCounts)

-- | Order: closeness to the chosen 'BinomialModel' target. In @[0,1]@.
orderB :: BinomialModel m => m -> Fingerprint -> Double
orderB = orderScoreBinomial

-- | Complexity: normalized Shannon entropy of the fingerprint's color
-- distribution, in @[0,1]@. High when all 64 colors are used evenly.
complexityB :: Fingerprint -> Double
complexityB fp =
  let counts  = colorCounts fp
      total   = fromIntegral (V.sum counts) :: Double
      n       = paletteSize (fpPalette fp)
      logN    = log (fromIntegral n)
  in if total <= 0 || logN <= 0
       then 0
       else shannonEntropyNorm counts / logN

-- | Shannon entropy of an integer histogram, in nats (not normalized).
-- Zero bins contribute zero.
shannonEntropyNorm :: V.Vector Int -> Double
shannonEntropyNorm h =
  let total = fromIntegral (V.sum h) :: Double
  in if total <= 0
       then 0
       else V.sum $ V.map
              (\c -> let p = fromIntegral c / total
                     in if p <= 0 then 0 else negate (p * log p))
              h

-- | Birkhoff on binomial: returns @(M, O, C)@. M = O / max(C, eps).
--
-- A fingerprint with a bell-shaped color histogram and reasonable entropy
-- lands at high M. A flat/random fingerprint has high C and low O, so M
-- stays low. A single-color fingerprint has high O (close to a point-mass
-- target could match trivially) but near-zero C, so M is numerically large
-- — callers can cap or regularize.
birkhoffB :: BinomialModel m => m -> Fingerprint -> (Double, Double, Double)
birkhoffB m fp =
  let o = orderB m fp
      c = complexityB fp
      m' = o / max c 1e-6
  in (m', o, c)
