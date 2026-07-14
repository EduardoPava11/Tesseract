-- | 5D -> 4D projection laws.
module ISP.Laws.Tesseract (laws) where

import Test.QuickCheck
import ISP.Bayer             (Quad (..))
import ISP.Sensor.Uncertainty
import ISP.Tesseract

laws :: [(String, Property)]
laws =
  [ ("G value = (Gr + Gb) / 2",                        property prop_gValue)
  , ("G sigma = sqrt(sigma_Gr^2 + sigma_Gb^2) / 2",    property prop_gSigma)
  , ("R and B pass through unchanged",                 property prop_rbPassThrough)
  , ("T pass through unchanged",                       property prop_tPassThrough)
  , ("add4D commutes",                                 property prop_addCommutes)
  ]

genU :: Gen (Uncertain Double)
genU = Uncertain <$> choose (-100, 100) <*> choose (0.01, 10)

genQuadU :: Gen (Quad (Uncertain Double))
genQuadU = Quad <$> genU <*> genU <*> genU <*> genU

prop_gValue :: Property
prop_gValue = forAll genQuadU $ \q -> forAll genU $ \t ->
  let T4D _ g _ _ = project5Dto4D q t
      want = (uValue (qGr q) + uValue (qGb q)) / 2
  in abs (uValue g - want) < 1e-9

prop_gSigma :: Property
prop_gSigma = forAll genQuadU $ \q -> forAll genU $ \t ->
  let T4D _ g _ _ = project5Dto4D q t
      want = sqrt (uSigma (qGr q) ^ (2 :: Int) + uSigma (qGb q) ^ (2 :: Int)) / 2
  in abs (uSigma g - want) < 1e-9

prop_rbPassThrough :: Property
prop_rbPassThrough = forAll genQuadU $ \q -> forAll genU $ \t ->
  let T4D r _ b _ = project5Dto4D q t
  in r == qR q && b == qB q

prop_tPassThrough :: Property
prop_tPassThrough = forAll genQuadU $ \q -> forAll genU $ \t ->
  let T4D _ _ _ t' = project5Dto4D q t
  in t' == t

prop_addCommutes :: Property
prop_addCommutes = forAll genQuadU $ \q1 -> forAll genU $ \t1 ->
                   forAll genQuadU $ \q2 -> forAll genU $ \t2 ->
  let p1 = project5Dto4D q1 t1
      p2 = project5Dto4D q2 t2
      a  = add4D p1 p2
      b  = add4D p2 p1
  in approxT4D a b

approxT4D :: T4D (Uncertain Double) -> T4D (Uncertain Double) -> Bool
approxT4D (T4D r1 g1 b1 t1) (T4D r2 g2 b2 t2) =
  au r1 r2 && au g1 g2 && au b1 b2 && au t1 t2
  where
    au (Uncertain x1 s1) (Uncertain x2 s2) =
      abs (x1 - x2) < 1e-9 && abs (s1 - s2) < 1e-9
