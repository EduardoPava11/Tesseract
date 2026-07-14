-- | The 4D (R, G, B, T) GIF domain and the 5D -> 4D projection.
module ISP.Tesseract
  ( T4D (..)
  , project5Dto4D
  , add4D
  , scale4D
  ) where

import ISP.Bayer
import ISP.Sensor.Uncertainty

-- 4D point as seen by the GIF encoder.
data T4D a = T4D
  { t4R :: !a
  , t4G :: !a
  , t4B :: !a
  , t4T :: !a
  }
  deriving (Eq, Show, Functor)

-- Project a Bayer quad + time estimate into (R, G, B, T).
-- G is the variance-weighted (here, equal-weight) mean of Gr and Gb.
project5Dto4D
  :: Quad (Uncertain Double)
  -> Uncertain Double
  -> T4D (Uncertain Double)
project5Dto4D q tU =
  let uR  = qR  q
      uGr = qGr q
      uGb = qGb q
      uB  = qB  q
      gVal   = (uValue uGr + uValue uGb) / 2
      gSigma = sqrt (uSigma uGr * uSigma uGr + uSigma uGb * uSigma uGb) / 2
  in T4D uR (Uncertain gVal gSigma) uB tU

-- Element-wise addition (independent inputs).
add4D
  :: T4D (Uncertain Double)
  -> T4D (Uncertain Double)
  -> T4D (Uncertain Double)
add4D (T4D r1 g1 b1 t1) (T4D r2 g2 b2 t2) =
  T4D (addU' r1 r2) (addU' g1 g2) (addU' b1 b2) (addU' t1 t2)
  where addU' (Uncertain a sa) (Uncertain b sb) =
          Uncertain (a + b) (sqrt (sa * sa + sb * sb))

scale4D :: Double -> T4D (Uncertain Double) -> T4D (Uncertain Double)
scale4D k (T4D r g b t) = T4D (s r) (s g) (s b) (s t)
  where s (Uncertain a sig) = Uncertain (k * a) (abs k * sig)
