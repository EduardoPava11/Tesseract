-- DepthSignal.hs
-- Tesseract spec — temporal layer
--
-- THE METERS → SIGNAL CONTRACT, verified in exact rational arithmetic.
--
-- TrueDepth hands the app depth in METERS (DepthFloat16). Every consumer
-- downstream — BinomialCadence.sigmaForDepth, CentroidRefiner face
-- weights, the D-channel preview — speaks the SIGNAL convention:
--
--     s ∈ [0,1],  1 = near (face),  0 = far (background),
--     invalid / missing depth = 1/2 (neutral fill).
--
-- FaceCadence.hs already pins the FACE mode producer to this convention
-- (FC2: nose = 1, background = 0). This file pins the LIVE producer.
-- The law is DISPARITY-AFFINE: TrueDepth's native sensor quantity is
-- disparity (1/m), so the map is linear in disparity — not in meters —
-- between two pinned anchors:
--
--     dNear = 1/4 m   (closest expected face)   → s = 1
--     dFar  = 3/2 m   (background cutoff)       → s = 0
--
--     s(m) = clamp01 ((1/m − 1/dFar) / (1/dNear − 1/dFar))
--          = clamp01 ((3/m − 2) / 10)                    -- exact form
--
-- Why a FIXED map and not per-frame min/max normalization (the old CPU
-- fallback): σ flicker. The epoch cadence σ(s) = σ_base·(2−s) is applied
-- per frame across a 64-frame capture; a per-frame adaptive range makes
-- the same physical face distance produce different σ on consecutive
-- frames, corrupting the temporal cadence. The contract must be a pure
-- function of meters.
--
--   DS1  range          s(m) ∈ [0,1] for every positive depth
--   DS2  monotone       m₁ ≤ m₂ ⇒ s(m₁) ≥ s(m₂)  (nearer is never darker)
--   DS3  golden points  s(1/4)=1, s(1/2)=2/5, s(1)=1/10, s(3/2)=0,
--                       s(2)=0 (clamped), s(1/5)=1 (clamped),
--                       invalid → 1/2 exactly
--   DS4  σ containment  σ(s)/σ_base = 2−s ∈ [1,2] for every reachable s;
--                       in particular σ is never 0 and never NaN
--                       (the raw-meters bug: 2−m ≤ 0 for m ≥ 2)
--
-- Swift twin: Tesseract/Camera/DepthSignal.swift (golden-pinned by
-- TesseractTests/DepthSignalTests.swift). Consumers: MetalPipeline
-- .readbackDepth (GPU path), CameraManager.readDepth (CPU fallback).
--
-- TRUTHFUL harness: every law asserted, main exits nonzero on failure.

module Main where

import Data.Ratio ((%))
import System.Exit (exitFailure, exitSuccess)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE CONTRACT, EXACTLY
-- ════════════════════════════════════════════════════════════════

dNear, dFar, fill :: Rational
dNear = 1 % 4     -- meters
dFar  = 3 % 2     -- meters
fill  = 1 % 2     -- neutral signal for invalid depth

clamp01 :: Rational -> Rational
clamp01 x = max 0 (min 1 x)

-- | The law. Total on positive meters.
signal :: Rational -> Rational
signal m = clamp01 ((recip m - recip dFar) / (recip dNear - recip dFar))

-- | Producer-side totality: what the readback loop actually computes.
--   Nothing models non-finite / non-positive sensor values.
signalOrFill :: Maybe Rational -> Rational
signalOrFill Nothing  = fill
signalOrFill (Just m) | m <= 0    = fill
                      | otherwise = signal m

-- | σ(s)/σ_base from BinomialCadence.sigmaForDepth: σ = σ_base·(2−s).
sigmaRatio :: Rational -> Rational
sigmaRatio s = 2 - s

-- Depth sample grid: 5 cm steps across and beyond the anchor span,
-- plus the anchors themselves and extreme clamp territory.
sampleMeters :: [Rational]
sampleMeters = [dNear, dFar]
            ++ [n % 20 | n <- [1 .. 60]]   -- 0.05 m … 3.00 m
            ++ [4, 10]

-- ════════════════════════════════════════════════════════════════
-- § 2. THE LAWS
-- ════════════════════════════════════════════════════════════════

ds1_range :: Bool
ds1_range = all (\m -> let s = signal m in 0 <= s && s <= 1) sampleMeters

ds2_monotone :: Bool
ds2_monotone = and [ signal m1 >= signal m2
                   | m1 <- sampleMeters, m2 <- sampleMeters, m1 <= m2 ]

ds3_golden :: Bool
ds3_golden = and
  [ signal (1 % 4) == 1
  , signal (1 % 2) == 2 % 5
  , signal 1       == 1 % 10
  , signal (3 % 2) == 0
  , signal 2       == 0          -- clamped, NOT negative
  , signal (1 % 5) == 1          -- clamped, NOT > 1
  , signalOrFill Nothing    == 1 % 2
  , signalOrFill (Just 0)   == 1 % 2
  , signalOrFill (Just (-1)) == 1 % 2
  ]

ds4_sigma :: Bool
ds4_sigma = all ok (fill : map signal sampleMeters)
  where ok s = let r = sigmaRatio s in 1 <= r && r <= 2

-- ════════════════════════════════════════════════════════════════
-- § 3. HARNESS
-- ════════════════════════════════════════════════════════════════

check :: String -> Bool -> IO Bool
check name ok = do
  putStrLn ((if ok then "  ✓ " else "  ✗ ") ++ name)
  return ok

main :: IO ()
main = do
  putStrLn "DepthSignal: meters → [0,1] signal contract (LIVE producer)"
  results <- sequence
    [ check "DS1 range: s(m) ∈ [0,1] on the sample grid"        ds1_range
    , check "DS2 monotone: nearer is never darker"               ds2_monotone
    , check "DS3 golden points (incl. clamps and 1/2 fill)"      ds3_golden
    , check "DS4 σ/σ_base = 2−s ∈ [1,2]; σ never 0, never NaN"   ds4_sigma
    ]
  if and results then exitSuccess else exitFailure
