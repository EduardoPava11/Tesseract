-- | Palette / K-means laws.
module ISP.Laws.Palette (laws) where

import Test.QuickCheck
import qualified Data.Vector as V
import ISP.Palette
import ISP.Tesseract

laws :: [(String, Property)]
laws =
  [ ("kmeansStep does not increase total quantization error",
     property prop_kmeansMonotone)
  , ("distance is symmetric",      property prop_distSymmetric)
  , ("distance is zero at equals", property prop_distZero)
  , ("assign picks closest centroid",
     property prop_assignClosest)
  ]

genT4D :: Gen (T4D Double)
genT4D = T4D <$> choose (0, 1) <*> choose (0, 1) <*> choose (0, 1) <*> choose (0, 1)

genPointsAndCents :: Gen (V.Vector (T4D Double), V.Vector (T4D Double))
genPointsAndCents = do
  n <- choose (4, 16)
  k <- choose (1, 4)
  pts  <- V.fromList <$> vectorOf n genT4D
  cen  <- V.fromList <$> vectorOf k genT4D
  pure (pts, cen)

prop_kmeansMonotone :: Property
prop_kmeansMonotone = forAll genPointsAndCents $ \(pts, cen) ->
  let (cen', idx0) = kmeansStep pts cen
      e0 = totalError pts (Palette cen)  idx0
      idx1 = assign pts cen'
      e1 = totalError pts (Palette cen') idx1
  in e1 <= e0 + 1e-9

prop_distSymmetric :: Property
prop_distSymmetric = forAll genT4D $ \a -> forAll genT4D $ \b ->
  abs (dist4 a b - dist4 b a) < 1e-12

prop_distZero :: Property
prop_distZero = forAll genT4D $ \a -> abs (dist4 a a) < 1e-12

prop_assignClosest :: Property
prop_assignClosest = forAll genPointsAndCents $ \(pts, cen) ->
  let idx = assign pts cen
  in V.and $ V.imap (\i k ->
       let d = dist4 (pts V.! i) (cen V.! k)
       in V.all (\c -> d <= dist4 (pts V.! i) c + 1e-9) cen) idx
