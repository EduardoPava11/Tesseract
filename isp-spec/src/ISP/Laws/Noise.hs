-- | Noise model laws: Poisson identity and Anscombe variance stabilization.
module ISP.Laws.Noise (laws) where

import Test.QuickCheck
import ISP.Sensor.Noise
import ISP.Sensor.Anscombe

laws :: [(String, Property)]
laws =
  [ ("Poisson variance = mean (NoiseProfile alpha=1 beta=0)", property prop_poissonIdentity)
  , ("NoiseProfile sigma non-negative",                        property prop_sigmaNonNegative)
  , ("Anscombe inverse is left-inverse above z = 2",           property prop_anscombeRoundTrip)
  , ("Generalized Anscombe inverse round-trip",                property prop_anscombeGRoundTrip)
  ]

prop_poissonIdentity :: Property
prop_poissonIdentity = forAll (choose (0 :: Double, 1e6)) $ \mu ->
  let np = NoiseProfile 1 0
  in abs (varNoise np mu - mu) < 1e-9

prop_sigmaNonNegative :: Property
prop_sigmaNonNegative =
  forAll (choose (0 :: Double, 1e3))  $ \a ->
  forAll (choose (0 :: Double, 1e3))  $ \b ->
  forAll (choose (0 :: Double, 1e6))  $ \mu ->
    sigmaNoise (NoiseProfile a b) mu >= 0

prop_anscombeRoundTrip :: Property
prop_anscombeRoundTrip = forAll (choose (10 :: Double, 1e6)) $ \x ->
  let z = anscombe x
      y = anscombeInv z
  in counterexample (show (x, z, y)) (abs (y - x) < 0.5 * max 1 (sqrt x))

prop_anscombeGRoundTrip :: Property
prop_anscombeGRoundTrip =
  forAll (choose (0.5 :: Double, 5)) $ \a ->
  forAll (choose (0.0 :: Double, 50)) $ \b ->
  forAll (choose (50  :: Double, 1e5)) $ \x ->
    let z = anscombeG a b x
        y = anscombeGInv a b z
    in abs (y - x) < 1.0 * max 1 (sqrt x)
