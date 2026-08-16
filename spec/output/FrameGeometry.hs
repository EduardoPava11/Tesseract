{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- FrameGeometry: Universal 768 Crop — Pixel Math
--
-- Universal crop: 768×768 RGB, 256×256 depth.
-- Centered in whatever the TrueDepth sensor gives.
-- Integer steps at 64, 128, 256 output sizes.
--
-- The sensor dims are UNKNOWN at spec time (iPhone 17 Pro TBD).
-- The crop is FIXED: 768×768 RGB, 256×256 depth.
-- The app centers the crop in the sensor buffer at runtime.
-- ════════════════════════════════════════════════════════════════

module FrameGeometry where

import Data.List (sort)

-- ════════════════════════════════════════════════════════════════
-- § 1. UNIVERSAL CROP (from Block.hs)
-- ════════════════════════════════════════════════════════════════

rgbCrop :: Int
rgbCrop = 768

depthCrop :: Int
depthCrop = 256

scaleFactor :: Int
scaleFactor = 3

-- ════════════════════════════════════════════════════════════════
-- § 2. OUTPUT SIZE
-- ════════════════════════════════════════════════════════════════

data OutputSize = Out64 | Out128 | Out256
  deriving (Show, Eq, Ord, Enum, Bounded)

outSide :: OutputSize -> Int
outSide Out64  = 64
outSide Out128 = 128
outSide Out256 = 256

rgbStep :: OutputSize -> Int
rgbStep sz = rgbCrop `div` outSide sz

depthStep :: OutputSize -> Int
depthStep sz = depthCrop `div` outSide sz

-- ════════════════════════════════════════════════════════════════
-- § 3. CROP OFFSET (centered in sensor buffer)
-- ════════════════════════════════════════════════════════════════

-- | Given actual sensor dimensions, compute the crop offset.
--   The crop is centered in the buffer.
rgbCropOffset :: Int -> Int -> (Int, Int)
rgbCropOffset sensorW sensorH =
  ( (sensorW - rgbCrop) `div` 2
  , (sensorH - rgbCrop) `div` 2 )

depthCropOffset :: Int -> Int -> (Int, Int)
depthCropOffset sensorW sensorH =
  ( (sensorW - depthCrop) `div` 2
  , (sensorH - depthCrop) `div` 2 )

-- ════════════════════════════════════════════════════════════════
-- § 4. OUTPUT → SOURCE MAPPING
-- ════════════════════════════════════════════════════════════════

-- | Map output pixel (x,y) to source center coordinate.
--   The step and half-step give the center of each block.
rgbSource :: OutputSize -> Int -> Int -> (Int, Int) -> (Int, Int)
rgbSource sz x y (cropX, cropY) =
  let step = rgbStep sz
      half = step `div` 2
  in (cropX + x * step + half, cropY + y * step + half)

depthSource :: OutputSize -> Int -> Int -> (Int, Int) -> (Int, Int)
depthSource sz x y (cropX, cropY) =
  let step = depthStep sz
      half = step `div` 2
  in (cropX + x * step + half, cropY + y * step + half)

-- ════════════════════════════════════════════════════════════════
-- § 5. AXIOMS
-- ════════════════════════════════════════════════════════════════

allSizes :: [OutputSize]
allSizes = [Out64, Out128, Out256]

-- (G1) Crop fits sensor: 768 ≤ min sensor dim
axiom_G1 :: Int -> Int -> Bool
axiom_G1 sensorW sensorH = rgbCrop <= min sensorW sensorH

axiom_G1_depth :: Int -> Int -> Bool
axiom_G1_depth sensorW sensorH = depthCrop <= min sensorW sensorH

-- (G2) Integer division at all three sizes
axiom_G2 :: Bool
axiom_G2 = all (\sz ->
  rgbCrop `mod` outSide sz == 0 &&
  depthCrop `mod` outSide sz == 0
  ) allSizes

-- (G3) Scale alignment: rgbStep = depthStep × 3
axiom_G3 :: Bool
axiom_G3 = all (\sz -> rgbStep sz == depthStep sz * scaleFactor) allSizes

-- (G4) Exact tiling: step × outSize = crop
axiom_G4 :: Bool
axiom_G4 = all (\sz ->
  rgbStep sz * outSide sz == rgbCrop &&
  depthStep sz * outSide sz == depthCrop
  ) allSizes

-- (G5) All source coordinates in bounds (for a given sensor)
axiom_G5 :: OutputSize -> Int -> Int -> Bool
axiom_G5 sz sensorW sensorH =
  let (cx, cy) = rgbCropOffset sensorW sensorH
      n = outSide sz
  in all (\(x,y) ->
    let (sx, sy) = rgbSource sz x y (cx, cy)
    in sx >= 0 && sx < sensorW && sy >= 0 && sy < sensorH
    ) [(x, y) | x <- [0..n-1], y <- [0..n-1]]

-- (G6) RGB and depth coordinates aligned (same output pixel → same region)
axiom_G6 :: OutputSize -> Int -> Int -> Int -> Int -> Bool
axiom_G6 sz rgbW rgbH dW dH =
  let (rcx, rcy) = rgbCropOffset rgbW rgbH
      (dcx, dcy) = depthCropOffset dW dH
      n = outSide sz
  in all (\(x,y) ->
    let (rx, ry) = rgbSource sz x y (rcx, rcy)
        (dx, dy) = depthSource sz x y (dcx, dcy)
        -- Depth coordinate × 3 should be near RGB coordinate
        -- (offset by crop centering difference, but proportionally aligned)
    in abs ((rx - rcx) - (dx - dcx) * scaleFactor) <= scaleFactor
    && abs ((ry - rcy) - (dy - dcy) * scaleFactor) <= scaleFactor
    ) [(x, y) | x <- [0..n-1], y <- [0..n-1]]

-- (G7) Block spacing is exactly step
axiom_G7 :: Bool
axiom_G7 = all (\sz ->
  let step = rgbStep sz
      (sx0, _) = rgbSource sz 0 0 (0, 0)
      (sx1, _) = rgbSource sz 1 0 (0, 0)
  in sx1 - sx0 == step
  ) allSizes

-- ════════════════════════════════════════════════════════════════
-- § 5b. ★ THE ROTATION, WHICH WAS SHIPPED AND NEVER SPECIFIED
-- ════════════════════════════════════════════════════════════════
--
-- Added 2026-08-15. Solve/Quantize.metal has read the sensor ROTATED
-- since it was written:
--
--   srcX = cropX + gid.y * step + halfStep
--   srcY = cropY + (outputSize - 1 - gid.x) * step + halfStep
--
-- and its comment says "Port of FrameGeometry.hs rgbSource/depthSource
-- ... Verified by Haskell axioms G5-G10 for all 4096 output pixels."
--
-- ★ THAT VERIFICATION WAS VACUOUS, and it is worth saying why rather
-- than just fixing it. G5 is about BOUNDS, G6 about ALIGNMENT, G7
-- about SPACING, and all three are invariant under any relabelling of
-- the output grid. They pass for the rotated read and for the
-- unrotated one equally, so they could never have caught a rotation
-- that was right or wrong. The kernel was gated by axioms that do not
-- discriminate the thing it was doing.
--
-- The reason the rotation exists is real (videoRotationAngle = 90
-- reports portrait dimensions while pixel memory may still be
-- landscape), so the fix is to STATE it, not to remove it. Once it is
-- a function here, one law has three ports: this file, the Swift, and
-- the Metal, and a parity test can compare all three at every one of
-- the 4096 output pixels.

-- | The 90 degree counter-clockwise relabelling of the output grid:
--   output (x, y) reads the source block that the unrotated law would
--   have given to (y, n-1-x). An involution only at n = 1; applied
--   four times it is the identity (G12).
rotateCCW :: Int -> (Int, Int) -> (Int, Int)
rotateCCW n (x, y) = (y, n - 1 - x)

-- | What the shipped kernel actually computes.
rgbSourceRotated :: OutputSize -> Int -> Int -> (Int, Int) -> (Int, Int)
rgbSourceRotated sz x y crop = uncurry (rgbSource sz) (rotateCCW (outSide sz) (x, y)) crop

depthSourceRotated :: OutputSize -> Int -> Int -> (Int, Int) -> (Int, Int)
depthSourceRotated sz x y crop =
  uncurry (depthSource sz) (rotateCCW (outSide sz) (x, y)) crop

-- (G11) ★ THE ROTATION IS A BIJECTION OF THE OUTPUT GRID, so it moves
--        no information: the rotated read visits exactly the same
--        multiset of source blocks as the unrotated one, and visits
--        each exactly once. Whatever else the rotation is, it cannot
--        be a place where signal is lost.
axiom_G11 :: Bool
axiom_G11 = all bijective allSizes
  where
    bijective sz =
      let n = outSide sz
          grid = [(x, y) | x <- [0 .. n-1], y <- [0 .. n-1]]
          img  = map (rotateCCW n) grid
      in sort img == sort grid            -- a permutation of the grid
      && all (\(a, b) -> a >= 0 && a < n && b >= 0 && b < n) img
      && sort (map (\(x, y) -> rgbSourceRotated sz x y (0, 0)) grid)
         == sort (map (\(x, y) -> rgbSource sz x y (0, 0)) grid)

-- (G12) FOUR ROTATIONS ARE THE IDENTITY. The relabelling has order 4
--        exactly, which is what makes "90 degrees" a claim rather
--        than a description.
axiom_G12 :: Bool
axiom_G12 = all order4 allSizes
  where
    order4 sz =
      let n = outSide sz
          r = rotateCCW n
          grid = [(x, y) | x <- [0 .. n-1], y <- [0 .. n-1]]
      in all (\p -> r (r (r (r p))) == p) grid
      && any (\p -> r p /= p) grid
      && all (\p -> r (r p) == (\(x, y) -> (n-1-x, n-1-y)) p) grid

-- (G13) ★ THE ROTATION IS APPLIED TO RGB AND DEPTH ALIKE, which is
--        why G6's alignment survives it. If only one stream were
--        rotated the two would disagree by a quarter turn and the
--        role law would read depth from the wrong place, silently.
--        This is the axiom G5-G10 could not have provided.
axiom_G13 :: Int -> Int -> Int -> Int -> Bool
axiom_G13 rgbW rgbH dW dH = all sameQuarterTurn allSizes
  where
    sameQuarterTurn sz =
      let n = outSide sz
          (rcx, rcy) = rgbCropOffset rgbW rgbH
          (dcx, dcy) = depthCropOffset dW dH
      in all (\(x, y) ->
                let (rx, ry) = rgbSourceRotated sz x y (rcx, rcy)
                    (dx, dy) = depthSourceRotated sz x y (dcx, dcy)
                in abs ((rx - rcx) - (dx - dcx) * scaleFactor) <= scaleFactor
                && abs ((ry - rcy) - (dy - dcy) * scaleFactor) <= scaleFactor)
             [(x, y) | x <- [0 .. n-1], y <- [0 .. n-1]]

-- ★ AND THE ONE THIS FILE STILL DOES NOT SETTLE (stated, not hidden):
-- whether the quarter turn is the RIGHT one, or whether it should be
-- clockwise, is a fact about the sensor's memory layout on a physical
-- iPhone 17. No axiom can decide it and no simulator can either. It is
-- the device pass's question. What these three axioms buy is that the
-- three ports now agree with EACH OTHER, so when the device answers,
-- one edit answers it everywhere.


-- ════════════════════════════════════════════════════════════════
-- § 6. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════"
  putStrLn " FrameGeometry: Universal 768 Crop"
  putStrLn "══════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn $ "  RGB crop:   " ++ show rgbCrop ++ "×" ++ show rgbCrop
  putStrLn $ "  Depth crop: " ++ show depthCrop ++ "×" ++ show depthCrop
  putStrLn $ "  Scale:      " ++ show scaleFactor ++ "×"
  putStrLn ""

  putStrLn "  output  │ RGB step │ depth step"
  putStrLn "  ────────┼──────────┼───────────"
  mapM_ (\sz ->
    putStrLn $ "  " ++ padL 7 (show (outSide sz) ++ "²")
            ++ " │ " ++ padL 8 (show (rgbStep sz))
            ++ " │ " ++ show (depthStep sz)
    ) allSizes
  putStrLn ""

  -- Test with a few realistic sensor sizes
  let sensors = [ ("iPhone 12-15", 1080, 1920, 360, 640)
                , ("iPhone 16 Pro", 1608, 1206, 536, 402)
                , ("Minimum viable", 768, 768, 256, 256)
                ]

  mapM_ (\(name, rw, rh, dw, dh) -> do
    let (rcx, rcy) = rgbCropOffset rw rh
        (dcx, dcy) = depthCropOffset dw dh
    putStrLn $ "── " ++ name ++ " (" ++ show rw ++ "×" ++ show rh ++ " RGB, "
            ++ show dw ++ "×" ++ show dh ++ " depth) ──"
    putStrLn $ "  RGB crop at:   (" ++ show rcx ++ ", " ++ show rcy ++ ")"
    putStrLn $ "  Depth crop at: (" ++ show dcx ++ ", " ++ show dcy ++ ")"
    putStrLn $ "  Fits RGB:      " ++ showB (axiom_G1 rw rh)
    putStrLn $ "  Fits depth:    " ++ showB (axiom_G1_depth dw dh)
    putStrLn $ "  Bounds (64²):  " ++ showB (axiom_G5 Out64 rw rh)
    putStrLn $ "  Aligned (64²): " ++ showB (axiom_G6 Out64 rw rh dw dh)
    putStrLn ""
    ) sensors

  putStrLn "══════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════"
  putStrLn ""
  check "G2  integer division (all sizes)" [axiom_G2]
  check "G3  rgbStep = depthStep × 3"     [axiom_G3]
  check "G4  exact tiling"                 [axiom_G4]
  check "G5  bounds (1080×1920, all sizes)"
    [axiom_G5 sz 1080 1920 | sz <- allSizes]
  check "G6  alignment (1080, 360)"
    [axiom_G6 sz 1080 1920 360 640 | sz <- allSizes]
  check "G7  block spacing = step"         [axiom_G7]
  check "G11 ★ the shipped ROTATION is a bijection: no signal lost"
        [axiom_G11]
  check "G12 four quarter turns are the identity, and none is"
        [axiom_G12]
  check "G13 ★ RGB and depth take the SAME quarter turn"
        [axiom_G13 1080 1920 360 640, axiom_G13 1608 1206 536 402]
  putStrLn ""

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

showB :: Bool -> String
showB True  = "✓"
showB False = "✗"

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
