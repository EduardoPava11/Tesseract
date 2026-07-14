-- | Laws of uncertainty propagation under linear operations.
module ISP.Laws.Uncertainty (laws) where

import Test.QuickCheck
import ISP.Sensor.Uncertainty

laws :: [(String, Property)]
laws =
  [ ("independent-sum: sigma(a+b)^2 = sigma_a^2 + sigma_b^2", property prop_addSigma)
  , ("scaling: sigma(k*x) = |k| * sigma(x)",                   property prop_scaleSigma)
  , ("mean: sigma(mean_n) = sigma/sqrt(n)",                    property prop_meanSigma)
  , ("clampSigma floors sigma below",                          property prop_clampSigma)
  , ("weighted mean sigma <= min sigma",                       property prop_weightedShrinks)
  ]

genUncertain :: Gen (Uncertain Double)
genUncertain = do
  v <- choose (-1e3, 1e3)
  s <- choose (0.01, 1e2)
  pure (Uncertain v s)

prop_addSigma :: Property
prop_addSigma = forAll genUncertain $ \a ->
                forAll genUncertain $ \b ->
  let c = addU a b
      want = sqrt (uSigma a ^ (2 :: Int) + uSigma b ^ (2 :: Int))
  in abs (uSigma c - want) < 1e-9

prop_scaleSigma :: Property
prop_scaleSigma = forAll genUncertain $ \a ->
                  forAll (choose (-10 :: Double, 10)) $ \k ->
  abs (uSigma (scaleU k a) - abs k * uSigma a) < 1e-9

prop_meanSigma :: Property
prop_meanSigma = forAll (choose (1 :: Int, 32)) $ \n ->
                 forAll (choose (0.1 :: Double, 10)) $ \s ->
  let xs = replicate n (Uncertain 0 s)
      m  = meanU xs
      want = s / sqrt (fromIntegral n)
  in abs (uSigma m - want) < 1e-9

prop_clampSigma :: Property
prop_clampSigma = forAll genUncertain $ \a ->
                  forAll (choose (0 :: Double, 100)) $ \floorS ->
  uSigma (clampSigma floorS a) >= floorS - 1e-12

prop_weightedShrinks :: Property
prop_weightedShrinks = forAll (listOf1 genUncertain) $ \xs ->
  let wm = weightedMeanU xs
      minS = minimum (map uSigma xs)
  in uSigma wm <= minS + 1e-9
