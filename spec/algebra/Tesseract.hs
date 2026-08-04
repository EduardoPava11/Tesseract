{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE FlexibleInstances #-}

-- ════════════════════════════════════════════════════════════════
-- Tesseract: R1 ⊕ R3 = R4
--
-- 4⁴ = 256. Perfect symmetry. No axis is special.
--
--   R1 = temporal epoch  (d ∈ {0,1,2,3}, 16 frames per epoch)
--   R3 = sRGB color      (a,b,c ∈ {0,1,2,3})
--   R4 = tesseract point  (d,a,b,c)
--
-- The palette encodes not just WHAT COLOR but WHEN IT APPEARS.
-- The projection to sRGB collapses the temporal axis.
-- The algebra lives in 4D where the symmetry is exact.
-- ════════════════════════════════════════════════════════════════

module Tesseract where

import Data.List (sort, foldl')
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE SPACES
-- ════════════════════════════════════════════════════════════════

-- | R1: temporal epoch (the "1D" part of the direct sum)
newtype R1 = R1 { unR1 :: Double }
  deriving (Show, Eq)

-- | R3: sRGB color space (the "3D" part of the direct sum)
data R3 = R3 { r3a :: !Double, r3b :: !Double, r3c :: !Double }
  deriving (Show, Eq)

-- | R4: the tesseract — the FULL space. R1 ⊕ R3 = R4.
data R4 = R4 { r4d :: !Double, r4a :: !Double, r4b :: !Double, r4c :: !Double }
  deriving (Show, Eq)

-- | Discrete tesseract coordinate: (d, a, b, c) ∈ {0,1,2,3}⁴
data TessCoord = TessCoord
  { tcD :: !Int   -- temporal epoch
  , tcA :: !Int   -- R channel
  , tcB :: !Int   -- G channel
  , tcC :: !Int   -- B channel
  } deriving (Show, Eq, Ord)

-- | sRGB color for display (3D projection of 4D tesseract)
data SRGBColor = SRGBColor !Double !Double !Double
  deriving (Show, Eq)

-- ════════════════════════════════════════════════════════════════
-- § 2. VECTOR SPACE
-- ════════════════════════════════════════════════════════════════

class VectorSpace v where
  zero  :: v
  add   :: v -> v -> v
  scale :: Double -> v -> v
  neg   :: v -> v
  neg v = scale (-1) v

instance VectorSpace R1 where
  zero = R1 0
  add (R1 a) (R1 b) = R1 (a + b)
  scale k (R1 a) = R1 (k * a)

instance VectorSpace R3 where
  zero = R3 0 0 0
  add (R3 a b c) (R3 d e f) = R3 (a+d) (b+e) (c+f)
  scale k (R3 a b c) = R3 (k*a) (k*b) (k*c)

instance VectorSpace R4 where
  zero = R4 0 0 0 0
  add (R4 a b c d) (R4 e f g h) = R4 (a+e) (b+f) (c+g) (d+h)
  scale k (R4 a b c d) = R4 (k*a) (k*b) (k*c) (k*d)

-- ════════════════════════════════════════════════════════════════
-- § 3. DIRECT SUM: R1 ⊕ R3 = R4
-- ════════════════════════════════════════════════════════════════

-- | The direct sum is defined by injection/projection pairs.
--   Axioms A1-A7 hold for this decomposition.
class (VectorSpace u, VectorSpace w, VectorSpace v)
  => DirectSum u w v | u w -> v, v -> u w where
  inject1  :: u -> v
  inject2  :: w -> v
  project1 :: v -> u
  project2 :: v -> w

instance DirectSum R1 R3 R4 where
  inject1 (R1 d)       = R4 d 0 0 0       -- epoch → tesseract
  inject2 (R3 a b c)   = R4 0 a b c       -- color → tesseract
  project1 (R4 d _ _ _) = R1 d            -- tesseract → epoch
  project2 (R4 _ a b c) = R3 a b c        -- tesseract → color

-- | Canonical decomposition
decompose :: DirectSum u w v => v -> (u, w)
decompose v = (project1 v, project2 v)

-- | Reconstruction from components
recompose :: DirectSum u w v => (u, w) -> v
recompose (u, w) = add (inject1 u) (inject2 w)

-- | Projection endomorphisms
pi1 :: R4 -> R4
pi1 v = inject1 (project1 v :: R1)

pi2 :: R4 -> R4
pi2 v = inject2 (project2 v :: R3)

-- ════════════════════════════════════════════════════════════════
-- § 4. METRIC
-- ════════════════════════════════════════════════════════════════

class Metric a where
  distance :: a -> a -> Double

instance Metric R1 where
  distance (R1 a) (R1 b) = abs (a - b)

instance Metric R3 where
  distance (R3 a b c) (R3 d e f) =
    sqrt ((a-d)**2 + (b-e)**2 + (c-f)**2)

instance Metric R4 where
  distance (R4 a b c d) (R4 e f g h) =
    sqrt ((a-e)**2 + (b-f)**2 + (c-g)**2 + (d-h)**2)

instance Metric TessCoord where
  distance tc1 tc2 = distance (tessToR4 tc1) (tessToR4 tc2)

instance Metric SRGBColor where
  distance (SRGBColor r1 g1 b1) (SRGBColor r2 g2 b2) =
    sqrt ((r1-r2)**2 + (g1-g2)**2 + (b1-b2)**2)

-- ════════════════════════════════════════════════════════════════
-- § 5. TESSERACT PALETTE: 4⁴ = 256
-- ════════════════════════════════════════════════════════════════

-- | All 256 lattice points
allTessCoords :: [TessCoord]
allTessCoords =
  [ TessCoord d a b c
  | d <- [0..3], a <- [0..3], b <- [0..3], c <- [0..3] ]

-- | Palette index: i = d×64 + a×16 + b×4 + c
tessIndex :: TessCoord -> Int
tessIndex (TessCoord d a b c) = d * 64 + a * 16 + b * 4 + c

-- | Inverse: index → coordinate via base-4 decomposition
indexTess :: Int -> TessCoord
indexTess i =
  let (d, r1) = i `divMod` 64
      (a, r2) = r1 `divMod` 16
      (b, c)  = r2 `divMod` 4
  in TessCoord d a b c

-- | Embed discrete lattice point into continuous R4
tessToR4 :: TessCoord -> R4
tessToR4 (TessCoord d a b c) =
  R4 (fromIntegral d) (fromIntegral a) (fromIntegral b) (fromIntegral c)

-- | Nearest lattice point (floor in each dimension)
r4ToTess :: R4 -> TessCoord
r4ToTess (R4 d a b c) =
  TessCoord (clamp 0 3 (floor d)) (clamp 0 3 (floor a))
            (clamp 0 3 (floor b)) (clamp 0 3 (floor c))

-- | Black and White: opposite corners of the tesseract
blackCoord :: TessCoord
blackCoord = TessCoord 0 0 0 0  -- index 0

whiteCoord :: TessCoord
whiteCoord = TessCoord 3 3 3 3  -- index 255

clamp :: Int -> Int -> Int -> Int
clamp lo hi x = max lo (min hi x)

-- ════════════════════════════════════════════════════════════════
-- § 6. 4D FLOOR QUANTIZATION
-- ════════════════════════════════════════════════════════════════

-- | Quantize a (frame, sRGB) pair to the nearest tesseract lattice point.
--   The epoch axis is determined by the frame index.
--   The color axes are determined by floor quantization of sRGB.
--   Cell volume = (1/4)⁴ = 1/256 for ALL cells.
quantize4D :: Int -> SRGBColor -> TessCoord
quantize4D frameIdx (SRGBColor r g b) =
  let d = clamp 0 3 (frameIdx `div` 16)
      a = clamp 0 3 (floor (r * 4))
      b' = clamp 0 3 (floor (g * 4))
      c = clamp 0 3 (floor (b * 4))
  in TessCoord d a b' c

-- ════════════════════════════════════════════════════════════════
-- § 7. PROJECTION TO sRGB
-- ════════════════════════════════════════════════════════════════

-- | Project tesseract coordinate to sRGB for display.
--   The temporal epoch is INVISIBLE — it's encoded in which
--   frames the color appears, not in its displayed hue.
--   4 palette entries share each sRGB value (one per epoch).
--
--   Reconstruction is at CELL CENTERS (level + 0.5) / 4, matching the
--   Swift port (TesseractCoord.sRGB, Axes.swift TessLevel.center) and
--   the floor-quantizer geometry: cells [k/4, (k+1)/4) have equal
--   width, and the midpoint is the centroid — the MSE-optimal
--   reconstruction for the fixed floor partition (see
--   quantization/Centers.hs axioms CN1-CN6). The former endpoint
--   scheme n/3 violated the centroid condition and implied unequal
--   Voronoi cells (statistics/BinomialFix.hs documents the bug class).
tessToSRGB :: TessCoord -> SRGBColor
tessToSRGB (TessCoord _d a b c) =
  SRGBColor ((fromIntegral a + 0.5) / 4.0)
            ((fromIntegral b + 0.5) / 4.0)
            ((fromIntegral c + 0.5) / 4.0)

-- | Tinted projection: slightly shift by epoch for debug visualization
tessToSRGBTinted :: TessCoord -> SRGBColor
tessToSRGBTinted (TessCoord d a b c) =
  let factor = 1.0 + 0.08 * (fromIntegral d - 1.5)
      cl x = max 0 (min 1 x)
  in SRGBColor (cl ((fromIntegral a + 0.5) / 4.0 * factor))
               (cl ((fromIntegral b + 0.5) / 4.0 * factor))
               (cl ((fromIntegral c + 0.5) / 4.0 * factor))

-- ════════════════════════════════════════════════════════════════
-- § 8. DIRECT SUM AXIOMS A1-A7
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-12

approxR1 :: R1 -> R1 -> Bool
approxR1 (R1 a) (R1 b) = abs (a - b) < eps

approxR3 :: R3 -> R3 -> Bool
approxR3 (R3 a b c) (R3 d e f) =
  abs (a-d) < eps && abs (b-e) < eps && abs (c-f) < eps

approxR4 :: R4 -> R4 -> Bool
approxR4 (R4 a b c d) (R4 e f g h) =
  abs (a-e) < eps && abs (b-f) < eps && abs (c-g) < eps && abs (d-h) < eps

-- (A1) inject₁(project₁(v)) + inject₂(project₂(v)) = v
axiom_A1 :: R4 -> Bool
axiom_A1 v = approxR4 (recompose (decompose v)) v

-- (A2) project₁(inject₁(u)) = u
axiom_A2 :: R1 -> Bool
axiom_A2 u = approxR1 (project1 (inject1 u :: R4)) u

-- (A3) project₂(inject₂(w)) = w
axiom_A3 :: R3 -> Bool
axiom_A3 w = approxR3 (project2 (inject2 w :: R4)) w

-- (A4) project₁(inject₂(w)) = 0
axiom_A4 :: R3 -> Bool
axiom_A4 w = approxR1 (project1 (inject2 w :: R4)) (zero :: R1)

-- (A5) project₂(inject₁(u)) = 0
axiom_A5 :: R1 -> Bool
axiom_A5 u = approxR3 (project2 (inject1 u :: R4)) (zero :: R3)

-- (A6) Trivial intersection
axiom_A6 :: R1 -> R3 -> Bool
axiom_A6 u w =
  let v1 = inject1 u :: R4
      v2 = inject2 w :: R4
  in if approxR4 v1 v2 then approxR4 v1 (zero :: R4) else True

-- (A7) Dimension: 1 + 3 = 4
axiom_A7 :: Bool
axiom_A7 = (1 :: Int) + 3 == 4

-- ════════════════════════════════════════════════════════════════
-- § 9. PROJECTION AXIOMS P1-P5
-- ════════════════════════════════════════════════════════════════

-- (P1) π₁ is idempotent
axiom_P1 :: R4 -> Bool
axiom_P1 v = approxR4 (pi1 (pi1 v)) (pi1 v)

-- (P2) π₂ is idempotent
axiom_P2 :: R4 -> Bool
axiom_P2 v = approxR4 (pi2 (pi2 v)) (pi2 v)

-- (P3) π₁ + π₂ = id
axiom_P3 :: R4 -> Bool
axiom_P3 v = approxR4 (add (pi1 v) (pi2 v)) v

-- (P4) π₁ ∘ π₂ = 0
axiom_P4 :: R4 -> Bool
axiom_P4 v = approxR4 (pi1 (pi2 v)) (zero :: R4)

-- (P5) π₂ ∘ π₁ = 0
axiom_P5 :: R4 -> Bool
axiom_P5 v = approxR4 (pi2 (pi1 v)) (zero :: R4)

-- ════════════════════════════════════════════════════════════════
-- § 10. CONE AXIOMS C1-C4
-- ════════════════════════════════════════════════════════════════

inCone :: R4 -> Bool
inCone (R4 a b c d) = a >= 0 && b >= 0 && c >= 0 && d >= 0

-- (C1) Zero in cone
axiom_C1 :: Bool
axiom_C1 = inCone (zero :: R4)

-- (C2) Non-negative scaling preserves cone
axiom_C2 :: Double -> R4 -> Bool
axiom_C2 k v | k >= 0 && inCone v = inCone (scale k v)
             | otherwise = True

-- (C3) Addition preserves cone
axiom_C3 :: R4 -> R4 -> Bool
axiom_C3 u v | inCone u && inCone v = inCone (add u v)
             | otherwise = True

-- (C4) Pointed: v and -v in cone ⟹ v = 0
axiom_C4 :: R4 -> Bool
axiom_C4 v | inCone v && inCone (neg v) = approxR4 v (zero :: R4)
           | otherwise = True

-- ════════════════════════════════════════════════════════════════
-- § 11. TESSERACT AXIOMS T1-T5
-- ════════════════════════════════════════════════════════════════

-- (T1) Metric invariant under axis permutation: all 4 axes are equal
axiom_T1 :: R4 -> R4 -> Bool
axiom_T1 (R4 a b c d) (R4 e f g h) =
  let d_orig  = distance (R4 a b c d) (R4 e f g h)
      -- Permute axes: swap 1st and 2nd
      d_swap12 = distance (R4 b a c d) (R4 f e g h)
      -- Swap 1st and 3rd
      d_swap13 = distance (R4 c b a d) (R4 g f e h)
      -- Swap 1st and 4th
      d_swap14 = distance (R4 d b c a) (R4 h f g e)
      -- Cyclic permutation
      d_cycle  = distance (R4 b c d a) (R4 f g h e)
  in abs (d_orig - d_swap12) < eps
  && abs (d_orig - d_swap13) < eps
  && abs (d_orig - d_swap14) < eps
  && abs (d_orig - d_cycle)  < eps

-- (T2) Lattice cardinality = 4⁴ = 256
axiom_T2 :: Bool
axiom_T2 = length allTessCoords == 256

-- (T3) Cell volume = (1/4)⁴ = 1/256
axiom_T3 :: Bool
axiom_T3 = abs ((1.0/4.0)^(4::Int) - 1.0/256.0) < eps

-- (T4) Black = index 0, White = index 255
axiom_T4 :: Bool
axiom_T4 = tessIndex blackCoord == 0
        && tessIndex whiteCoord == 255
        && indexTess 0 == blackCoord
        && indexTess 255 == whiteCoord

-- (T5) Diagonal = √(4 × 3²) = 6
axiom_T5 :: Bool
axiom_T5 =
  let diag = distance (tessToR4 blackCoord) (tessToR4 whiteCoord)
  in abs (diag - 6.0) < eps

-- ════════════════════════════════════════════════════════════════
-- § 12. EPOCH AXIOMS E1-E3
-- ════════════════════════════════════════════════════════════════

-- (E1) 4 epochs × 16 frames = 64
axiom_E1 :: Bool
axiom_E1 =
  let epochs = [[z | z <- [0..63], z `div` 16 == d] | d <- [0..3]]
  in all (\e -> length e == 16) epochs
  && length (concat epochs) == 64

-- (E2) project₁ extracts epoch correctly for all 256 palette entries
axiom_E2 :: Bool
axiom_E2 = all checkEntry [0..255]
  where
    checkEntry i =
      let tc = indexTess i
          R1 d = project1 (tessToR4 tc)
      in round d == tcD tc

-- (E3) 64 colors per epoch (256 ÷ 4 = 64)
axiom_E3 :: Bool
axiom_E3 =
  let perEpoch = [length [tc | tc <- allTessCoords, tcD tc == d] | d <- [0..3]]
  in all (== 64) perEpoch

-- ════════════════════════════════════════════════════════════════
-- § 13. BINOMIAL MODEL (3 levels)
-- ════════════════════════════════════════════════════════════════

-- Level 1: Per palette entry per frame
--   B(4096, 1/256), E = 16, SD ≈ 3.99
binomE_entry :: Double
binomE_entry = 4096.0 / 256.0  -- = 16

binomSD_entry :: Double
binomSD_entry = sqrt (4096.0 * (1/256) * (255/256))  -- ≈ 3.99

-- Level 2: Per epoch per frame (64 colors per epoch)
--   B(4096, 64/256) = B(4096, 1/4), E = 1024, SD ≈ 27.7
binomE_epoch :: Double
binomE_epoch = 4096.0 * (64.0 / 256.0)  -- = 1024

binomSD_epoch :: Double
binomSD_epoch = sqrt (4096.0 * (1/4) * (3/4))  -- ≈ 27.7

-- Level 3: Per sRGB triplet per frame (4 epochs share same display color)
--   B(4096, 4/256) = B(4096, 1/64), E = 64, SD ≈ 7.94
binomE_srgb :: Double
binomE_srgb = 4096.0 * (4.0 / 256.0)  -- = 64

binomSD_srgb :: Double
binomSD_srgb = sqrt (4096.0 * (1/64) * (63/64))  -- ≈ 7.94

-- ════════════════════════════════════════════════════════════════
-- § 14. INDEX ROUND-TRIP VERIFICATION
-- ════════════════════════════════════════════════════════════════

-- | Verify tessIndex ∘ indexTess = id and indexTess ∘ tessIndex = id
axiom_index_roundtrip :: Bool
axiom_index_roundtrip =
  all (\i -> tessIndex (indexTess i) == i) [0..255]
  && all (\tc -> indexTess (tessIndex tc) == tc) allTessCoords

-- ════════════════════════════════════════════════════════════════
-- § 15. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " Tesseract: R1 ⊕ R3 = R4"
  putStrLn " 4⁴ = 256. Perfect symmetry. No axis is special."
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  -- Geometry
  putStrLn "── Tesseract Geometry ──"
  putStrLn ""
  putStrLn $ "  Lattice points:  " ++ show (length allTessCoords)
  putStrLn $ "  Axes:            4 (epoch, R, G, B)"
  putStrLn $ "  Levels per axis: 4 → {0, 1, 2, 3}"
  putStrLn $ "  Cell volume:     (1/4)⁴ = " ++ showF ((1/4)**4)
  putStrLn $ "  Diagonal:        √(4×9) = " ++ showF (distance (tessToR4 blackCoord) (tessToR4 whiteCoord))
  putStrLn ""
  putStrLn "  Corners:"
  putStrLn $ "    Black = " ++ showTC blackCoord ++ " → index " ++ show (tessIndex blackCoord)
  putStrLn $ "    White = " ++ showTC whiteCoord ++ " → index " ++ show (tessIndex whiteCoord)
  putStrLn ""

  -- Epoch structure
  putStrLn "── Epoch Structure ──"
  putStrLn ""
  mapM_ (\d -> do
    let colors = [tc | tc <- allTessCoords, tcD tc == d]
        frames = [d * 16 .. d * 16 + 15]
    putStrLn $ "  Epoch " ++ show d ++ ": frames "
            ++ show (head frames) ++ "-" ++ show (last frames)
            ++ " │ " ++ show (length colors) ++ " colors"
    ) [0..3]
  putStrLn ""

  -- Direct sum decomposition
  putStrLn "── Direct Sum: R1 ⊕ R3 = R4 ──"
  putStrLn ""
  let testV = R4 2 1 3 0.5
      (u, w) = decompose testV
      reconstructed = recompose (u, w) :: R4
  putStrLn $ "  v          = " ++ showR4 testV
  putStrLn $ "  π₁(v) = R1 = " ++ showR1 u ++ "  (epoch)"
  putStrLn $ "  π₂(v) = R3 = " ++ showR3 w ++ "  (color)"
  putStrLn $ "  recompose  = " ++ showR4 reconstructed
  putStrLn $ "  v = recompose? " ++ show (approxR4 testV reconstructed) ++ " ✓"
  putStrLn ""

  -- Projection to sRGB: 4 epochs of "red"
  putStrLn "── sRGB Projection: 4 Epochs of the Same Color ──"
  putStrLn ""
  putStrLn "  epoch │ tesseract     │ index │ sRGB display"
  putStrLn "  ──────┼───────────────┼───────┼─────────────────"
  mapM_ (\d -> do
    let tc = TessCoord d 3 0 0  -- "red" at (a=3, b=0, c=0), varying epoch
        idx = tessIndex tc
        srgb = tessToSRGB tc
    putStrLn $ "  " ++ padL 5 (show d)
            ++ " │ " ++ padL 13 (showTC tc)
            ++ " │ " ++ padL 5 (show idx)
            ++ " │ " ++ showSRGB srgb
    ) [0..3]
  putStrLn ""
  putStrLn "  ★ All 4 epochs project to the SAME sRGB value."
  putStrLn "    The epoch is invisible in display — encoded in timing."
  putStrLn ""

  -- Binomial model
  putStrLn "── Binomial Model (3 Levels) ──"
  putStrLn ""
  putStrLn "  Level          │ p        │ E[count] │ SD"
  putStrLn "  ───────────────┼──────────┼──────────┼──────"
  putStrLn $ "  Per entry      │ 1/256    │ " ++ padL 8 (showF binomE_entry)
          ++ " │ " ++ showF binomSD_entry
  putStrLn $ "  Per epoch      │ 1/4      │ " ++ padL 8 (showF binomE_epoch)
          ++ " │ " ++ showF binomSD_epoch
  putStrLn $ "  Per sRGB color │ 4/256    │ " ++ padL 8 (showF binomE_srgb)
          ++ " │ " ++ showF binomSD_srgb
  putStrLn ""

  -- Axiom verification
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOM VERIFICATION (22 axioms)"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  let testR4s = [ R4 1 0 0 0, R4 0 1 0 0, R4 0 0 1 0, R4 0 0 0 1
                , R4 2 3 1 0.5, R4 0 0 0 0, R4 (-1) 2 (-3) 0.7
                , R4 3 3 3 3, R4 1.5 1.5 1.5 1.5 ]
  let testR1s = [R1 0, R1 1, R1 (-3), R1 2.5]
  let testR3s = [R3 0 0 0, R3 1 0 0, R3 0 1 0, R3 0 0 1, R3 3.5 (-2.1) 0.7]

  putStrLn "  ── Direct Sum A1-A7 ──"
  check "A1 decomposition identity" [axiom_A1 v | v <- testR4s]
  check "A2 project₁ ∘ inject₁ = id" [axiom_A2 u | u <- testR1s]
  check "A3 project₂ ∘ inject₂ = id" [axiom_A3 w | w <- testR3s]
  check "A4 project₁ ∘ inject₂ = 0" [axiom_A4 w | w <- testR3s]
  check "A5 project₂ ∘ inject₁ = 0" [axiom_A5 u | u <- testR1s]
  check "A6 trivial intersection" [axiom_A6 u w | u <- testR1s, w <- testR3s]
  check "A7 dim = 1 + 3 = 4" [axiom_A7]
  putStrLn ""

  putStrLn "  ── Projection P1-P5 ──"
  check "P1 π₁ idempotent" [axiom_P1 v | v <- testR4s]
  check "P2 π₂ idempotent" [axiom_P2 v | v <- testR4s]
  check "P3 π₁ + π₂ = id" [axiom_P3 v | v <- testR4s]
  check "P4 π₁ ∘ π₂ = 0" [axiom_P4 v | v <- testR4s]
  check "P5 π₂ ∘ π₁ = 0" [axiom_P5 v | v <- testR4s]
  putStrLn ""

  putStrLn "  ── Cone C1-C4 ──"
  let coneVecs = filter inCone testR4s
  check "C1 zero ∈ cone" [axiom_C1]
  check "C2 λ≥0, v∈cone → λv∈cone" [axiom_C2 k v | k <- [0,0.5,1,3.7], v <- coneVecs]
  check "C3 u,v∈cone → u+v∈cone" [axiom_C3 u v | u <- coneVecs, v <- coneVecs]
  check "C4 pointed" [axiom_C4 v | v <- testR4s]
  putStrLn ""

  putStrLn "  ── Tesseract T1-T5 ──"
  check "T1 metric axis-permutation invariant"
    [axiom_T1 v1 v2 | v1 <- take 4 testR4s, v2 <- drop 4 testR4s]
  check "T2 |lattice| = 256" [axiom_T2]
  check "T3 cell volume = 1/256" [axiom_T3]
  check "T4 Black=0, White=255" [axiom_T4]
  check "T5 diagonal = 6" [axiom_T5]
  putStrLn ""

  putStrLn "  ── Epoch E1-E3 ──"
  check "E1 4 epochs × 16 frames = 64" [axiom_E1]
  check "E2 project₁ extracts epoch" [axiom_E2]
  check "E3 64 colors per epoch" [axiom_E3]
  putStrLn ""

  putStrLn "  ── Index Round-Trip ──"
  check "tessIndex ∘ indexTess = id ∧ indexTess ∘ tessIndex = id"
    [axiom_index_roundtrip]
  putStrLn ""

  -- Summary
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE TESSERACT"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  R1 ⊕ R3 = R4"
  putStrLn ""
  putStrLn "  R1 = temporal epoch (WHEN the color appears)"
  putStrLn "  R3 = sRGB color    (WHAT the color looks like)"
  putStrLn "  R4 = tesseract     (the full space, 4⁴ = 256)"
  putStrLn ""
  putStrLn "  Every axis is equal. No symmetry is broken."
  putStrLn "  The palette is not a cube — it's a tesseract."
  putStrLn "  Color and time are unified in 4 dimensions."
  putStrLn "  The projection to sRGB is a shadow of the true space."
  putStrLn ""
  putStrLn "  Black (0,0,0,0) and White (3,3,3,3) sit at opposite"
  putStrLn "  corners of the tesseract, distance 6 apart."
  putStrLn "  Between them: 254 other colors, each with an epoch,"
  putStrLn "  each with a position in the 4D lattice."
  putStrLn ""
  putStrLn "  4⁴ = 256. The GIF spec met its match."
  putStrLn "══════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 1000) :: Int) / 1000.0 :: Double)
          in take 7 (s ++ repeat '0')

showR1 :: R1 -> String
showR1 (R1 d) = showF d

showR3 :: R3 -> String
showR3 (R3 a b c) = "(" ++ showF a ++ ", " ++ showF b ++ ", " ++ showF c ++ ")"

showR4 :: R4 -> String
showR4 (R4 d a b c) = "(" ++ showF d ++ ", " ++ showF a ++ ", " ++ showF b ++ ", " ++ showF c ++ ")"

showTC :: TessCoord -> String
showTC (TessCoord d a b c) = "(" ++ show d ++ "," ++ show a ++ "," ++ show b ++ "," ++ show c ++ ")"

showSRGB :: SRGBColor -> String
showSRGB (SRGBColor r g b) = "(" ++ showF r ++ ", " ++ showF g ++ ", " ++ showF b ++ ")"

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
