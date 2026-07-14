-- | Laws for the Oklab color space module.
module ISP.Laws.Oklab (laws) where

import Test.QuickCheck
import Data.Word (Word8)
import ISP.Oklab

laws :: [(String, Property)]
laws =
  [ ("sRGB8 -> linear -> sRGB8 is within 1 LSB",
     property prop_srgbRoundtrip)
  , ("linear -> Oklab -> linear is near-identity",
     property prop_oklabRoundtrip)
  , ("deltaE is symmetric",
     property prop_deltaSymmetric)
  , ("deltaE is zero at equals",
     property prop_deltaZero)
  ]

genWord8 :: Gen Word8
genWord8 = choose (0, 255)

genSRGB8 :: Gen SRGB8
genSRGB8 = SRGB8 <$> genWord8 <*> genWord8 <*> genWord8

genLinRGB :: Gen LinRGB
genLinRGB = LinRGB <$> choose (0, 1) <*> choose (0, 1) <*> choose (0, 1)

prop_srgbRoundtrip :: Property
prop_srgbRoundtrip = forAll genSRGB8 $ \c ->
  let SRGB8 r1 g1 b1 = c
      SRGB8 r2 g2 b2 = linearToSrgb8 (srgb8ToLinear c)
  in abs (fromIntegral r1 - fromIntegral r2 :: Int) <= 1
  && abs (fromIntegral g1 - fromIntegral g2 :: Int) <= 1
  && abs (fromIntegral b1 - fromIntegral b2 :: Int) <= 1

prop_oklabRoundtrip :: Property
prop_oklabRoundtrip = forAll genLinRGB $ \c ->
  let LinRGB r1 g1 b1 = c
      LinRGB r2 g2 b2 = oklabToLinear (linearToOklab c)
  in abs (r1 - r2) < 1e-6 && abs (g1 - g2) < 1e-6 && abs (b1 - b2) < 1e-6

prop_deltaSymmetric :: Property
prop_deltaSymmetric = forAll genLinRGB $ \a -> forAll genLinRGB $ \b ->
  let oa = linearToOklab a
      ob = linearToOklab b
  in abs (deltaE oa ob - deltaE ob oa) < 1e-12

prop_deltaZero :: Property
prop_deltaZero = forAll genLinRGB $ \c ->
  let o = linearToOklab c in abs (deltaE o o) < 1e-12
