-- | L6 fingerprint extraction: 16x16 index plane + 64-color Oklab palette.
--
-- Given a 1024x1024 Oklab frame, run the pyramid-double path:
--
-- > L0 1024^2  (Oklab full color)
-- > L1  512^2   2 colors  (Bayer ordered dither on L-channel)
-- > L2  256^2   4 colors  (ColorDouble)
-- > L3  128^2   8 colors  (ColorDouble)
-- > L4   64^2  16 colors  (ColorDouble)
-- > L5   32^2  32 colors  (ColorDouble)
-- > L6   16^2  64 colors  (ColorDouble)  <- fingerprint
--
-- The full sequence of 7 planes (as Oklab floats, L1 lifted via 'bwToOklab')
-- is also returned so the Laplacian-style reconstruction in ISP.Compose can
-- combine them into a single 64x64 frame.
module ISP.Fingerprint
  ( Fingerprint (..)
  , PyramidStack (..)
  , extractFingerprint
  , pyramidL0toL6
  , bwL1ToPaletteState
  ) where

import qualified Data.Vector as V
import ISP.Oklab
import ISP.Bayer.Dither (BayerMat, bayerDownsampleBW)
import ISP.ColorDouble

-- | The fingerprint: 16x16 index plane and its 64-color Oklab palette.
data Fingerprint = Fingerprint
  { fpIndices :: !(Plane Int)
  , fpPalette :: !OklabPalette
  }
  deriving (Eq, Show)

-- | All 7 pyramid levels as Oklab-valued planes. Later levels are the
-- palette-indexed planes lifted back to Oklab via 'paletteLift' so the
-- composition pass can operate uniformly in Oklab space.
data PyramidStack = PyramidStack
  { pL0 :: !(Plane Oklab)   -- 1024 x 1024
  , pL1 :: !(Plane Oklab)   --  512 x  512
  , pL2 :: !(Plane Oklab)   --  256 x  256
  , pL3 :: !(Plane Oklab)   --  128 x  128
  , pL4 :: !(Plane Oklab)   --   64 x   64  (output resolution)
  , pL5 :: !(Plane Oklab)   --   32 x   32
  , pL6 :: !(Plane Oklab)   --   16 x   16  (fingerprint as Oklab)
  }

-- | Full pyramid from a 1024x1024 Oklab frame using the supplied dither
-- matrix and doubling operator.
pyramidL0toL6
  :: ColorDouble op
  => BayerMat
  -> op
  -> Plane Oklab
  -> (PyramidStack, Fingerprint)
pyramidL0toL6 bm op l0 =
  let -- Pre-downsample L0 to each subsequent level (mean filter chain).
      l0_512 = downsampleMean2Oklab l0
      l0_256 = downsampleMean2Oklab l0_512
      l0_128 = downsampleMean2Oklab l0_256
      l0_64  = downsampleMean2Oklab l0_128
      l0_32  = downsampleMean2Oklab l0_64
      l0_16  = downsampleMean2Oklab l0_32

      -- L0 -> L1: Bayer ordered dither on L channel at 512 resolution.
      l1Bool = bayerDownsampleBW bm l0
      (pal1, idx1) = bwL1ToPaletteState l1Bool

      -- Successive doublings.
      (pal2, idx2) = double op pal1 l0_256
      (pal3, idx3) = double op pal2 l0_128
      (pal4, idx4) = double op pal3 l0_64
      (pal5, idx5) = double op pal4 l0_32
      (pal6, idx6) = double op pal5 l0_16

      -- Lift palette-indexed planes back to Oklab for the composition pass.
      lift pal idx = planeMap (pal V.!) idx
      stack = PyramidStack
        { pL0 = l0
        , pL1 = lift pal1 idx1
        , pL2 = lift pal2 idx2
        , pL3 = lift pal3 idx3
        , pL4 = lift pal4 idx4
        , pL5 = lift pal5 idx5
        , pL6 = lift pal6 idx6
        }
      fp = Fingerprint idx6 pal6
  in (stack, fp)

-- | Convenience: drop the full stack and just return the fingerprint.
extractFingerprint
  :: ColorDouble op
  => BayerMat
  -> op
  -> Plane Oklab
  -> Fingerprint
extractFingerprint bm op = snd . pyramidL0toL6 bm op

-- | Convert a Bool plane from 'bayerDownsampleBW' into an initial
-- (palette, indices) state: False -> black, True -> white.
bwL1ToPaletteState :: Plane Bool -> (OklabPalette, Plane Int)
bwL1ToPaletteState bp =
  let pal = mkPalette [Oklab 0 0 0, Oklab 1 0 0]
      idx = planeMap (\b -> if b then 1 else 0) bp
  in (pal, idx)
