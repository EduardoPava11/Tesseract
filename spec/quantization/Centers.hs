-- Centers.hs
-- Tesseract spec — quantization layer
--
-- THE CELL-CENTER RECONSTRUCTION THEOREM, verified in exact rational
-- arithmetic (no floating point anywhere in the proofs).
--
-- The app quantizes each color channel by the floor map
--     E(x) = min 3 ⌊4x⌋            (encoder, {0..3})
-- and reconstructs by the cell center
--     D(k) = (k + 1/2) / 4         (decoder, {1/8, 3/8, 5/8, 7/8})
-- i.e. sRGB bytes {32, 96, 159, 223} (Swift: TessLevel.byte,
-- TesseractCoord.sRGB8; Metal: Quantize.metal).
--
-- These axioms prove the center choice is not a taste decision but the
-- unique solution to four independent optimality conditions:
--
--   CN1  byte parity          D matches the Swift 8-bit table exactly
--   CN2  section law          E ∘ D = id  (decode then encode is identity)
--   CN3  equal measure        the 4 cells partition [0,1) into equal
--                             widths 1/4; the 4D cell volume is 1/256 =
--                             1/|palette| — one lattice point per equal
--                             measure of the hypercube
--   CN4  centroid condition   D(k) = centroid of cell k under uniform
--                             density; per-cell MSE = Δ³/12 = 1/768,
--                             and by the parallel-axis theorem ANY other
--                             reconstruction r pays exactly
--                             Δ·(r − mid)² more — computed exactly for
--                             the legacy endpoint scheme r = k/3
--   CN5  total distortion     E‖x − D(E(x))‖² over the RGB cube
--                             [0,1)³ = 3·Δ²/12 = 1/64 exactly
--   CN6  Lloyd fixed point    the Voronoi partition of the center set
--                             IS the floor partition (boundaries at
--                             k/4), so floor-encoding ≡ nearest-center
--                             encoding: the quantizer satisfies BOTH
--                             Lloyd-Max optimality conditions at once.
--                             The endpoint set {0,1/3,2/3,1} fails this:
--                             its Voronoi widths are {1/6,1/3,1/3,1/6}.
--
-- The computational consequences (tensor formulation, SIMD lane
-- layout, SIMT branch-free encoding) are documented in
-- ../../docs/CENTERS.md. This file is also the template for a
-- TRUTHFUL spec: every law is asserted and main exits nonzero on any
-- failure (exitFailure), unlike the print-only style it replaces.

module Main where

import Data.Ratio (Rational, (%))
import System.Exit (exitFailure, exitSuccess)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE QUANTIZER, EXACTLY
-- ════════════════════════════════════════════════════════════════

levels :: [Integer]
levels = [0, 1, 2, 3]

delta :: Rational
delta = 1 % 4                                   -- cell width Δ

-- | Encoder: floor cell of x ∈ [0,1), clamped.
encode :: Rational -> Integer
encode x = min 3 (floor (4 * x))

