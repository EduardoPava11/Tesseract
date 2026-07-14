-- | Laplacian-pyramid-style composition of the 7 pyramid levels into a
-- single 64x64 Oklab frame, followed by a nearest-color snap onto the
-- 256-color effective palette.
--
-- Composition is linear in the level planes, so gradients flow cleanly
-- through 'compose64'. The snap step is non-differentiable; in a learned
-- setup it would use a straight-through estimator (VQ-VAE style).
module ISP.Compose
  ( compose64
  , resampleTo
  , flatWeights
  , laplacianWeights
  , snapToPalette
  , renderFrame
  ) where

import qualified Data.Vector as V
import ISP.Oklab
import ISP.ColorDouble
import ISP.Fingerprint
import ISP.PaletteSpine

-- | Uniform weights: 1/7 for each of the 7 levels.
flatWeights :: V.Vector Double
flatWeights = V.replicate 7 (1 / 7)

-- | Laplacian-style descending weights centered at L4 (the output resolution).
-- w_k = 2^(-|k - 4|) before normalization.
laplacianWeights :: V.Vector Double
laplacianWeights =
  let raw = V.generate 7 (\k -> 2 ** fromIntegral (negate (abs (k - 4))))
      s   = V.sum raw
  in V.map (/ s) raw

-- | Composite a 'PyramidStack' into a 64x64 Oklab plane using the supplied
-- per-level weights. Each level is resampled (mean for downsample,
-- nearest-neighbor for upsample) to 64x64 first.
compose64 :: V.Vector Double -> PyramidStack -> Plane Oklab
compose64 ws s
  | V.length ws /= 7 = error "compose64: weight vector must have length 7"
  | otherwise =
      let levels =
            [ pL0 s, pL1 s, pL2 s, pL3 s, pL4 s, pL5 s, pL6 s ]
          resampled = map (resampleTo 64 64) levels
      in planeGenerate 64 64 $ \x y ->
           let px = [ planeIndex p x y | p <- resampled ]
               (sL, sA, sB) = foldr step (0, 0, 0) (zip (V.toList ws) px)
               step (w, Oklab l a b) (aL, aA, aB) =
                 (aL + w * l, aA + w * a, aB + w * b)
           in Oklab sL sA sB

-- | Resample an Oklab plane to a target size. For downsampling we average
-- over the source block; for upsampling we nearest-neighbor-replicate.
-- When the source and target sizes match we return the plane unchanged.
resampleTo :: Int -> Int -> Plane Oklab -> Plane Oklab
resampleTo tw th p
  | planeW p == tw && planeH p == th = p
  | planeW p >= tw && planeH p >= th = downsampleTo tw th p
  | planeW p <= tw && planeH p <= th = upsampleTo   tw th p
  | otherwise = upsampleTo tw th (downsampleTo (min (planeW p) tw)
                                                (min (planeH p) th) p)

downsampleTo :: Int -> Int -> Plane Oklab -> Plane Oklab
downsampleTo tw th p =
  let sw = planeW p `div` tw
      sh = planeH p `div` th
  in planeGenerate tw th $ \x y ->
       let xs = [ planeIndex p (x * sw + dx) (y * sh + dy)
                | dx <- [0 .. sw - 1], dy <- [0 .. sh - 1] ]
           n  = fromIntegral (length xs)
           (sL, sA, sB) = foldr (\(Oklab l a b) (aL, aA, aB) ->
                                    (aL + l, aA + a, aB + b))
                                (0, 0, 0) xs
       in Oklab (sL / n) (sA / n) (sB / n)

upsampleTo :: Int -> Int -> Plane Oklab -> Plane Oklab
upsampleTo tw th p =
  planeGenerate tw th $ \x y ->
    let sx = (x * planeW p) `div` tw
        sy = (y * planeH p) `div` th
    in planeIndex p sx sy

-- | Snap a continuous Oklab frame to the effective 256-color palette of
-- the given frame. The returned indices are into that effective palette
-- (spine ++ delta[g]).
snapToPalette :: GlobalPalette -> Int -> Plane Oklab -> Plane Int
snapToPalette gp frameIdx frame =
  let pal = effectivePalette gp frameIdx
  in assignNearest pal frame

-- | End-to-end render of one frame: composition + snap. The returned plane
-- holds indices into @effectivePalette gp frameIdx@.
renderFrame
  :: V.Vector Double   -- ^ compose weights (length 7)
  -> GlobalPalette
  -> Int               -- ^ frame index (0..63)
  -> PyramidStack
  -> Plane Int
renderFrame ws gp i stack =
  snapToPalette gp i (compose64 ws stack)
