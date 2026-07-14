-- | Laws for the binomial-beauty aesthetic scoring.
module ISP.Laws.BinomialBeauty (laws) where

import Test.QuickCheck
import qualified Data.Vector as V
import ISP.Bayer.Dither (bayer2)
import ISP.BinomialBeauty
import ISP.BinomialEMD
import ISP.BirkhoffBinomial (orderB, complexityB)
import ISP.ColorDouble (paletteSize)
import ISP.ColorDouble.Coproduct (CatCoproduct (..))
import ISP.Fingerprint (extractFingerprint, fpPalette)
import ISP.FingerprintHistogram (colorCounts)
import ISP.Oklab

laws :: [(String, Property)]
laws =
  [ ("dyadicShape n is palindromic (Bi1)",
     property prop_shapePalindromic)
  , ("dyadicShape n has length 2*(n+2) (Bi1')",
     property prop_shapeLength)
  , ("modelPMF sums to 1 for FingerprintBinomial (Bi3)",
     property prop_fingerprintPmfNormalized)
  , ("modelPMF sums to 1 for DyadicBell (Bi3)",
     property prop_dyadicPmfNormalized)
  , ("emd1D is non-negative and zero at equals (Bi4)",
     withMaxSuccess 50 prop_emdMetric)
  , ("emd1D is symmetric (Bi4')",
     withMaxSuccess 50 prop_emdSymmetric)
  , ("colorCounts sums to 256 (cell count)",
     withMaxSuccess 3 prop_countsSum256)
  , ("colorCounts length = palette size",
     withMaxSuccess 3 prop_countsLength)
  , ("orderB, complexityB are in [0,1]",
     withMaxSuccess 3 prop_scoresInRange)
  ]

-- A small synthetic 1024x1024 Oklab frame (constant color) is enough for
-- structural invariants. Full beauty ranking is covered in smoke tests.
constFrame :: Oklab -> Plane Oklab
constFrame c = planeGenerate 1024 1024 (\_ _ -> c)

genOklab :: Gen Oklab
genOklab = Oklab <$> choose (0.1, 0.9)
                 <*> choose (-0.2, 0.2)
                 <*> choose (-0.2, 0.2)

genPeak :: Gen Int
genPeak = choose (1, 8)

genPmfPair :: Gen (V.Vector Double, V.Vector Double)
genPmfPair = do
  n <- choose (4, 16)
  a <- vectorOf n (choose (0, 1 :: Double))
  b <- vectorOf n (choose (0, 1 :: Double))
  let na = normalize (V.fromList a)
      nb = normalize (V.fromList b)
  pure (na, nb)

prop_shapePalindromic :: Property
prop_shapePalindromic = forAll genPeak $ \n ->
  let s = dyadicShape n in V.toList s == reverse (V.toList s)

prop_shapeLength :: Property
prop_shapeLength = forAll genPeak $ \n ->
  V.length (dyadicShape n) == 2 * (n + 2)

prop_fingerprintPmfNormalized :: Property
prop_fingerprintPmfNormalized = property $
  abs (V.sum (modelPMF FingerprintBinomial) - 1) < 1e-9

prop_dyadicPmfNormalized :: Property
prop_dyadicPmfNormalized = forAll genPeak $ \n ->
  abs (V.sum (modelPMF (DyadicBell n)) - 1) < 1e-9

prop_emdMetric :: Property
prop_emdMetric = forAll genPmfPair $ \(p, q) ->
  let d = emd1D p q
  in d >= 0 && emd1D p p < 1e-9

prop_emdSymmetric :: Property
prop_emdSymmetric = forAll genPmfPair $ \(p, q) ->
  abs (emd1D p q - emd1D q p) < 1e-9

prop_countsSum256 :: Property
prop_countsSum256 = forAll genOklab $ \c ->
  let fp = extractFingerprint bayer2 CatCoproduct (constFrame c)
  in V.sum (colorCounts fp) == 256

prop_countsLength :: Property
prop_countsLength = forAll genOklab $ \c ->
  let fp = extractFingerprint bayer2 CatCoproduct (constFrame c)
  in V.length (colorCounts fp) == paletteSize (fpPalette fp)

prop_scoresInRange :: Property
prop_scoresInRange = forAll genOklab $ \c ->
  let fp = extractFingerprint bayer2 CatCoproduct (constFrame c)
      o  = orderB (DyadicBell 5) fp
      k  = complexityB fp
  in o >= 0 && o <= 1 && k >= 0 && k <= 1
