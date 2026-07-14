-- | Color-doubling by 2-means split of each existing bucket.
--
-- For each of the n current buckets, run Lloyd's algorithm (2 clusters,
-- deltaE distance) over the reference pixels assigned to that bucket and
-- emit the two cluster means. Falls back to a small L-axis perturbation
-- when a bucket is empty.
module ISP.ColorDouble.KMeans
  ( KMeansSplit (..)
  ) where

import qualified Data.Vector as V
import ISP.ColorDouble
import ISP.Oklab

-- | Iteration budget for the inner 2-means.
newtype KMeansSplit = KMeansSplit { kmsIters :: Int }
  deriving (Eq, Show)

instance ColorDouble KMeansSplit where
  double (KMeansSplit nIter) pal ref =
    let buckets = bucketIndices pal ref
        pairs   = V.imap (splitBucket nIter pal) buckets
        newPal  = palettePair pairs
        newIdx  = assignNearest newPal ref
    in (newPal, newIdx)

-- | Split one bucket into 2 Oklab centroids via Lloyd.
splitBucket :: Int -> OklabPalette -> Int -> V.Vector Oklab -> (Oklab, Oklab)
splitBucket nIter pal k pts
  | V.null pts = perturb (pal V.! k)
  | V.length pts < 2 =
      let c = V.head pts in perturb c
  | otherwise =
      let c = pal V.! k
          (c0, c1) = perturb c
      in lloyd nIter pts c0 c1

-- Small symmetric perturbation along the L axis so the two seeds differ.
perturb :: Oklab -> (Oklab, Oklab)
perturb (Oklab l a b) =
  (Oklab (l - 0.02) a b, Oklab (l + 0.02) a b)

lloyd :: Int -> V.Vector Oklab -> Oklab -> Oklab -> (Oklab, Oklab)
lloyd 0 _   c0 c1 = (c0, c1)
lloyd n pts c0 c1 =
  let (left, right) = V.partition (\p -> deltaE p c0 <= deltaE p c1) pts
      c0' = if V.null left  then c0 else meanOklab left
      c1' = if V.null right then c1 else meanOklab right
      moved = deltaE c0 c0' + deltaE c1 c1'
  in if moved < 1e-6 then (c0', c1') else lloyd (n - 1) pts c0' c1'

meanOklab :: V.Vector Oklab -> Oklab
meanOklab v =
  let n = fromIntegral (V.length v)
      (sL, sA, sB) = V.foldl' (\(l,a,b) (Oklab l' a' b') -> (l+l', a+a', b+b'))
                               (0, 0, 0) v
  in Oklab (sL / n) (sA / n) (sB / n)
