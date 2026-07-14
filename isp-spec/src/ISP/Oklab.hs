-- | Oklab perceptual color space (Björn Ottosson, 2020).
-- Near-lossless when stored in Double; used as the working space for the
-- pyramid-double synthesis path. Matrices and transfer curves match the
-- reference at <https://bottosson.github.io/posts/oklab/>.
module ISP.Oklab
  ( -- * Color types
    SRGB8 (..)
  , LinRGB (..)
  , Oklab (..)
    -- * sRGB transfer
  , srgb8ToLinear
  , linearToSrgb8
    -- * Linear <-> Oklab
  , linearToOklab
  , oklabToLinear
    -- * Distance
  , deltaE
    -- * 2D color planes
  , Plane (..)
  , planeSize
  , planeIndex
  , planeGenerate
  , planeMap
  , downsampleMean2Oklab
  ) where

import Data.Word (Word8)
import qualified Data.Vector as V

-- | 8-bit sRGB triple (gamma-encoded display color).
data SRGB8 = SRGB8 !Word8 !Word8 !Word8
  deriving (Eq, Show)

-- | Linear-light RGB in [0,1]. Intermediate between sRGB and LMS.
data LinRGB = LinRGB
  { lR :: !Double
  , lG :: !Double
  , lB :: !Double
  }
  deriving (Eq, Show)

-- | Oklab triple: perceptual lightness L and opponent channels a, b.
-- L in [0,1] for in-gamut sRGB; a, b typically in [-0.5, 0.5].
data Oklab = Oklab
  { okL :: !Double
  , okA :: !Double
  , okB :: !Double
  }
  deriving (Eq, Show)

-- sRGB gamma curve (IEC 61966-2-1).
srgbEncode :: Double -> Double
srgbEncode c
  | c <= 0.0031308 = 12.92 * c
  | otherwise      = 1.055 * (c ** (1.0 / 2.4)) - 0.055

srgbDecode :: Double -> Double
srgbDecode c
  | c <= 0.04045 = c / 12.92
  | otherwise    = ((c + 0.055) / 1.055) ** 2.4

clamp01 :: Double -> Double
clamp01 = max 0 . min 1

srgb8ToLinear :: SRGB8 -> LinRGB
srgb8ToLinear (SRGB8 r g b) =
  LinRGB (srgbDecode (i r)) (srgbDecode (i g)) (srgbDecode (i b))
  where i w = fromIntegral w / 255.0

linearToSrgb8 :: LinRGB -> SRGB8
linearToSrgb8 (LinRGB r g b) =
  SRGB8 (q r) (q g) (q b)
  where
    q x = round (clamp01 (srgbEncode (clamp01 x)) * 255.0)

-- Linear sRGB -> Oklab (Ottosson 2020).
linearToOklab :: LinRGB -> Oklab
linearToOklab (LinRGB r g b) =
  let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
      m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
      s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
      l_ = cbrtD l
      m_ = cbrtD m
      s_ = cbrtD s
      okL_ = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_
      okA_ = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_
      okB_ = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
  in Oklab okL_ okA_ okB_

oklabToLinear :: Oklab -> LinRGB
oklabToLinear (Oklab okL_ okA_ okB_) =
  let l_ = okL_ + 0.3963377774 * okA_ + 0.2158037573 * okB_
      m_ = okL_ - 0.1055613458 * okA_ - 0.0638541728 * okB_
      s_ = okL_ - 0.0894841775 * okA_ - 1.2914855480 * okB_
      l = l_ * l_ * l_
      m = m_ * m_ * m_
      s = s_ * s_ * s_
      r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
      g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
      b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
  in LinRGB r g b

-- Real cube root (cbrt is not in Prelude prior to base 4.19).
cbrtD :: Double -> Double
cbrtD x
  | x < 0     = negate ((negate x) ** (1/3))
  | otherwise = x ** (1/3)

-- | Perceptual distance. Euclidean in Oklab is the recommended delta-E.
deltaE :: Oklab -> Oklab -> Double
deltaE (Oklab l1 a1 b1) (Oklab l2 a2 b2) =
  let dL = l1 - l2
      dA = a1 - a2
      dB = b1 - b2
  in sqrt (dL * dL + dA * dA + dB * dB)

-- | Simple row-major 2D plane backed by a boxed vector. Used by the pyramid.
data Plane a = Plane
  { planeW :: !Int
  , planeH :: !Int
  , planeData :: !(V.Vector a)
  }
  deriving (Eq, Show, Functor)

planeSize :: Plane a -> (Int, Int)
planeSize p = (planeW p, planeH p)

planeIndex :: Plane a -> Int -> Int -> a
planeIndex (Plane w _ v) x y = v V.! (y * w + x)

planeGenerate :: Int -> Int -> (Int -> Int -> a) -> Plane a
planeGenerate w h f =
  Plane w h (V.generate (w * h) (\i -> let (y, x) = i `divMod` w in f x y))

planeMap :: (a -> b) -> Plane a -> Plane b
planeMap f (Plane w h v) = Plane w h (V.map f v)

-- | Downsample an Oklab plane by 2x2 block mean (component-wise).
-- Truncates the last row/column if a dimension is odd.
downsampleMean2Oklab :: Plane Oklab -> Plane Oklab
downsampleMean2Oklab p =
  let w = planeW p `div` 2
      h = planeH p `div` 2
  in planeGenerate w h $ \x y ->
       let Oklab l0 a0 b0 = planeIndex p (2*x)   (2*y)
           Oklab l1 a1 b1 = planeIndex p (2*x+1) (2*y)
           Oklab l2 a2 b2 = planeIndex p (2*x)   (2*y+1)
           Oklab l3 a3 b3 = planeIndex p (2*x+1) (2*y+1)
       in Oklab ((l0 + l1 + l2 + l3) / 4)
                ((a0 + a1 + a2 + a3) / 4)
                ((b0 + b1 + b2 + b3) / 4)
