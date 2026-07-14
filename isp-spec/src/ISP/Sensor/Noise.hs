-- | Poisson + Gaussian sensor noise model, matching the DNG NoiseProfile tag.
module ISP.Sensor.Noise
  ( NoiseProfile (..)
  , varNoise
  , sigmaNoise
  , shotVariance
  , readVariance
  , signalFromDN
  ) where

-- NoiseProfile per channel: Var(DN | mean) = alpha * mean + beta
-- where alpha captures photon-shot scaling and beta captures read noise.
data NoiseProfile = NoiseProfile
  { noiseAlpha :: !Double
  , noiseBeta  :: !Double
  }
  deriving (Eq, Show)

varNoise :: NoiseProfile -> Double -> Double
varNoise (NoiseProfile a b) mean = a * max 0 mean + b

sigmaNoise :: NoiseProfile -> Double -> Double
sigmaNoise np mean = sqrt (varNoise np mean)

-- Pure shot-noise variance: Var(N) = N (Poisson identity).
shotVariance :: Double -> Double
shotVariance n = max 0 n

-- Read-noise variance in electrons-squared.
readVariance :: NoiseProfile -> Double
readVariance (NoiseProfile _ b) = b

-- Convert a raw DN (digital number) to electrons given black level and gain.
--   signal_e = gain_e_per_DN * (dn - black_level)
signalFromDN :: Double -> Double -> Int -> Double
signalFromDN gain_ePerDN black dn =
  gain_ePerDN * (fromIntegral dn - black)