-- | Decoder: cell CENTER (the app's choice).
center :: Integer -> Rational
center k = (fromInteger k + 1 % 2) / 4

-- | Legacy decoder: endpoints k/3 (the Tesseract64 scheme, rejected).
endpoint :: Integer -> Rational
endpoint k = fromInteger k % 3

-- | Cell k = [lo, hi) under the floor partition.
cell :: Integer -> (Rational, Rational)
cell k = (fromInteger k % 4, (fromInteger k + 1) % 4)

-- ════════════════════════════════════════════════════════════════
-- § 2. EXACT MOMENT INTEGRALS (closed form, Rational)
-- ════════════════════════════════════════════════════════════════

-- | ∫_a^b (x − r)² dx = ((b−r)³ − (a−r)³) / 3, exact.
sqErr :: Rational -> Rational -> Rational -> Rational
sqErr a b r = ((b - r)^(3 :: Int) - (a - r)^(3 :: Int)) / 3

-- | Per-cell MSE of a decoder d on cell k (uniform density, unnormalized:
--   this is the ∫ over the cell; divide by Δ for the conditional mean).
cellMSE :: (Integer -> Rational) -> Integer -> Rational
cellMSE d k = let (a, b) = cell k in sqErr a b (d k)

-- ════════════════════════════════════════════════════════════════
-- § 3. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- CN1: 8-bit parity with Swift — round(center·255) = {32, 96, 159, 223}
axiom_CN1 :: Bool
axiom_CN1 = map (roundR . (* 255) . center) levels == [32, 96, 159, 223]
  where roundR r = floor (r + 1 % 2) :: Integer

-- CN2: section law — encode (center k) = k for every level.
--      (The reconstruction points are fixed points of the round trip.)
axiom_CN2 :: Bool
axiom_CN2 = [encode (center k) | k <- levels] == levels

-- CN3: equal measure — all cell widths are Δ = 1/4, the cells tile
--      [0,1) exactly, and the 4D product cell volume is 1/256.
axiom_CN3 :: Bool
axiom_CN3 =
  all (\k -> let (a, b) = cell k in b - a == delta) levels
  && fst (cell 0) == 0
  && snd (cell 3) == 1
  && and [snd (cell k) == fst (cell (k + 1)) | k <- [0 .. 2]]
  && delta ^ (4 :: Int) == 1 % 256

-- CN4: centroid condition. Exactly, per cell:
--        MSE_center(k) = Δ³/12 = 1/768
--      and for the endpoint decoder, by the parallel-axis theorem:
--        MSE_endpoint(k) = MSE_center(k) + Δ·(endpoint k − center k)²
--      with the excess STRICTLY positive for every k (endpoints never
--      hit a centroid: 0≠1/8, 1/3≠3/8, 2/3≠5/8, 1≠7/8).
axiom_CN4 :: Bool
axiom_CN4 =
  all (\k -> cellMSE center k == delta ^ (3 :: Int) / 12) levels
  && all (\k ->
        cellMSE endpoint k
          == cellMSE center k + delta * (endpoint k - center k)^(2 :: Int)
     ) levels
  && all (\k -> cellMSE endpoint k > cellMSE center k) levels

-- CN5: total distortion — E‖x − D(E(x))‖² over the RGB cube [0,1)³ is
--      3 · Δ²/12 = 1/64 exactly (axes independent, error tensorizes).
axiom_CN5 :: Bool
axiom_CN5 =
  let perAxis = sum (map (cellMSE center) levels)   -- = Δ²/12 = 1/192
  in perAxis == delta ^ (2 :: Int) / 12
     && 3 * perAxis == 1 % 64

-- CN6: Lloyd fixed point — the Voronoi boundaries of the center set are
--      the floor boundaries {1/4, 2/4, 3/4}, so nearest-center encoding
--      coincides with floor encoding (both Lloyd-Max conditions hold
--      simultaneously — the quantizer is a fixed point of Lloyd
--      iteration). The endpoint set is NOT: its Voronoi widths are
--      {1/6, 1/3, 1/3, 1/6}, violating CN3's equal measure.
axiom_CN6 :: Bool
axiom_CN6 =
  let mid d k = (d k + d (k + 1)) / 2
      centerBounds   = [mid center k   | k <- [0 .. 2]]
      endpointBounds = [mid endpoint k | k <- [0 .. 2]]
      endpointWidths =
        zipWith (-) (endpointBounds ++ [1]) (0 : endpointBounds)
  in centerBounds == [1 % 4, 2 % 4, 3 % 4]
     && endpointWidths == [1 % 6, 1 % 3, 1 % 3, 1 % 6]
     && endpointWidths /= replicate 4 delta

-- ════════════════════════════════════════════════════════════════
-- § 4. TRUTHFUL HARNESS — exits nonzero on any failure
-- ════════════════════════════════════════════════════════════════

axioms :: [(String, Bool)]
axioms =
  [ ("CN1 byte parity {32,96,159,223}",            axiom_CN1)
  , ("CN2 section law  E∘D = id",                  axiom_CN2)
  , ("CN3 equal measure, cell volume 1/256",       axiom_CN3)
  , ("CN4 centroid condition + parallel axis",     axiom_CN4)
  , ("CN5 total distortion = 1/64 exact",          axiom_CN5)
  , ("CN6 Lloyd fixed point (Voronoi = floor)",    axiom_CN6)
  ]

main :: IO ()
main = do
  putStrLn "── Centers.hs: cell-center reconstruction, exact ──"
  results <- mapM (\(name, ok) -> do
    putStrLn $ "  " ++ (if ok then "✓" else "✗") ++ " " ++ name
    pure ok) axioms
  putStrLn ""
  if and results
    then do
      putStrLn $ "  " ++ show (length results) ++ "/"
                       ++ show (length results) ++ " centers axioms hold (Rational-exact)"
      exitSuccess
    else do
      putStrLn "  CENTERS AXIOM FAILURE"
      exitFailure
