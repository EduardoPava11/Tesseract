-- | Laws for the Bayer ordered-dither module.
module ISP.Laws.BayerDither (laws) where

import Test.QuickCheck
import qualified Data.Vector as V
import ISP.Bayer.Dither
import ISP.Oklab

laws :: [(String, Property)]
laws =
  [ ("bayer matrix entries lie strictly in (0,1)",
     property prop_matRange)
  , ("thresholdBayer is deterministic",
     property prop_deterministic)
  , ("bayerDownsampleBW halves both dimensions",
     property prop_halvesSize)
  , ("block mean of BW output tracks input mean",
     property prop_meanTracking)
  ]

-- Generate a small Oklab plane of even dimensions with L in [0,1].
genOklabPlane :: Gen (Plane Oklab)
genOklabPlane = do
  wHalf <- choose (2, 8)
  hHalf <- choose (2, 8)
  let w = wHalf * 2
      h = hHalf * 2
  vs <- V.fromList <$> vectorOf (w * h)
          (Oklab <$> choose (0, 1) <*> pure 0 <*> pure 0)
  pure (Plane w h vs)

prop_matRange :: Property
prop_matRange = property $
  all (\(BayerMat _ v) ->
         V.all (\x -> x > 0 && x < 1) v)
      [bayer2, bayer4, bayer8]

prop_deterministic :: Property
prop_deterministic = forAll genOklabPlane $ \p ->
  let lp = planeMap okL p
      a = thresholdBayer bayer2 lp
      b = thresholdBayer bayer2 lp
  in planeData a == planeData b

prop_halvesSize :: Property
prop_halvesSize = forAll genOklabPlane $ \p ->
  let r = bayerDownsampleBW bayer2 p
  in planeW r == planeW p `div` 2 && planeH r == planeH p `div` 2

-- The fraction of True pixels in the B/W output should be close to the
-- input's average L. Tolerance is loose: 2x2 matrix has 4 threshold levels
-- so a block-level mean can differ by up to ~0.25 from the ideal fraction.
prop_meanTracking :: Property
prop_meanTracking = forAll genOklabPlane $ \p ->
  let r    = bayerDownsampleBW bayer2 p
      lMean = V.sum (V.map okL (planeData p)) / fromIntegral (V.length (planeData p))
      trueFrac = fromIntegral (V.length (V.filter id (planeData r)))
               / fromIntegral (V.length (planeData r))
  in abs (lMean - trueFrac) <= 0.5
