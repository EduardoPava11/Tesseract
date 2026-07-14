-- | Ordered (Bayer) dithering as a full-color -> B/W downsampler.
--
-- This module is named 'ISP.Bayer.Dither' to avoid clashing with the
-- existing 'ISP.Bayer' which models Bayer CFA sensor quads (a different
-- meaning of "Bayer"). Reference: B. E. Bayer, "An Optimum Method for
-- Two-Level Rendition of Continuous-Tone Pictures", IEEE ICC, 1973.
module ISP.Bayer.Dither
  ( BayerMat (..)
  , bayer2
  , bayer4
  , bayer8
  , thresholdBayer
  , downsampleMean2
  , bayerDownsampleBW
  , bwToOklab
  ) where

import qualified Data.Vector as V
import ISP.Oklab

-- | A Bayer ordered-dither matrix with entries normalized to (0, 1).
-- Square; side stored for indexing.
data BayerMat = BayerMat
  { bmSide :: !Int
  , bmData :: !(V.Vector Double)
  }
  deriving (Eq, Show)

-- Convert an integer matrix (values in [0 .. n^2 - 1]) to (0, 1) exclusive.
-- The +1 offset and /(n^2) keep entries away from the boundaries.
mkMat :: Int -> [Int] -> BayerMat
mkMat n xs =
  BayerMat n
    (V.fromList [ (fromIntegral x + 0.5) / fromIntegral (n * n) | x <- xs ])

-- | Classic 2x2 Bayer matrix.
bayer2 :: BayerMat
bayer2 = mkMat 2
  [ 0, 2
  , 3, 1 ]

-- | Classic 4x4 Bayer matrix (recursively built from 2x2).
bayer4 :: BayerMat
bayer4 = mkMat 4
  [  0,  8,  2, 10
  , 12,  4, 14,  6
  ,  3, 11,  1,  9
  , 15,  7, 13,  5 ]

-- | Classic 8x8 Bayer matrix.
bayer8 :: BayerMat
bayer8 = mkMat 8
  [  0, 32,  8, 40,  2, 34, 10, 42
  , 48, 16, 56, 24, 50, 18, 58, 26
  , 12, 44,  4, 36, 14, 46,  6, 38
  , 60, 28, 52, 20, 62, 30, 54, 22
  ,  3, 35, 11, 43,  1, 33,  9, 41
  , 51, 19, 59, 27, 49, 17, 57, 25
  , 15, 47,  7, 39, 13, 45,  5, 37
  , 63, 31, 55, 23, 61, 29, 53, 21 ]

bayerAt :: BayerMat -> Int -> Int -> Double
bayerAt (BayerMat n v) x y = v V.! ((y `mod` n) * n + (x `mod` n))

-- | Threshold a grayscale plane (values in [0,1]) against a tiled Bayer
-- matrix. Output Bool plane has the same dimensions as the input.
thresholdBayer :: BayerMat -> Plane Double -> Plane Bool
thresholdBayer m p =
  planeGenerate (planeW p) (planeH p) $ \x y ->
    planeIndex p x y > bayerAt m x y

-- | Downsample a plane by a factor of 2 using 2x2 block mean. Requires
-- both dimensions to be even; truncates the last row/column otherwise.
downsampleMean2 :: Fractional a => Plane a -> Plane a
downsampleMean2 p =
  let w  = planeW p `div` 2
      h  = planeH p `div` 2
  in planeGenerate w h $ \x y ->
       let a = planeIndex p (2*x)   (2*y)
           b = planeIndex p (2*x+1) (2*y)
           c = planeIndex p (2*x)   (2*y+1)
           d = planeIndex p (2*x+1) (2*y+1)
       in (a + b + c + d) / 4

-- | L0 -> L1 step: downsample an Oklab plane by 2x2 mean on the L channel,
-- then ordered-dither the result to a binary plane. The Bayer matrix is
-- applied at the downsampled resolution so adjacent blocks see adjacent
-- matrix entries.
bayerDownsampleBW :: BayerMat -> Plane Oklab -> Plane Bool
bayerDownsampleBW m p =
  let lPlane = planeMap okL p
      lDown  = downsampleMean2 lPlane
  in thresholdBayer m lDown

-- | Lift a boolean plane back to Oklab: False -> pure black (L=0), True ->
-- pure white (L=1). This is the "quantized-upsampled" form of L1 used when
-- the Laplacian composition pass recombines pyramid levels.
bwToOklab :: Plane Bool -> Plane Oklab
bwToOklab = planeMap (\b -> if b then Oklab 1 0 0 else Oklab 0 0 0)
