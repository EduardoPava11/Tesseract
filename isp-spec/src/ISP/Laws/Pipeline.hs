-- | Pipeline laws: frame-delay accounting and end-to-end well-definedness.
module ISP.Laws.Pipeline (laws) where

import Test.QuickCheck
import ISP.GIF (deriveDelaysCs)

laws :: [(String, Property)]
laws =
  [ ("deriveDelaysCs yields exactly K delays",      property prop_delaysCount)
  , ("every frame delay >= 1 cs",                    property prop_delaysMin)
  , ("sum of delays (cs) = round(deltaT*100) when feasible",
     property prop_delaysSum)
  ]

prop_delaysCount :: Property
prop_delaysCount = forAll (choose (1 :: Int, 256)) $ \k ->
                   forAll (choose (0.01 :: Double, 5.0)) $ \dt ->
  length (deriveDelaysCs dt k) == k

prop_delaysMin :: Property
prop_delaysMin = forAll (choose (1 :: Int, 256)) $ \k ->
                 forAll (choose (0.01 :: Double, 5.0)) $ \dt ->
  all (>= 1) (deriveDelaysCs dt k)

prop_delaysSum :: Property
prop_delaysSum = forAll (choose (2 :: Int, 64)) $ \k ->
                 forAll (choose (0.5 :: Double, 5.0)) $ \dt ->
  let got  = sum (deriveDelaysCs dt k)
      want = max k (round (dt * 100) :: Int)
  in got == want
