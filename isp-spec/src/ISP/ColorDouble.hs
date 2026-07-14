-- | Typeclass for the "color-doubling" pyramid operator.
--
-- Given a palette of n Oklab colors and an Oklab reference plane at the
-- next pyramid level, produce a palette of 2n colors plus a nearest-neighbor
-- assignment of the reference onto that palette.
--
-- Three candidate instances live under 'ISP.ColorDouble.*' (KMeans, PCA,
-- Coproduct). The choice is deferred: benchmark across the Birkhoff beauty
-- score ('spec/output/GIFAnalysis.hs::gradeGIF') before pinning.
module ISP.ColorDouble
  ( -- * Typeclass
    ColorDouble (..)
    -- * Palette type
  , OklabPalette
  , mkPalette
  , paletteSize
  , paletteColors
    -- * Shared helpers
  , assignNearest
  , bucketIndices
  , palettePair
  ) where

import qualified Data.Vector as V
import ISP.Oklab

-- | A palette of Oklab centroids.
type OklabPalette = V.Vector Oklab

mkPalette :: [Oklab] -> OklabPalette
mkPalette = V.fromList

paletteSize :: OklabPalette -> Int
paletteSize = V.length

paletteColors :: OklabPalette -> [Oklab]
paletteColors = V.toList

-- | Color-doubling operator. Laws (see ISP.Laws.ColorDouble):
--
--   C1 - 'paletteSize' of output = 2 * 'paletteSize' of input
--   C2 - pairing the output palette (2i, 2i+1) -> i recovers the input
--        palette when the split is trivial (identical centroids).
class ColorDouble op where
  double
    :: op
    -> OklabPalette   -- ^ current palette (size n)
    -> Plane Oklab    -- ^ reference plane at the next level (size s/2)
    -> (OklabPalette, Plane Int)  -- ^ new palette (size 2n), indices at s/2

-- | Nearest-neighbor assignment of each plane pixel to a palette index.
assignNearest :: OklabPalette -> Plane Oklab -> Plane Int
assignNearest pal p =
  planeGenerate (planeW p) (planeH p) $ \x y ->
    V.minIndex (V.map (deltaE (planeIndex p x y)) pal)

-- | Collect the reference pixels that currently land in each palette bucket.
-- Returns a vector of length 'paletteSize' of buckets.
bucketIndices :: OklabPalette -> Plane Oklab -> V.Vector (V.Vector Oklab)
bucketIndices pal p =
  let assigns = assignNearest pal p
      n = paletteSize pal
      flat = planeData p
      idxs = planeData assigns
  in V.generate n $ \k ->
       V.ifilter (\i _ -> idxs V.! i == k) flat

-- | Assemble a doubled palette by flattening per-bucket pairs. The helper
-- interleaves so children of bucket k sit at positions (2k, 2k+1).
palettePair :: V.Vector (Oklab, Oklab) -> OklabPalette
palettePair pairs =
  V.generate (V.length pairs * 2) $ \i ->
    let (p0, p1) = pairs V.! (i `div` 2)
    in if even i then p0 else p1
