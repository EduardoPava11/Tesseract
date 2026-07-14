-- | Laws for the L6 16x16 x 64-color fingerprint.
module ISP.Laws.Fingerprint (laws) where

import Test.QuickCheck
import qualified Data.Vector as V
import ISP.Bayer.Dither
import ISP.ColorDouble
import ISP.ColorDouble.Coproduct
import ISP.Fingerprint
import ISP.Oklab

-- The end-to-end pyramid allocates a 1024x1024 Oklab frame on every run,
-- so we cap the property iterations at a handful rather than 100.
laws :: [(String, Property)]
laws =
  [ ("fingerprint has 16x16 = 256 index cells (F1)",
     withMaxSuccess 3 prop_256Cells)
  , ("fingerprint palette has 64 colors",
     withMaxSuccess 3 prop_64Palette)
  , ("all fingerprint indices lie in [0, 64)",
     withMaxSuccess 3 prop_indexRange)
  , ("pyramid stack has the declared level sizes",
     withMaxSuccess 3 prop_stackSizes)
  ]

-- A small synthetic 1024x1024 Oklab frame (constant color) is enough to
-- exercise size invariants. For color fidelity we rely on the integration
-- tests rather than QuickCheck.
constFrame :: Oklab -> Plane Oklab
constFrame c = planeGenerate 1024 1024 (\_ _ -> c)

genOklab :: Gen Oklab
genOklab = Oklab <$> choose (0.1, 0.9) <*> choose (-0.2, 0.2) <*> choose (-0.2, 0.2)

prop_256Cells :: Property
prop_256Cells = forAll genOklab $ \c ->
  let fp = extractFingerprint bayer2 CatCoproduct (constFrame c)
  in V.length (planeData (fpIndices fp)) == 256

prop_64Palette :: Property
prop_64Palette = forAll genOklab $ \c ->
  let fp = extractFingerprint bayer2 CatCoproduct (constFrame c)
  in paletteSize (fpPalette fp) == 64

prop_indexRange :: Property
prop_indexRange = forAll genOklab $ \c ->
  let fp = extractFingerprint bayer2 CatCoproduct (constFrame c)
  in V.all (\i -> i >= 0 && i < 64) (planeData (fpIndices fp))

prop_stackSizes :: Property
prop_stackSizes = forAll genOklab $ \c ->
  let (s, _) = pyramidL0toL6 bayer2 CatCoproduct (constFrame c)
      sz p   = (planeW p, planeH p)
  in  sz (pL0 s) == (1024, 1024)
   && sz (pL1 s) == ( 512,  512)
   && sz (pL2 s) == ( 256,  256)
   && sz (pL3 s) == ( 128,  128)
   && sz (pL4 s) == (  64,   64)
   && sz (pL5 s) == (  32,   32)
   && sz (pL6 s) == (  16,   16)
