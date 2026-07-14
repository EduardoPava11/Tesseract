-- | Sensor physics constants and per-channel optical parameters.
-- Wavelengths are peak-transmission centers for a generic Bayer CFA.
module ISP.Sensor.Physics
  ( -- * Constants (CODATA 2019)
    planckH
  , lightC
  , planckHbar
  , hcJm
    -- * Channels
  , Channel (..)
  , allChannels
    -- * Per-channel optics
  , wavelengthNm
  , wavelengthM
  , fwhmNm
  , peakTransmission
  , photonEnergyJ
    -- * Heisenberg bound
  , heisenbergFloorSec
  ) where

planckH, lightC, planckHbar, hcJm :: Double
planckH    = 6.62607015e-34
lightC     = 299792458
planckHbar = planckH / (2 * pi)
hcJm       = planckH * lightC

data Channel = R | Gr | Gb | B
  deriving (Eq, Show, Ord, Enum, Bounded)

allChannels :: [Channel]
allChannels = [minBound .. maxBound]

wavelengthNm :: Channel -> Double
wavelengthNm R  = 640
wavelengthNm Gr = 546
wavelengthNm Gb = 546
wavelengthNm B  = 427

wavelengthM :: Channel -> Double
wavelengthM c = wavelengthNm c * 1e-9

fwhmNm :: Channel -> Double
fwhmNm R  = 55
fwhmNm Gr = 66
fwhmNm Gb = 66
fwhmNm B  = 76

peakTransmission :: Channel -> Double
peakTransmission R  = 0.75
peakTransmission Gr = 0.82
peakTransmission Gb = 0.82
peakTransmission B  = 0.88

-- Photon energy E = hc / lambda.
photonEnergyJ :: Channel -> Double
photonEnergyJ c = hcJm / wavelengthM c

-- Heisenberg energy-time: Delta E * Delta t >= hbar / 2.
-- For N photons per pixel with per-photon energy E_c = hc/lambda_c,
-- Delta E ~ sqrt(N) * E_c, so:
--   Delta t >= hbar / (2 * sqrt(N) * hc/lambda_c) = lambda_c / (4 pi c sqrt(N))
heisenbergFloorSec :: Channel -> Double -> Double
heisenbergFloorSec c n
  | n <= 0    = 1 / 0
  | otherwise = wavelengthM c / (4 * pi * lightC * sqrt n)
