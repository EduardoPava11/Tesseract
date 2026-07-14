-- | Color-doubling as a categorical coproduct with a deterministic refinement.
--
-- Interprets 'double :: Palette n -> Palette (2n)' as the coproduct functor
-- P |-> P ⊔ P' in the category Pal of finite Oklab palettes. The refinement
-- P' is a deterministic perturbation of P along a fixed basis direction
-- (here the L axis by a fixed epsilon). No data fitting; the universal
-- morphism P ⊔ P' -> P sends (2i, 2i+1) both back to i.
--
-- This is the minimal inspectable splitter and serves as the categorical
-- baseline against which the K-means and PCA instances are compared.
module ISP.ColorDouble.Coproduct
  ( CatCoproduct (..)
  , coproductEpsilon
  ) where

import ISP.ColorDouble
import ISP.Oklab
import qualified Data.Vector as V

data CatCoproduct = CatCoproduct
  deriving (Eq, Show)

-- | The fixed perturbation applied symmetrically to each bucket.
coproductEpsilon :: Double
coproductEpsilon = 0.02

instance ColorDouble CatCoproduct where
  double CatCoproduct pal ref =
    let pairs = V.map split pal
        newPal = palettePair pairs
        newIdx = assignNearest newPal ref
    in (newPal, newIdx)
    where
      split (Oklab l a b) =
        ( Oklab (l - coproductEpsilon) a b
        , Oklab (l + coproductEpsilon) a b )
