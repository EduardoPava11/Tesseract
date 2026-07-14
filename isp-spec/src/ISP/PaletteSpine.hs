-- | Hybrid spine + local-delta 256-color global palette.
--
-- All 64 frames share a "spine" of colors (built from a K-means over every
-- frame's fingerprint palette). Each 4-frame group also carries its own
-- "delta" palette (built from the group-local residuals). At render time
-- the effective per-frame palette is @spine ++ delta[g]@ where g is the
-- group index; by construction its size is always 256.
module ISP.PaletteSpine
  ( SpineConfig (..)
  , defaultSpineConfig
  , GlobalPalette (..)
  , buildGlobalPalette
  , effectivePalette
  , paletteSpineTotal
  , kmeansOklab
  ) where

import qualified Data.Vector as V
import ISP.ColorDouble
import ISP.Fingerprint
import ISP.Oklab

-- | Size allocation for the spine+delta split. Constraint:
-- 'spineSize' + 'deltaSize' = 256.
data SpineConfig = SpineConfig
  { spineSize :: !Int
  , deltaSize :: !Int
  }
  deriving (Eq, Show)

-- | The plan's leaning choice. Benchmark other allocations before pinning.
defaultSpineConfig :: SpineConfig
defaultSpineConfig = SpineConfig { spineSize = 192, deltaSize = 64 }

-- | Total budget this spec commits to.
paletteSpineTotal :: Int
paletteSpineTotal = 256

-- | One spine plus one delta per 4-frame group. For a 64-frame GIF there
-- are 16 deltas.
data GlobalPalette = GlobalPalette
  { spine  :: !OklabPalette
  , deltas :: !(V.Vector OklabPalette)
  }
  deriving (Eq, Show)

-- | Build the global palette from 64 per-frame fingerprints. Groups are
-- consecutive blocks of 4 frames.
buildGlobalPalette :: SpineConfig -> V.Vector Fingerprint -> GlobalPalette
buildGlobalPalette cfg fps =
  let allColors = V.concatMap fpPalette fps
      sp        = kmeansOklab 8 (spineSize cfg) allColors
      nGroups   = V.length fps `div` 4
      groupColors g =
        V.concatMap fpPalette (V.slice (4*g) 4 fps)
      -- For each group, project out the spine-captured part and fit deltas
      -- to the residuals.
      groupDelta g =
        let gc = groupColors g
            residual = V.filter (\c -> nearestDistance sp c > residualThreshold) gc
            source   = if V.null residual then gc else residual
        in kmeansOklab 8 (deltaSize cfg) source
      ds = V.generate nGroups groupDelta
  in GlobalPalette sp ds

-- | The effective 256-color palette for a given frame index.
effectivePalette :: GlobalPalette -> Int -> OklabPalette
effectivePalette gp frameIdx =
  let g = frameIdx `div` 4
      d = if g < V.length (deltas gp)
            then deltas gp V.! g
            else V.empty
  in spine gp V.++ d

-- | Colors closer than this to the spine are considered already captured.
-- Tuned for Oklab where typical just-noticeable-difference is ~0.02.
residualThreshold :: Double
residualThreshold = 0.04

nearestDistance :: OklabPalette -> Oklab -> Double
nearestDistance pal c =
  V.minimum (V.map (deltaE c) pal)

-- | Lloyd's algorithm over Oklab. Initial centroids are picked by striding
-- the input vector; deterministic.
kmeansOklab :: Int -> Int -> V.Vector Oklab -> OklabPalette
kmeansOklab nIter k pts
  | V.null pts = V.empty
  | k <= 0     = V.empty
  | otherwise  =
      let initial = V.generate k $ \i ->
            pts V.! ((i * V.length pts) `div` max 1 k)
      in lloyd nIter pts initial

lloyd :: Int -> V.Vector Oklab -> V.Vector Oklab -> V.Vector Oklab
lloyd 0 _   cs = cs
lloyd n pts cs =
  let assigns = V.map (\p -> V.minIndex (V.map (deltaE p) cs)) pts
      k       = V.length cs
      newCs   = V.generate k $ \j ->
        let group = V.ifilter (\i _ -> assigns V.! i == j) pts
        in if V.null group then cs V.! j else meanO group
      moved = V.sum (V.zipWith deltaE cs newCs)
  in if moved < 1e-6 then newCs else lloyd (n - 1) pts newCs

meanO :: V.Vector Oklab -> Oklab
meanO v =
  let n = fromIntegral (V.length v)
      (sL, sA, sB) = V.foldl' (\(l,a,b) (Oklab l' a' b') -> (l+l', a+a', b+b'))
                               (0, 0, 0) v
  in Oklab (sL / n) (sA / n) (sB / n)
