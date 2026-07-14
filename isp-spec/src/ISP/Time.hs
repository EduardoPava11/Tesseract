-- | Per-pixel time-axis estimators. T is a physical quantity (seconds),
-- not a frame index. All estimators return an 'Uncertain Double' with a
-- sigma floor imposed by the Heisenberg energy-time bound.
module ISP.Time
  ( TimeEstimator (..)
  , estimateT
  , poissonMLE
  ) where

import ISP.Sensor.Physics
import ISP.Sensor.Uncertainty

-- | Which statistical tool to use when collapsing photon count + exposure
-- into a per-pixel time coordinate.
data TimeEstimator
  = PoissonInterarrival
    -- ^ Maximum-likelihood: T = t_exposure / N_hat. Default.
  | EffectiveIntegration !Double
    -- ^ Calibration mode: T = N_hat / Phi_ref, given a reference flux.
  | HeisenbergPrecision
    -- ^ Report only the quantum-mechanical precision floor.
  deriving (Eq, Show)

-- Maximum-likelihood estimator of photon count given DN and physical constants.
-- Trivially N_hat = electrons / QE (we absorb QE into the caller).
poissonMLE :: Double -> Double
poissonMLE x = max 0 x

-- Estimate T and its sigma for a single pixel.
--
-- Arguments:
--   estimator - chosen tool
--   channel   - Bayer channel (wavelength for Heisenberg floor)
--   tExp      - exposure time in seconds
--   nHat      - photon count estimate (electrons / QE)
--   varN      - variance of nHat (from NoiseProfile)
estimateT
  :: TimeEstimator
  -> Channel
  -> Double
  -> Double
  -> Double
  -> Uncertain Double
estimateT est ch tExp nHat varN =
  let sigmaN   = sqrt (max 0 varN)
      floorSec = heisenbergFloorSec ch (max 1 nHat)
  in case est of
       PoissonInterarrival ->
         let t  = if nHat > 0 then tExp / nHat else tExp
             -- first-order uncertainty propagation: sigma_T = (tExp / N^2) * sigma_N
             sT = if nHat > 0 then (tExp / (nHat * nHat)) * sigmaN else 1 / 0
         in clampSigma floorSec (Uncertain t sT)
       EffectiveIntegration phiRef ->
         let t  = nHat / phiRef
             sT = sigmaN / phiRef
         in clampSigma floorSec (Uncertain t sT)
       HeisenbergPrecision ->
         Uncertain floorSec floorSec
