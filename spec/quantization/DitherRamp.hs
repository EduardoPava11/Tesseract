{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- DitherRamp: The Dyadic Dither Ramp 16² → 4096² at K = 64
--
-- One palette (256 colors), one frame count (K = 64), nine dyadic
-- square resolutions:
--
--   S ∈ {2⁴, 2⁵, ..., 2¹²} = {16, 32, 64, ..., 2048, 4096}
--
-- The BOTTOM rung is the bijection: 16² = 256 pixels, one per
-- palette entry — the palette IS the image (BellPalette BP4).
-- The TOP rung is the identity 4096 = 16 × 256: bijection side
-- times palette size. Between them, occupancy S²/256 climbs the
-- powers of four — the ramp along which dithering turns a 256-
-- color palette into a continuous-looking image.
--
-- The top rung is set by the SENSOR, not the format: the largest
-- dyadic square inside the 6048² centered crop of an 8064×6048
-- readout is 4096²; GIF's 65535-per-side ceiling never binds.
--
-- Rungs relate by exact factor-2 decimation in the INDEX domain:
-- nearest-neighbor decimation of a replicated frame recovers it —
-- the GIFEncoder replicate/decimate contract, rung to rung.
-- ════════════════════════════════════════════════════════════════

module DitherRamp where

import Data.List (sort)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE RAMP
-- ════════════════════════════════════════════════════════════════

rungs :: [Int]
rungs = [2 ^ k | k <- [4 .. 12 :: Int]]

kFrames :: Int
kFrames = 64

paletteSize :: Int
paletteSize = 256

-- | Occupancy at rung S: expected pixels per palette color, S²/256.
occupancy :: Int -> Int
occupancy s = s * s `div` paletteSize

-- ════════════════════════════════════════════════════════════════
-- § 2. CEILINGS AND MEMORY
-- ════════════════════════════════════════════════════════════════

sensorW, sensorH :: Int
sensorW = 8064
sensorH = 6048

-- | The centered square crop: side = min dimension.
cropSide :: Int
cropSide = min sensorW sensorH

-- | GIF logical-screen fields are u16: 65535 per side, hard max.
gifCeiling :: Int
gifCeiling = 65535

-- | Largest power of two ≤ n.
largestDyadicIn :: Int -> Int
largestDyadicIn n = last (takeWhile (<= n) [2 ^ k | k <- [0 .. 30 :: Int]])

-- | Index bytes for a burst: one byte per pixel per frame, S²·64.
indexBytes :: Int -> Int
indexBytes s = s * s * kFrames

-- | Decode canvas allocation: RGBA, S²·4 bytes (ONE canvas — GIF
--   decodes frame-at-a-time over a single canvas).
canvasBytes :: Int -> Int
canvasBytes s = s * s * 4

-- ════════════════════════════════════════════════════════════════
-- § 3. REPLICATE / DECIMATE (the GIFEncoder contract)
--
-- replicate2D doubles each pixel in both axes (S² → (2S)²).
-- decimate keeps every even row and column ((2S)² → S²) — the
-- nearest-neighbor decimation with the TOP-LEFT convention.
-- ════════════════════════════════════════════════════════════════

type Frame = [[Int]]   -- rows of palette indices

replicate2D :: Frame -> Frame
replicate2D = concatMap (\r -> let d = concatMap (\x -> [x, x]) r in [d, d])

decimate :: Frame -> Frame
decimate = map evens . evens
  where
    evens (x : _ : t) = x : evens t
    evens [x]         = [x]
    evens []          = []

-- ════════════════════════════════════════════════════════════════
-- § 4. DETERMINISTIC PSEUDO-RANDOMNESS (no System.Random)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

-- | Infinite uniform [0,1) stream from a seed.
uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

-- | Uniform random frame at rung S: S² palette indices, S rows.
randomFrame :: Int -> Int -> Frame
randomFrame seed s = chunk s (take (s * s) [floor (u * 256) | u <- uniforms seed])

chunk :: Int -> [a] -> [[a]]
chunk _ [] = []
chunk n xs = take n xs : chunk n (drop n xs)

-- | Per-palette-entry counts (the ResolutionLadder span walk).
histogram :: [Int] -> [Int]
histogram xs = go 0 (sort xs)
  where
    go i ys | i == 256  = []
            | otherwise = let (h, t) = span (== i) ys
                          in length h : go (i + 1) t

-- ════════════════════════════════════════════════════════════════
-- § 5. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (DR1) Rung set: S ∈ {2⁴..2¹²}, exactly 9 dyadic rungs. Rung 16
--       is the bijection (16² = 256 — ties BellPalette BP4); rung
--       4096 satisfies the identity 4096 = 16 × 256, bijection
--       side × palette size.
axiom_DR1 :: Bool
axiom_DR1 =
     rungs == [16, 32, 64, 128, 256, 512, 1024, 2048, 4096]
  && length rungs == 9
  && head rungs == 16 && 16 * 16 == paletteSize          -- bijection rung
  && last rungs == 4096 && 4096 == 16 * paletteSize      -- side × palette LAW
  && and (zipWith (\a b -> b == 2 * a) rungs (tail rungs))

-- (DR2) Occupancy: S²/256 divides exactly at every rung, giving
--       {1,4,16,...,65536} — powers of four. Under the null model
--       B(S², 1/256): mean = S²/256 = occupancy exactly, variance
--       = mean·(255/256) — the Poisson limit (var ≈ mean at small
--       p, var/mean = 1 − p, always just under 1). Checked by
--       formula at all rungs and empirically at S = 64 and 128.
axiom_DR2 :: Bool
axiom_DR2 =
     map occupancy rungs
       == [1, 4, 16, 64, 256, 1024, 4096, 16384, 65536]
  && all (\s -> (s * s) `mod` paletteSize == 0) rungs
  && all meanVar rungs
  && all empirical [64, 128]
  where
    p = 1 / 256 :: Double
    meanVar s =
      let n    = s * s
          mean = fromIntegral n * p
          var  = fromIntegral n * p * (1 - p)
      in mean == fromIntegral (occupancy s)          -- mean is EXACT
      && abs (var / mean - (1 - p)) < 1e-12          -- Poisson limit
      && var < mean                                  -- from below
    empirical s =
      let h    = histogram (concat (randomFrame (s * 7 + 1) s))
          mean = fromIntegral (sum h) / 256 :: Double
          sd   = sqrt (sum [(fromIntegral c - mean) ^ (2 :: Int) | c <- h] / 256)
          ref  = sqrt (fromIntegral (s * s) * p * (1 - p))
      in sum h == s * s
      && abs (mean - fromIntegral (occupancy s)) < 1e-9
      && abs (sd - ref) < ref * 0.3

-- (DR3) Sensor ceiling: the centered crop of 8064×6048 is 6048²
--       (integral margins), the largest dyadic square inside it is
--       4096² = the top rung, and GIF's 65535 ceiling never binds
--       (the sensor cuts the ramp off three octaves earlier).
axiom_DR3 :: Bool
axiom_DR3 =
     cropSide == 6048
  && cropSide == min sensorW sensorH
  && (sensorW - cropSide) `mod` 2 == 0                  -- centered, integral
  && 2 ^ (12 :: Int) <= cropSide && 2 ^ (13 :: Int) > cropSide
  && largestDyadicIn cropSide == 4096
  && last rungs == largestDyadicIn cropSide             -- sensor sets the top
  && all (<= gifCeiling) rungs
  && largestDyadicIn gifCeiling == 32768                -- format allows 2¹⁵
  && largestDyadicIn cropSide < largestDyadicIn gifCeiling  -- so it never binds

-- (DR4) Memory law: index bytes = S²·64; at the top rung EXACTLY
--       2³⁰ bytes (1 GiB). Decode canvas S²·4 bytes stays ≤ 64 MiB
--       everywhere (equality at the top rung: 4096²·4 = 2²⁶).
axiom_DR4 :: Bool
axiom_DR4 =
     indexBytes 4096 == 2 ^ (30 :: Int)
  && canvasBytes 4096 == 64 * 2 ^ (20 :: Int)
  && all (\s -> canvasBytes s <= 64 * 2 ^ (20 :: Int)) rungs
  && and (zipWith (<) (map indexBytes rungs) (tail (map indexBytes rungs)))

-- (DR5) Dither-scale monotonicity: the relative sampling error of
--       a color's count is 1/√occupancy = 16/S EXACTLY (occupancy
--       is a perfect square at every rung). It strictly decreases
--       up the ramp and reaches 1/256 at the top rung.
axiom_DR5 :: Bool
axiom_DR5 =
     errs == [16 / fromIntegral s | s <- rungs]         -- 1/√occ = 16/S, exact
  && and (zipWith (>) errs (tail errs))                 -- strictly decreasing
  && last errs == 1 / 256                               -- top rung, ≤ 1/256
  where
    errs = [1 / sqrt (fromIntegral (occupancy s)) | s <- rungs]

