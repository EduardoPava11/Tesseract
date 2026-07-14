-- | Bayer quad types and the V4 (Klein four-group) spatial symmetry.
module ISP.Bayer
  ( Quad (..)
  , CFAPattern (..)
  , channelAt
  , selectChan
  , zipQuadWith
  , mapQuad
  , V4 (..)
  , applyV4
  , v4All
  ) where

import ISP.Sensor.Physics (Channel (..))

-- Bayer 2x2 supercell packed in RGGB order. Layout:
--   qR  qGr
--   qGb qB
data Quad a = Quad
  { qR  :: !a
  , qGr :: !a
  , qGb :: !a
  , qB  :: !a
  }
  deriving (Eq, Show, Functor)

data CFAPattern = RGGB | BGGR | GRBG | GBRG
  deriving (Eq, Show, Enum, Bounded)

channelAt :: CFAPattern -> Int -> Int -> Channel
channelAt pat i j =
  let r = i `mod` 2
      c = j `mod` 2
  in case pat of
       RGGB -> pick r c R  Gr Gb B
       BGGR -> pick r c B  Gb Gr R
       GRBG -> pick r c Gr R  B  Gb
       GBRG -> pick r c Gb B  R  Gr
  where
    pick 0 0 a _ _ _ = a
    pick 0 1 _ b _ _ = b
    pick 1 0 _ _ c_ _ = c_
    pick 1 1 _ _ _ d = d
    pick _ _ _ _ _ _ = error "channelAt: unreachable"

selectChan :: Channel -> Quad a -> a
selectChan R  = qR
selectChan Gr = qGr
selectChan Gb = qGb
selectChan B  = qB

zipQuadWith :: (a -> b -> c) -> Quad a -> Quad b -> Quad c
zipQuadWith f (Quad r1 g1 h1 b1) (Quad r2 g2 h2 b2) =
  Quad (f r1 r2) (f g1 g2) (f h1 h2) (f b1 b2)

mapQuad :: (a -> b) -> Quad a -> Quad b
mapQuad = fmap

-- Klein four-group V4 = {E, H, V, HV} acting on a 2x2 supercell by
-- permuting the four positions. Channel identity moves with the pixel.
data V4 = E | H | V | HV
  deriving (Eq, Show, Enum, Bounded)

v4All :: [V4]
v4All = [minBound .. maxBound]

-- H = flip left/right: rows swap cols within row
-- V = flip top/bottom: cols swap rows within col
-- HV = 180 deg
applyV4 :: V4 -> Quad a -> Quad a
applyV4 E  q = q
applyV4 H  (Quad r g h b) = Quad g  r  b  h
applyV4 V  (Quad r g h b) = Quad h  b  r  g
applyV4 HV (Quad r g h b) = Quad b  h  g  r
