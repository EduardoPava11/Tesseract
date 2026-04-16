{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- Residual: Teacher + δ, Confidence-Gated, Cube Interaction
--
-- The NN is a RESIDUAL on top of the teacher (proven algorithms).
-- δ = tanh(NN_direction) × (1 - confidence) × max_delta
--
-- Three interaction mechanisms (form follows function):
--
--   1. ROTATE: the GIF is a 64³ cube. Rotating it rotates the
--      δ correction in the corresponding aesthetic subspace.
--      X-axis = spatial structure. Y-axis = temporal/spatial trade.
--      Z-axis = chromatic balance.
--
--   2. SWIPE: discretized rotation.
--      LEFT = explore (Sobol). RIGHT = retreat.
--      UP = more temporal. DOWN = more stable.
--
--   3. INTERPOLATE: two genes → lerp weights → merged GIF.
--      The user navigates a 1D line between two known-good points.
--
-- Phase diagram (materials science analogy):
--   High confidence + high depth = STABLE (face, δ ≈ 0)
--   Low confidence + low depth = EXPLORE (background, δ large)
--   Medium = BOUNDARY (edges, dithering, many solutions)
--
-- GIFs are memories. The gene IS how you see.
-- ════════════════════════════════════════════════════════════════

module Residual where

import Data.List (foldl')

-- ════════════════════════════════════════════════════════════════
-- § 1. THE RESIDUAL CORRECTION
-- ════════════════════════════════════════════════════════════════

-- | δ correction per pixel: direction × magnitude
data Delta = Delta
  { deltaD :: !Double    -- epoch correction
  , deltaA :: !Double    -- R level correction
  , deltaB :: !Double    -- G level correction
  , deltaC :: !Double    -- B level correction
  , deltaG :: !Double    -- global weight correction
  } deriving (Show, Eq)

zeroDelta :: Delta
zeroDelta = Delta 0 0 0 0 0

-- | Maximum correction per axis
data MaxDelta = MaxDelta
  { mdEpoch  :: !Double   -- 0.5
  , mdColor  :: !Double   -- 0.5
  , mdGlobal :: !Double   -- 0.3
  } deriving (Show, Eq)

defaultMaxDelta :: MaxDelta
defaultMaxDelta = MaxDelta 0.5 0.5 0.3

-- ════════════════════════════════════════════════════════════════
-- § 2. CONFIDENCE GATE — statistics constrain the correction
--
-- direction = tanh(NN_output)        ∈ [-1, 1]
-- magnitude = (1 - confidence) × δ_max
-- δ = direction × magnitude
--
-- High confidence → magnitude ≈ 0 → teacher wins.
-- Low confidence → magnitude ≈ δ_max → NN explores.
-- The STATISTICS are the gate, not the NN.
-- ════════════════════════════════════════════════════════════════

data ConfidenceGate = ConfidenceGate
  { cgR     :: !Double   -- R channel confidence ∈ [0.25, 1.0]
  , cgG     :: !Double   -- G channel confidence
  , cgB     :: !Double   -- B channel confidence
  , cgEpoch :: !Double   -- epoch concentration
  , cgGlobal :: !Double  -- depth-derived global weight
  } deriving (Show, Eq)

-- | Compute the gated δ from direction and confidence
gateDelta :: [Double] -> ConfidenceGate -> MaxDelta -> Delta
gateDelta rawDir gate maxD =
  let -- Direction: tanh ∈ [-1, 1]
      dir = map tanh rawDir
      -- Magnitude per axis: (1 - confidence) × max_delta
      magD = (1 - cgEpoch gate)  * mdEpoch maxD
      magA = (1 - cgR gate)      * mdColor maxD
      magB = (1 - cgG gate)      * mdColor maxD
      magC = (1 - cgB gate)      * mdColor maxD
      magG = (1 - cgGlobal gate) * mdGlobal maxD
  in Delta
    { deltaD = (dir !! 0) * magD
    , deltaA = (dir !! 1) * magA
    , deltaB = (dir !! 2) * magB
    , deltaC = (dir !! 3) * magC
    , deltaG = (dir !! 4) * magG
    }

-- ════════════════════════════════════════════════════════════════
-- § 3. APPLY RESIDUAL: teacher + δ → final
-- ════════════════════════════════════════════════════════════════

-- | Teacher output (baseline)
data TeacherOutput = TeacherOutput
  { toD :: !Int, toA :: !Int, toB :: !Int, toC :: !Int
  , toG :: !Double
  } deriving (Show, Eq)

-- | Final output after residual correction
data FinalOutput = FinalOutput
  { foD :: !Int, foA :: !Int, foB :: !Int, foC :: !Int
  , foG :: !Double
  } deriving (Show, Eq)

clamp03 :: Int -> Int
clamp03 = max 0 . min 3

clamp01 :: Double -> Double
clamp01 = max 0 . min 1

applyResidual :: TeacherOutput -> Delta -> FinalOutput
applyResidual t d = FinalOutput
  { foD = clamp03 $ round (fromIntegral (toD t) + deltaD d)
  , foA = clamp03 $ round (fromIntegral (toA t) + deltaA d)
  , foB = clamp03 $ round (fromIntegral (toB t) + deltaB d)
  , foC = clamp03 $ round (fromIntegral (toC t) + deltaC d)
  , foG = clamp01 (toG t + deltaG d)
  }

paletteIndex :: FinalOutput -> Int
paletteIndex fo = foD fo * 64 + foA fo * 16 + foB fo * 4 + foC fo

-- ════════════════════════════════════════════════════════════════
-- § 4. PHASE IDENTIFICATION
-- ════════════════════════════════════════════════════════════════

data Phase = PhaseStable    -- high conf, high depth → δ ≈ 0
           | PhaseBoundary  -- medium → dithering territory
           | PhaseExplore   -- low conf, low depth → δ large
           deriving (Show, Eq, Ord)

identifyPhase :: ConfidenceGate -> Double -> Phase
identifyPhase gate depth
  | meanConf > 0.7 && depth > 0.6 = PhaseStable
  | meanConf < 0.4 && depth < 0.4 = PhaseExplore
  | otherwise                       = PhaseBoundary
  where meanConf = (cgR gate + cgG gate + cgB gate) / 3

-- ════════════════════════════════════════════════════════════════
-- § 5. INTERACTION — three mechanisms from the cube geometry
-- ════════════════════════════════════════════════════════════════

data Direction = DirLeft | DirRight | DirUp | DirDown
  deriving (Show, Eq)

data Interaction
  = Rotate Double Double Double     -- (rx, ry, rz) rotation angles
  | Swipe Direction                 -- LEFT/RIGHT/UP/DOWN
  | Interpolate Double [Double] [Double]  -- α, weightsA, weightsB
  deriving (Show)

-- | Interpolate two weight vectors: α × A + (1-α) × B
lerpWeights :: Double -> [Double] -> [Double] -> [Double]
lerpWeights alpha wa wb =
  zipWith (\a b -> alpha * a + (1 - alpha) * b) wa wb

-- | Rotate a 5D direction vector around the cube axes
--   rx: rotate between δA and δB (spatial structure)
--   ry: rotate between δD and (δA+δB+δC)/3 (temporal ↔ spatial)
--   rz: rotate between color channels (chromatic balance)
rotateDirection :: Double -> Double -> Double -> [Double] -> [Double]
rotateDirection rx ry rz [d, a, b, c, g] =
  let -- X-axis: rotate (a, b) subspace
      cosX = cos rx; sinX = sin rx
      a' = cosX * a - sinX * b
      b' = sinX * a + cosX * b
      -- Y-axis: rotate (d, mean_color) subspace
      meanC = (a' + b' + c) / 3
      cosY = cos ry; sinY = sin ry
      d' = cosY * d - sinY * meanC
      scaleC = if abs meanC > 1e-10 then (sinY * d + cosY * meanC) / meanC else 1
      a'' = a' * scaleC; b'' = b' * scaleC; c' = c * scaleC
      -- Z-axis: rotate (r, g, b) → cyclic permutation blend
      cosZ = cos rz; sinZ = sin rz
      aFinal = cosZ * a'' - sinZ * c'
      cFinal = sinZ * a'' + cosZ * c'
  in [d', aFinal, b'', cFinal, g]
rotateDirection _ _ _ dir = dir  -- passthrough for wrong length

-- ════════════════════════════════════════════════════════════════
-- § 6. ENERGY LANDSCAPE
-- ════════════════════════════════════════════════════════════════

data Energy = Energy
  { enRecon    :: !Double  -- distance from teacher
  , enBeauty   :: !Double  -- 1/M (lower = more beautiful)
  , enSmooth   :: !Double  -- spatial coherence
  , enTotal    :: !Double
  } deriving (Show)

computeEnergy :: Double -> Double -> Double -> TeacherOutput -> FinalOutput -> Energy
computeEnergy alpha beta gamma teacher final =
  let recon = fromIntegral $
        (if toD teacher /= foD final then 1 else 0) +
        (if toA teacher /= foA final then 1 else 0) +
        (if toB teacher /= foB final then 1 else 0) +
        (if toC teacher /= foC final then 1 else 0 :: Int)
      beauty = 0  -- placeholder: computed from full frame
      smooth = 0  -- placeholder: computed from neighbors
  in Energy recon beauty smooth (alpha * recon + beta * beauty + gamma * smooth)

-- ════════════════════════════════════════════════════════════════
-- § 7. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (R1) δ = 0 when confidence = 1.0
axiom_R1 :: Bool
axiom_R1 =
  let gate = ConfidenceGate 1.0 1.0 1.0 1.0 1.0
      delta = gateDelta [10, -5, 3, -7, 2] gate defaultMaxDelta
  in deltaD delta == 0 && deltaA delta == 0 && deltaB delta == 0
  && deltaC delta == 0 && deltaG delta == 0

-- (R2) |δ| ≤ (1-confidence) × max_delta
axiom_R2 :: Bool
axiom_R2 =
  let gate = ConfidenceGate 0.5 0.5 0.5 0.5 0.5
      delta = gateDelta [100, 100, 100, 100, 100] gate defaultMaxDelta
  in abs (deltaA delta) <= (1 - 0.5) * mdColor defaultMaxDelta + 1e-10
  && abs (deltaD delta) <= (1 - 0.5) * mdEpoch defaultMaxDelta + 1e-10

-- (R3) tanh(direction) ∈ [-1, 1]
axiom_R3 :: Bool
axiom_R3 = all (\x -> tanh x >= -1 && tanh x <= 1) [-100, -1, 0, 1, 100]

-- (R4) final ∈ {0,1,2,3}⁴
axiom_R4 :: Bool
axiom_R4 =
  let t = TeacherOutput 2 1 3 0 0.5
      d = Delta 0.8 (-0.8) 0.3 1.5 (-0.2)  -- large deltas
      f = applyResidual t d
  in foD f >= 0 && foD f <= 3
  && foA f >= 0 && foA f <= 3
  && foB f >= 0 && foB f <= 3
  && foC f >= 0 && foC f <= 3
  && foG f >= 0 && foG f <= 1

-- (R5) Rotate(0,0,0) = identity
axiom_R5 :: Bool
axiom_R5 =
  let dir = [0.5, -0.3, 0.7, -0.1, 0.2]
      rotated = rotateDirection 0 0 0 dir
  in all (\(a,b) -> abs (a-b) < 1e-10) (zip dir rotated)

-- (R6) Interpolate(0,A,B) = A, Interpolate(1,A,B) = B
axiom_R6 :: Bool
axiom_R6 =
  let wa = [1, 2, 3, 4, 5 :: Double]
      wb = [10, 20, 30, 40, 50]
      la = lerpWeights 1.0 wa wb  -- α=1 → A
      lb = lerpWeights 0.0 wa wb  -- α=0 → B
  in la == wa && lb == wb

-- (R7) Interpolate(0.5,A,A) = A
axiom_R7 :: Bool
axiom_R7 =
  let wa = [1, 2, 3, 4, 5 :: Double]
      mid = lerpWeights 0.5 wa wa
  in all (\(a,b) -> abs (a-b) < 1e-10) (zip wa mid)

-- (R8) PhaseStable → δ magnitude small
axiom_R8 :: Bool
axiom_R8 =
  let gate = ConfidenceGate 0.9 0.9 0.9 0.9 0.9  -- high confidence
      delta = gateDelta [1, 1, 1, 1, 1] gate defaultMaxDelta
  in abs (deltaA delta) < 0.1 && abs (deltaD delta) < 0.1

-- (R9) PhaseExplore → δ magnitude large (relative to max)
axiom_R9 :: Bool
axiom_R9 =
  let gate = ConfidenceGate 0.25 0.25 0.25 0.25 0.25  -- min confidence
      delta = gateDelta [1, 1, 1, 1, 1] gate defaultMaxDelta
  in abs (deltaA delta) > 0.2

-- (R10) Phase identification deterministic
axiom_R10 :: Bool
axiom_R10 =
  let gate = ConfidenceGate 0.9 0.9 0.9 0.9 0.9
  in identifyPhase gate 0.8 == PhaseStable
  && identifyPhase gate 0.8 == PhaseStable  -- same input → same output

-- (R11) Energy(teacher + 0) = 0 reconstruction (local minimum)
axiom_R11 :: Bool
axiom_R11 =
  let t = TeacherOutput 1 2 3 0 0.7
      f = applyResidual t zeroDelta  -- no correction
  in enRecon (computeEnergy 1 0 0 t f) == 0

-- (R12) Palette index valid after residual
axiom_R12 :: Bool
axiom_R12 =
  let tests = [ (TeacherOutput d a b c g, Delta dd da db dc dg)
              | d <- [0,3], a <- [0,3], b <- [0,3], c <- [0,3]
              , g <- [0, 1]
              , dd <- [-1, 0, 1], da <- [-1, 0, 1]
              , db <- [-1, 0, 1], dc <- [-1, 0, 1]
              , dg <- [-0.5, 0, 0.5]
              ]
      allValid = all (\(t, d) ->
        let f = applyResidual t d
            i = paletteIndex f
        in i >= 0 && i <= 255
        ) tests
  in allValid

-- ════════════════════════════════════════════════════════════════
-- § 8. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Residual: teacher + δ, confidence-gated, cube interaction"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Phase diagram
  putStrLn "── Phase Diagram ──"
  putStrLn ""
  putStrLn "           confidence →"
  putStrLn "      low        medium       high"
  putStrLn "  ┌──────────┬──────────┬──────────┐"
  putStrLn "  │ EXPLORE  │ BOUNDARY │  STABLE  │  high depth"
  putStrLn "  │ δ large  │ δ medium │  δ ≈ 0   │  (face)"
  putStrLn "  ├──────────┼──────────┼──────────┤"
  putStrLn "  │ EXPLORE  │ BOUNDARY │ BOUNDARY │  med depth"
  putStrLn "  ├──────────┼──────────┼──────────┤"
  putStrLn "  │ EXPLORE  │ EXPLORE  │ BOUNDARY │  low depth"
  putStrLn "  │ maximum  │ high     │ moderate │  (background)"
  putStrLn "  └──────────┴──────────┴──────────┘"
  putStrLn ""

  -- Demonstrate gating
  putStrLn "── Confidence Gating ──"
  putStrLn ""
  let rawDir = [1, 1, 1, 1, 1]  -- NN wants to push all axes
  mapM_ (\(name, conf) -> do
    let gate = ConfidenceGate conf conf conf conf conf
        delta = gateDelta rawDir gate defaultMaxDelta
    putStrLn $ "  " ++ padL 12 name
            ++ ": conf=" ++ showF conf
            ++ " |δA|=" ++ showF (abs (deltaA delta))
            ++ " |δD|=" ++ showF (abs (deltaD delta))
            ++ " phase=" ++ show (identifyPhase gate conf)
    ) [ ("Face (high)", 0.9)
      , ("Edge (med)",  0.5)
      , ("BG (low)",    0.25)
      ]
  putStrLn ""

  -- Demonstrate residual
  putStrLn "── Residual Application ──"
  putStrLn ""
  let t = TeacherOutput 1 2 1 3 0.7
  putStrLn $ "  Teacher: d=" ++ show (toD t) ++ " a=" ++ show (toA t)
          ++ " b=" ++ show (toB t) ++ " c=" ++ show (toC t)
          ++ " g=" ++ showF (toG t)
  mapM_ (\(name, d) -> do
    let f = applyResidual t d
    putStrLn $ "  + " ++ padL 8 name
            ++ ": d=" ++ show (foD f) ++ " a=" ++ show (foA f)
            ++ " b=" ++ show (foB f) ++ " c=" ++ show (foC f)
            ++ " g=" ++ showF (foG f)
            ++ " idx=" ++ show (paletteIndex f)
    ) [ ("zero δ",  zeroDelta)
      , ("small δ", Delta 0.1 (-0.1) 0.2 0 0.05)
      , ("large δ", Delta 0.8 (-0.8) 0.5 1.2 (-0.3))
      ]
  putStrLn ""

  -- Demonstrate interpolation
  putStrLn "── Gene Interpolation ──"
  let wa = [1, 0, 0, 0, 0 :: Double]
      wb = [0, 0, 0, 0, 1]
  putStrLn $ "  A = " ++ show wa
  putStrLn $ "  B = " ++ show wb
  mapM_ (\alpha ->
    putStrLn $ "  α=" ++ showF alpha ++ " → " ++ show (lerpWeights alpha wa wb)
    ) [0, 0.25, 0.5, 0.75, 1.0]
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "R1  conf=1 → δ=0 (teacher preserved)"       [axiom_R1]
  check "R2  |δ| ≤ (1-conf) × max_delta"              [axiom_R2]
  check "R3  tanh ∈ [-1, 1]"                           [axiom_R3]
  check "R4  final ∈ {0..3}⁴ × [0,1]"                [axiom_R4]
  check "R5  Rotate(0,0,0) = identity"                 [axiom_R5]
  check "R6  Lerp endpoints: α=1→A, α=0→B"            [axiom_R6]
  check "R7  Lerp(0.5, A, A) = A"                      [axiom_R7]
  check "R8  PhaseStable → |δ| < 0.1"                 [axiom_R8]
  check "R9  PhaseExplore → |δ| > 0.2"                [axiom_R9]
  check "R10 Phase identification deterministic"        [axiom_R10]
  check "R11 Energy(teacher+0) = 0 recon"              [axiom_R11]
  check "R12 Palette valid after any residual"          [axiom_R12]
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn "  The GIF is a cube. Rotate it to navigate aesthetic space."
  putStrLn "  The NN proposes δ. Statistics constrain HOW FAR."
  putStrLn "  Face (stable phase): δ ≈ 0. Teacher wins."
  putStrLn "  Background (explore phase): δ large. NN discovers."
  putStrLn "  Interpolate two genes: navigate the line between them."
  putStrLn "  GIFs are memories. The gene IS how you see."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 1000) :: Int) / 1000.0 :: Double)
          in take 6 (s ++ repeat '0')

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
