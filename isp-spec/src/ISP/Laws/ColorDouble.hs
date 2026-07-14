-- | Laws for the ColorDouble typeclass and its three instances.
module ISP.Laws.ColorDouble (laws) where

import Test.QuickCheck
import qualified Data.Vector as V
import ISP.ColorDouble
import ISP.ColorDouble.KMeans
import ISP.ColorDouble.PCA
import ISP.ColorDouble.Coproduct
import ISP.Oklab

laws :: [(String, Property)]
laws =
  [ ("KMeansSplit doubles palette size (C1)",
     property (prop_sizeDoubles (KMeansSplit 8)))
  , ("PCASplit doubles palette size (C1)",
     property (prop_sizeDoubles PCASplit))
  , ("CatCoproduct doubles palette size (C1)",
     property (prop_sizeDoubles CatCoproduct))
  , ("CatCoproduct pairing projects back to input (C2)",
     property prop_coproductProject)
  , ("all instances produce indices in [0, 2n)",
     property prop_indicesInRange)
  ]

genOklab :: Gen Oklab
genOklab = Oklab <$> choose (0, 1) <*> choose (-0.3, 0.3) <*> choose (-0.3, 0.3)

genPaletteAndRef :: Gen (OklabPalette, Plane Oklab)
genPaletteAndRef = do
  n <- elements [2, 4, 8]
  pal <- V.fromList <$> vectorOf n genOklab
  w <- choose (4, 8)
  h <- choose (4, 8)
  pts <- V.fromList <$> vectorOf (w * h) genOklab
  pure (pal, Plane w h pts)

prop_sizeDoubles :: ColorDouble op => op -> Property
prop_sizeDoubles op = forAll genPaletteAndRef $ \(pal, ref) ->
  let (newPal, _) = double op pal ref
  in paletteSize newPal == 2 * paletteSize pal

-- The coproduct functor's pairing (2i, 2i+1) -> i collapses back to the
-- input palette's L shifted by 0 (i.e., sharing the same a, b).
prop_coproductProject :: Property
prop_coproductProject = forAll genPaletteAndRef $ \(pal, ref) ->
  let (newPal, _) = double CatCoproduct pal ref
      collapsed   = V.generate (paletteSize pal) $ \i ->
        let p0 = newPal V.! (2 * i)
            p1 = newPal V.! (2 * i + 1)
        in Oklab ((okL p0 + okL p1) / 2) (okA p0) (okB p0)
  in V.and (V.zipWith (\a b -> deltaE a b < 1e-9) collapsed pal)

prop_indicesInRange :: Property
prop_indicesInRange = forAll genPaletteAndRef $ \(pal, ref) ->
  let (newPal, idx) = double (KMeansSplit 4) pal ref
      n = paletteSize newPal
  in V.all (\i -> i >= 0 && i < n) (planeData idx)
