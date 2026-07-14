-- | Pyramid conservation laws.
module ISP.Laws.Pyramid (laws) where

import Test.QuickCheck
import ISP.Pyramid

laws :: [(String, Property)]
laws =
  [ ("S * K = 4096 at every level",           property prop_conservation)
  , ("pyramidS descends in powers of 2",      property prop_halving)
  , ("pickByTargetK returns closest-K level", property prop_pickByTargetK)
  , ("pickByDeltaT / tickSec = K (target)",   property prop_pickByDeltaT)
  ]

genLevel :: Gen Level
genLevel = elements allLevels

prop_conservation :: Property
prop_conservation = forAll genLevel $ \l -> conservationHolds l

prop_halving :: Property
prop_halving = property $
  and [ pyramidS (succ a) * 2 == pyramidS a
      | a <- init allLevels
      ]

prop_pickByTargetK :: Property
prop_pickByTargetK = forAll (choose (1 :: Int, 256)) $ \target ->
  let chosen = pickByTargetK target
      d l    = abs (pyramidK l - target)
  in all (\l -> d l >= d chosen) allLevels

prop_pickByDeltaT :: Property
prop_pickByDeltaT =
  forAll (choose (0.02 :: Double, 5.0)) $ \deltaT ->
  forAll (choose (0.01 :: Double, 0.10)) $ \tick ->
    let lvl    = pickByDeltaT deltaT tick
        maxK   = max 1 (floor (deltaT / tick) :: Int)
        chosen = pickByTargetK maxK
    in lvl == chosen
