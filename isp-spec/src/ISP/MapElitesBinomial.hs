-- | Extension of the 2D MapElites descriptor (rhythm, spread) with a third
-- axis 'desc3BellFit' measuring how closely the fingerprint's color-count
-- histogram matches a chosen binomial/dyadic-bell target.
--
-- The 2D grid in @spec/neural/MapElites.hs@ stays; this module only
-- supplies the new axis value, so a 3D-grid runner can be added later
-- without disturbing the 2D baseline.
module ISP.MapElitesBinomial
  ( Descriptor3D (..)
  , toDescriptor3D
  , rhythmEntropy
  , spreadEntropy
  ) where

import qualified Data.Vector as V
import ISP.BinomialBeauty
import ISP.BinomialEMD (orderScoreBinomial)
import ISP.ColorDouble (paletteSize)
import ISP.Fingerprint (Fingerprint (..))
import ISP.FingerprintHistogram (colorCounts)

data Descriptor3D = Descriptor3D
  { desc3Rhythm  :: !Double   -- ^ H(color-count distribution) / log(palette)
  , desc3Spread  :: !Double   -- ^ palette coverage = nonzero / palette
  , desc3BellFit :: !Double   -- ^ orderB against the chosen binomial target
  }
  deriving (Eq, Show)

-- | Build a 3D descriptor for a fingerprint.
toDescriptor3D :: BinomialModel m => m -> Fingerprint -> Descriptor3D
toDescriptor3D m fp =
  let counts = colorCounts fp
  in Descriptor3D
       { desc3Rhythm  = rhythmEntropy counts (paletteSize (fpPalette fp))
       , desc3Spread  = spreadEntropy counts
       , desc3BellFit = orderScoreBinomial m fp
       }

-- | Normalized Shannon entropy of the color-count vector treated as a PMF.
-- In @[0,1]@: 1 when counts are uniform, 0 when one color dominates.
rhythmEntropy :: V.Vector Int -> Int -> Double
rhythmEntropy counts n =
  let total = fromIntegral (V.sum counts) :: Double
      logN  = log (fromIntegral n)
      h     = if total <= 0
                then 0
                else V.sum $ V.map
                       (\c -> let p = fromIntegral c / total
                              in if p <= 0 then 0 else negate (p * log p))
                       counts
  in if logN <= 0 then 0 else h / logN

-- | Palette coverage: fraction of palette entries with non-zero count.
-- In @[0,1]@.
spreadEntropy :: V.Vector Int -> Double
spreadEntropy counts
  | V.null counts = 0
  | otherwise     =
      let nonZero = V.length (V.filter (> 0) counts)
          total   = V.length counts
      in fromIntegral nonZero / fromIntegral total
