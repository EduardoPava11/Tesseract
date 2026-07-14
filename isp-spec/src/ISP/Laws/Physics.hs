-- | Property tests for sensor-physics constants and the Heisenberg bound.
module ISP.Laws.Physics (laws) where

import Test.QuickCheck
import ISP.Sensor.Physics

laws :: [(String, Property)]
laws =
  [ ("photon energy E * lambda = hc",                       property prop_energyTimesWavelength)
  , ("photon energy ordered R < G < B (inverse to lambda)", property prop_energyOrdering)
  , ("Heisenberg floor shrinks as 1/sqrt(N)",               property prop_heisenbergScaling)
  , ("Heisenberg floor non-negative",                       property prop_heisenbergNonNegative)
  ]

prop_energyTimesWavelength :: Property
prop_energyTimesWavelength = forAll genChannel $ \c ->
  let e  = photonEnergyJ c
      l  = wavelengthM c
      p  = e * l
      tol = 1e-27
  in counterexample (show (c, p, hcJm)) (abs (p - hcJm) < tol)

prop_energyOrdering :: Property
prop_energyOrdering = property $
  photonEnergyJ R < photonEnergyJ Gr &&
  photonEnergyJ Gr < photonEnergyJ B

prop_heisenbergScaling :: Property
prop_heisenbergScaling = forAll genChannel $ \c ->
  forAll (choose (100 :: Double, 1e6)) $ \n ->
    let dt1 = heisenbergFloorSec c n
        dt4 = heisenbergFloorSec c (4 * n)
        -- dt(4N) should be ~ dt(N) / 2
        ratio = dt1 / dt4
    in counterexample (show (c, n, ratio)) (abs (ratio - 2) < 1e-6)

prop_heisenbergNonNegative :: Property
prop_heisenbergNonNegative = forAll genChannel $ \c ->
  forAll (choose (1 :: Double, 1e8)) $ \n ->
    heisenbergFloorSec c n > 0

genChannel :: Gen Channel
genChannel = elements allChannels
