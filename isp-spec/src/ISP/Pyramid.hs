-- | 8-level scale hierarchy with the S * K = 4096 conservation law.
module ISP.Pyramid
  ( Level (..)
  , allLevels
  , pyramidS
  , pyramidK
  , conservedProduct
  , conservationHolds
  , pickByTargetK
  , pickByDeltaT
  ) where

import Data.List (minimumBy)
import Data.Ord (comparing)

data Level = L1 | L2 | L3 | L4 | L5 | L6 | L7 | L8
  deriving (Eq, Show, Ord, Enum, Bounded)

allLevels :: [Level]
allLevels = [minBound .. maxBound]

-- Spatial side length of a GIF frame at each level.
pyramidS :: Level -> Int
pyramidS L1 = 2048
pyramidS L2 = 1024
pyramidS L3 = 512
pyramidS L4 = 256
pyramidS L5 = 128
pyramidS L6 = 64
pyramidS L7 = 32
pyramidS L8 = 16

-- Number of frames (and palette size) at each level.
pyramidK :: Level -> Int
pyramidK L1 = 2
pyramidK L2 = 4
pyramidK L3 = 8
pyramidK L4 = 16
pyramidK L5 = 32
pyramidK L6 = 64
pyramidK L7 = 128
pyramidK L8 = 256

conservedProduct :: Int
conservedProduct = 4096

conservationHolds :: Level -> Bool
conservationHolds l = pyramidS l * pyramidK l == conservedProduct

-- Pick the level whose K is closest to a target frame count.
pickByTargetK :: Int -> Level
pickByTargetK target = minimumBy (comparing (\l -> abs (pyramidK l - target))) allLevels

-- Pick a level such that frame_delay = deltaT / K is at least tickSec (the
-- minimum GIF tick, typically 10 ms). Prefers higher K within that bound.
pickByDeltaT :: Double -> Double -> Level
pickByDeltaT deltaT tickSec =
  let maxK = max 1 (floor (deltaT / tickSec) :: Int)
  in pickByTargetK maxK
