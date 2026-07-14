module Main (main) where

import qualified Data.Vector.Unboxed as VU
import           Data.Word           (Word16)
import           System.Directory    (createDirectoryIfMissing)

import ISP.DNG

-- Generate two synthetic CFA DNGs with correlated content plus mild
-- per-capture drift. Width/height are small so tests stay fast.
main :: IO ()
main = do
  createDirectoryIfMissing True "fixtures/dng"
  let w = 256
      h = 256
      sm = defaultSensorMeta
      aPix = VU.generate (w * h) (synth w h 0)
      bPix = VU.generate (w * h) (synth w h 1)
  writeTestDNG "fixtures/dng/a.dng" sm w h aPix
  writeTestDNG "fixtures/dng/b.dng" sm w h bPix
  putStrLn "Wrote fixtures/dng/a.dng and fixtures/dng/b.dng"

-- Simple Bayer-aware synthetic scene: color gradient + phase shift between
-- captures so the two DNGs actually differ along T.
synth :: Int -> Int -> Int -> Int -> Word16
synth w h phase k =
  let (j, i) = k `divMod` w
      x     = fromIntegral i / fromIntegral (w - 1) :: Double
      y     = fromIntegral j / fromIntegral (h - 1) :: Double
      iMod2 = i `mod` 2
      jMod2 = j `mod` 2
      base = case (jMod2, iMod2) of
               (0, 0) -> 0.9 * x                -- R
               (0, 1) -> 0.6 * (x + y) / 2      -- Gr
               (1, 0) -> 0.6 * (x + y) / 2      -- Gb
               _      -> 0.9 * y                -- B
      drift = 0.05 * fromIntegral phase * sin (6.283185 * x)
      v = max 0 (min 1 (base + drift))
  in fromIntegral (round (v * 65535) :: Int)
