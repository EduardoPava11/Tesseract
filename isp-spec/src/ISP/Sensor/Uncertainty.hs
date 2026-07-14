-- | A thin value-with-standard-deviation carrier. Operations assume
-- independent inputs unless otherwise noted; covariance is explicit.
module ISP.Sensor.Uncertainty
  ( Uncertain (..)
  , addU
  , subU
  , scaleU
  , meanU
  , weightedMeanU
  , clampSigma
  , nSigma
  , toPair
  ) where

data Uncertain a = Uncertain
  { uValue :: !a
  , uSigma :: !Double
  }
  deriving (Eq, Show, Functor)

toPair :: Uncertain a -> (a, Double)
toPair (Uncertain x s) = (x, s)

-- Sum of independent uncertain quantities.
addU :: Num a => Uncertain a -> Uncertain a -> Uncertain a
addU (Uncertain a sa) (Uncertain b sb) =
  Uncertain (a + b) (sqrt (sa * sa + sb * sb))

subU :: Num a => Uncertain a -> Uncertain a -> Uncertain a
subU (Uncertain a sa) (Uncertain b sb) =
  Uncertain (a - b) (sqrt (sa * sa + sb * sb))

-- Scale a Double-valued measurement by a real constant.
scaleU :: Double -> Uncertain Double -> Uncertain Double
scaleU k (Uncertain a s) = Uncertain (k * a) (abs k * s)

-- Arithmetic mean of independent Doubles: sigma shrinks as 1/sqrt(n).
meanU :: [Uncertain Double] -> Uncertain Double
meanU [] = Uncertain 0 (1 / 0)
meanU xs =
  let n    = fromIntegral (length xs)
      m    = sum (map uValue xs) / n
      sSq  = sum (map (\u -> uSigma u * uSigma u) xs) / (n * n)
  in Uncertain m (sqrt sSq)

-- Inverse-variance-weighted mean (minimum variance unbiased combiner).
weightedMeanU :: [Uncertain Double] -> Uncertain Double
weightedMeanU [] = Uncertain 0 (1 / 0)
weightedMeanU xs =
  let ws   = map (\u -> 1 / (uSigma u * uSigma u)) xs
      wsum = sum ws
      num  = sum (zipWith (\u w -> uValue u * w) xs ws)
  in Uncertain (num / wsum) (sqrt (1 / wsum))

-- Enforce a lower bound on sigma (e.g. Heisenberg precision floor).
clampSigma :: Double -> Uncertain a -> Uncertain a
clampSigma floorS (Uncertain a s) = Uncertain a (max s floorS)

-- Width of an n-sigma interval.
nSigma :: Double -> Uncertain a -> Double
nSigma n (Uncertain _ s) = n * s