-- (DR6) Conservation with the ladder: adjacent rungs differ by
--       factor 2; decimate ∘ replicate2D = id on frames (nearest-
--       neighbor decimation of a replicated frame recovers it
--       EXACTLY, in the index domain), including two-rung chains —
--       the GIFEncoder replicate/decimate contract. The law is
--       size-independent; it is exercised at S ≤ 128.
axiom_DR6 :: Bool
axiom_DR6 =
     and (zipWith (\a b -> b == 2 * a) rungs (tail rungs))
  && all roundTrip [16, 32, 64, 128]
  && all chain [16, 32, 64]
  where
    roundTrip s =
      let f  = randomFrame (s + 5) s
          up = replicate2D f
      in decimate up == f
      && length up == 2 * s && all ((== 2 * s) . length) up
    chain s =
      let f = randomFrame (s + 9) s
      in decimate (decimate (replicate2D (replicate2D f))) == f

-- ════════════════════════════════════════════════════════════════
-- § 6. VISUALIZATION
-- ════════════════════════════════════════════════════════════════

showRamp :: IO ()
showRamp = do
  putStrLn "  rung S │ pixels S²  │ px/color │ 1/√occ │ index bytes S²·64"
  putStrLn "  ───────┼────────────┼──────────┼────────┼──────────────────"
  mapM_ row rungs
  where
    row s = putStrLn $
         "  " ++ padL 6 (show s)
      ++ " │ " ++ padL 10 (show (s * s))
      ++ " │ " ++ padL 8 (show (occupancy s))
      ++ " │ " ++ padL 6 (showF (16 / fromIntegral s))
      ++ " │ " ++ padL 13 (show (indexBytes s))
      ++ (if s == head rungs then "   ← bijection (BP4)" else "")
      ++ (if s == last rungs then "   = 2³⁰ (1 GiB)" else "")

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " DitherRamp: The Dyadic Dither Ramp 16² → 4096² at K = 64"
  putStrLn " Nine rungs. Bottom = bijection. Top = 16 × 256 = 4096."
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The Ramp ──"
  putStrLn ""
  showRamp
  putStrLn ""

  putStrLn "── Ceilings ──"
  putStrLn ""
  putStrLn $ "  sensor readout   : " ++ show sensorW ++ " × " ++ show sensorH
  putStrLn $ "  centered crop    : " ++ show cropSide ++ "²  (margin "
          ++ show ((sensorW - cropSide) `div` 2) ++ " px each side)"
  putStrLn $ "  largest dyadic   : " ++ show (largestDyadicIn cropSide)
          ++ "²  (2¹³ = 8192 > " ++ show cropSide ++ ")"
  putStrLn $ "  GIF format max   : " ++ show gifCeiling
          ++ " per side (u16) — would allow "
          ++ show (largestDyadicIn gifCeiling) ++ "², never binds"
  putStrLn ""

  putStrLn "── The 64² Rung vs B(4096, 1/256) (seed 449) ──"
  putStrLn ""
  let h    = histogram (concat (randomFrame 449 64))
      mean = fromIntegral (sum h) / 256 :: Double
      sd   = sqrt (sum [(fromIntegral c - mean) ^ (2 :: Int) | c <- h] / 256)
  putStrLn $ "  B(4096, 1/256): E = " ++ showF (4096 / 256)
          ++ ", SD = " ++ showF (sqrt (4096 * (1/256) * (255/256)))
  putStrLn $ "  empirical:      E = " ++ showF mean ++ ", SD = " ++ showF sd
  putStrLn "  (var/mean = 255/256 — the Poisson limit, just under 1)"
  putStrLn ""

  putStrLn "── Replicate / Decimate (4×4 corner of the 16² frame) ──"
  putStrLn ""
  let f      = randomFrame 21 16
      corner = map (take 4) . take 4
  mapM_ (putStrLn . ("  " ++) . unwords . map (padL 3 . show)) (corner f)
  putStrLn "        ↓ replicate2D (8×8 corner)      ↓ decimate recovers"
  mapM_ (putStrLn . ("  " ++) . unwords . map (padL 3 . show))
        (map (take 8) (take 8 (replicate2D f)))
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "DR1 rung set: 9 dyadic rungs 2⁴..2¹²; 4096 = 16 × 256"        [axiom_DR1]
  check "DR2 occupancy S²/256 exact; B(S²,1/256) mean/var; Poisson"    [axiom_DR2]
  check "DR3 sensor ceiling: 4096² in 6048² crop; GIF 65535 unbound"   [axiom_DR3]
  check "DR4 memory: S²·64 index bytes, 2³⁰ at top; canvas ≤ 64 MiB"   [axiom_DR4]
  check "DR5 error ramp: 1/√occ = 16/S strictly falls to 1/256"        [axiom_DR5]
  check "DR6 conservation: decimate ∘ replicate2D = id, rung to rung"  [axiom_DR6]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  16² → 4096²: nine dyadic rungs, one palette, K = 64."
  putStrLn ""
  putStrLn "  The bottom rung is the bijection — one pixel per"
  putStrLn "  palette entry, the palette IS the image (BP4). Each"
  putStrLn "  rung up multiplies occupancy by 4 and halves the"
  putStrLn "  relative dither error 16/S, down to 1/256 at the top."
  putStrLn ""
  putStrLn "  The top rung 4096 = 16 × 256 is where the ramp meets"
  putStrLn "  the sensor: the largest dyadic square in the 6048²"
  putStrLn "  crop. GIF's 65535 ceiling never binds — the format"
  putStrLn "  outlives the optics."
  putStrLn ""
  putStrLn "  Rungs are conserved, not resampled: replicate up,"
  putStrLn "  decimate down, recover exactly — in the index domain."
  putStrLn "══════════════════════════════════════════════════════════"

-- Helpers (no-scientific-notation formatter: integer math, 3 dp)
showF :: Double -> String
showF x =
  let n    = round (abs x * 1000) :: Int
      sign = if x < 0 then "-" else ""
      frac = show (n `mod` 1000)
      pad3 = replicate (3 - length frac) '0' ++ frac
  in sign ++ show (n `div` 1000) ++ "." ++ pad3

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
