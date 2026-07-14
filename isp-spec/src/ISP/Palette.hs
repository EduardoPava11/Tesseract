-- | 4D palette: K-means over (R, G, B, T) in Euclidean distance.
-- For the v0 spec we use raw channel space; a future revision can swap
-- in OkLab-for-color + scaled-T.
module ISP.Palette
  ( Palette (..)
  , Indices
  , PaletteMethod (..)
  , kmeans
  , kmeansStep
  , totalError
  , assign
  , dist4
  ) where

import qualified Data.Vector as V
import ISP.Tesseract

data PaletteMethod = KMeans4D | MedianCut4D
  deriving (Eq, Show)

newtype Palette = Palette { paletteCentroids :: V.Vector (T4D Double) }
  deriving (Eq, Show)

type Indices = V.Vector Int

dist4 :: T4D Double -> T4D Double -> Double
dist4 (T4D r1 g1 b1 t1) (T4D r2 g2 b2 t2) =
  let dr = r1 - r2
      dg = g1 - g2
      db = b1 - b2
      dt = t1 - t2
  in sqrt (dr * dr + dg * dg + db * db + dt * dt)

assign :: V.Vector (T4D Double) -> V.Vector (T4D Double) -> V.Vector Int
assign points cents =
  V.map (\p -> V.minIndex (V.map (dist4 p) cents)) points

kmeansStep
  :: V.Vector (T4D Double)
  -> V.Vector (T4D Double)
  -> (V.Vector (T4D Double), V.Vector Int)
kmeansStep points cents =
  let assigns  = assign points cents
      newCents = V.generate (V.length cents) $ \k ->
        let pts = V.ifilter (\i _ -> assigns V.! i == k) points
        in if V.null pts then cents V.! k else mean4 pts
  in (newCents, assigns)

mean4 :: V.Vector (T4D Double) -> T4D Double
mean4 v =
  let n  = fromIntegral (V.length v)
      s0 = T4D 0 0 0 0
      s  = V.foldl' add4 s0 v
  in T4D (t4R s / n) (t4G s / n) (t4B s / n) (t4T s / n)

add4 :: T4D Double -> T4D Double -> T4D Double
add4 (T4D r1 g1 b1 t1) (T4D r2 g2 b2 t2) =
  T4D (r1 + r2) (g1 + g2) (b1 + b2) (t1 + t2)

-- Run Lloyd's algorithm up to nIter iterations or convergence.
kmeans
  :: Int
  -> V.Vector (T4D Double)
  -> V.Vector (T4D Double)
  -> (Palette, Indices)
kmeans nIter points cents0 = go nIter cents0
  where
    go 0 c =
      let (_, a) = kmeansStep points c in (Palette c, a)
    go n c =
      let (c', a) = kmeansStep points c
          done    = V.and (V.zipWith (\x y -> dist4 x y < 1e-6) c c')
      in if done then (Palette c', a) else go (n - 1) c'

totalError :: V.Vector (T4D Double) -> Palette -> Indices -> Double
totalError pts (Palette cs) idx =
  V.sum (V.zipWith (\p i -> dist4 p (cs V.! i)) pts idx)
