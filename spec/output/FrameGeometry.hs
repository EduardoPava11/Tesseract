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
