-- | Laws for the hybrid spine+delta global palette.
module ISP.Laws.PaletteSpine (laws) where

import Test.QuickCheck
import qualified Data.Vector as V
import ISP.Bayer.Dither (bayer2)
import ISP.ColorDouble.Coproduct (CatCoproduct (..))
import ISP.Fingerprint
import ISP.Oklab
import ISP.PaletteSpine

-- buildGlobalPalette runs 64 full pyramids per property; cap iterations.
laws :: [(String, Property)]
laws =
  [ ("spineSize + deltaSize = 256 for default config (P1)",
     property prop_defaultP1)
  , ("buildGlobalPalette produces 16 deltas for 64 frames",
     withMaxSuccess 1 prop_sixteenDeltas)
  , ("effectivePalette has exactly 256 colors for every frame",
     withMaxSuccess 1 prop_effective256)
  , ("defaultSpineConfig satisfies paletteSpineTotal",
     property prop_totalHolds)
  ]

-- 64 synthetic fingerprints built from 64 constant-color frames.
genSyntheticFingerprints :: Gen (V.Vector Fingerprint)
genSyntheticFingerprints = do
  colors <- vectorOf 64 (Oklab <$> choose (0.1, 0.9)
                                <*> choose (-0.2, 0.2)
                                <*> choose (-0.2, 0.2))
  pure $ V.fromList
       [ extractFingerprint bayer2 CatCoproduct
           (planeGenerate 1024 1024 (\_ _ -> c))
       | c <- colors ]

prop_defaultP1 :: Property
prop_defaultP1 = property $
  spineSize defaultSpineConfig + deltaSize defaultSpineConfig == paletteSpineTotal

prop_totalHolds :: Property
prop_totalHolds = property $ paletteSpineTotal == 256

prop_sixteenDeltas :: Property
prop_sixteenDeltas = forAll genSyntheticFingerprints $ \fps ->
  let gp = buildGlobalPalette defaultSpineConfig fps
  in V.length (deltas gp) == 16

prop_effective256 :: Property
prop_effective256 = forAll genSyntheticFingerprints $ \fps ->
  let gp = buildGlobalPalette defaultSpineConfig fps
  in all (\i -> V.length (effectivePalette gp i)
             == spineSize defaultSpineConfig + deltaSize defaultSpineConfig)
         [0, 4, 32, 60]
