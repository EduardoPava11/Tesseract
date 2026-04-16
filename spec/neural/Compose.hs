{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- Compose: Non-Commutative Gene Composition
--
-- Two genes A and B are two POINTS in the NN's dimensional space.
-- Composing them creates a new gene on the LINE between them.
--
-- A+B: base=A, residual=B-A → composite = A + α×(B-A)
-- B+A: base=B, residual=A-B → composite = B + α×(A-B)
-- A+B ≠ B+A because the BASE determines which CORE survives.
--
-- Three phases:
--   Phase 1: DUAL EXPLORE (UP/DOWN/LEFT/RIGHT steer both)
--   Phase 2: COMPOSE (TAP+HOLD drag A→B or B→A, irreversible)
--   Phase 3: REFINE (CW/CCW adjust α, TAP to export)
-- ════════════════════════════════════════════════════════════════

module Compose where

-- ════════════════════════════════════════════════════════════════
-- § 1. GENE WEIGHTS (simplified for spec)
-- ════════════════════════════════════════════════════════════════

-- | Gene = flat weight vector. ATTENTION is first N, CORE is last M.
type Weights = [Double]

attentionCount :: Int
attentionCount = 4416

totalCount :: Int
totalCount = 4581

-- ════════════════════════════════════════════════════════════════
-- § 2. COMPOSITION — base + α × residual
-- ════════════════════════════════════════════════════════════════

data CompositionOrder = AintoB | BintoA
  deriving (Show, Eq)

-- | Compose two genes. Non-commutative.
--   base + α × (other - base)
--   ATTENTION: interpolated
--   CORE: kept from base (species identity)
compose :: Weights -> Weights -> Double -> Weights
compose base other alpha =
  let n = length base
  in [ if i < attentionCount
       then base !! i + alpha * (other !! i - base !! i)  -- ATTENTION: lerp
       else base !! i                                       -- CORE: from base
     | i <- [0..n-1]
     ]

-- | A+B: A is base, B is other
composeAB :: Weights -> Weights -> Double -> Weights
composeAB a b = compose a b

-- | B+A: B is base, A is other
composeBA :: Weights -> Weights -> Double -> Weights
composeBA a b = compose b a

-- ════════════════════════════════════════════════════════════════
-- § 3. PHASE TRANSITIONS (state machine)
-- ════════════════════════════════════════════════════════════════

data Phase
  = DualExplore Int            -- generation counter
  | Composing CompositionOrder -- A+B or B+A (instant, flash)
  | Refining Double            -- α ∈ [0, 1]
  | Done
  deriving (Show, Eq)

-- | Phase transitions
transition :: Phase -> PhaseEvent -> Phase
transition (DualExplore n) (Swipe _)        = DualExplore (n + 1)
transition (DualExplore _) (DragCompose order) = Composing order
transition (Composing order) StartRefine    = Refining 0.5
transition (Refining alpha) (RotateCW da)   = Refining (min 1 (alpha + da))
transition (Refining alpha) (RotateCCW da)  = Refining (max 0 (alpha - da))
transition (Refining _) TapExport           = Done
transition phase _ = phase  -- invalid transitions = no-op

data PhaseEvent
  = Swipe Direction
  | DragCompose CompositionOrder
  | StartRefine
  | RotateCW Double    -- clockwise: increase α
  | RotateCCW Double   -- counter-clockwise: decrease α
  | TapExport
  deriving (Show, Eq)

data Direction = DirUp | DirDown | DirLeft | DirRight
  deriving (Show, Eq)

-- | Is the transition irreversible?
isIrreversible :: PhaseEvent -> Bool
isIrreversible (DragCompose _) = True
isIrreversible _ = False

-- ════════════════════════════════════════════════════════════════
-- § 4. α REFINEMENT — CW/CCW controls the collapse
--
-- α = 0: pure base gene (A for A+B, B for B+A)
-- α = 0.5: equal blend (initial after composition)
-- α = 1: pure other gene (B for A+B, A for B+A)
--
-- CW: tighter collapse → α increases → more of the other
-- CCW: looser collapse → α decreases → back toward base
-- ════════════════════════════════════════════════════════════════

-- | Adjust α by a rotation gesture
adjustAlpha :: Double -> Double -> Double
adjustAlpha alpha delta = max 0 (min 1 (alpha + delta))

-- ════════════════════════════════════════════════════════════════
-- § 5. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- Synthetic genes for testing
geneA :: Weights
geneA = replicate totalCount 1.0

geneB :: Weights
geneB = [fromIntegral i * 0.01 | i <- [0..totalCount-1]]

-- (CP1) compose(base, other, 0) = base
axiom_CP1 :: Bool
axiom_CP1 =
  let c = compose geneA geneB 0.0
  in c == geneA

-- (CP2) compose(base, other, 1) for ATTENTION = other, for CORE = base
axiom_CP2 :: Bool
axiom_CP2 =
  let c = compose geneA geneB 1.0
      -- ATTENTION slots should equal geneB
      attnMatch = all (\i -> abs (c !! i - geneB !! i) < 1e-10) [0..attentionCount-1]
      -- CORE slots should equal geneA (base)
      coreMatch = all (\i -> abs (c !! i - geneA !! i) < 1e-10) [attentionCount..totalCount-1]
  in attnMatch && coreMatch

-- (CP3) A+B ≠ B+A (non-commutative)
axiom_CP3 :: Bool
axiom_CP3 =
  let ab = composeAB geneA geneB 0.5
      ba = composeBA geneA geneB 0.5
  in ab /= ba

-- (CP4) compose(A, A, α) = A for all α (self-composition = identity)
axiom_CP4 :: Bool
axiom_CP4 =
  all (\alpha ->
    let c = compose geneA geneA alpha
    in all (\i -> abs (c !! i - geneA !! i) < 1e-10) [0..totalCount-1]
  ) [0, 0.25, 0.5, 0.75, 1.0]

-- (CP5) α ∈ [0, 1] bounded by adjustAlpha
axiom_CP5 :: Bool
axiom_CP5 =
  adjustAlpha 0.5 0.3 == 0.8
  && adjustAlpha 0.5 (-0.3) == 0.2
  && adjustAlpha 0.9 0.5 == 1.0    -- clamped at 1
  && adjustAlpha 0.1 (-0.5) == 0.0  -- clamped at 0

-- (CP6) CW increases α, CCW decreases
axiom_CP6 :: Bool
axiom_CP6 =
  let p0 = Refining 0.5
      p1 = transition p0 (RotateCW 0.1)
      p2 = transition p0 (RotateCCW 0.1)
  in p1 == Refining 0.6 && p2 == Refining 0.4

-- (CP7) CORE preserved from base
axiom_CP7 :: Bool
axiom_CP7 =
  let c = compose geneA geneB 0.7
  in all (\i -> c !! i == geneA !! i) [attentionCount..totalCount-1]

-- (CP8) DragCompose is irreversible
axiom_CP8 :: Bool
axiom_CP8 =
  isIrreversible (DragCompose AintoB)
  && isIrreversible (DragCompose BintoA)
  && not (isIrreversible (Swipe DirUp))
  && not (isIrreversible TapExport)

-- ════════════════════════════════════════════════════════════════
-- § 6. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Compose: Non-Commutative Gene Composition"
  putStrLn " A+B ≠ B+A. Base + α × residual. CW/CCW adjust α."
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Demonstrate non-commutativity
  putStrLn "── Non-Commutativity ──"
  let ab = composeAB geneA geneB 0.5
      ba = composeBA geneA geneB 0.5
  putStrLn $ "  A+B[0..4]:  " ++ show (take 5 ab)
  putStrLn $ "  B+A[0..4]:  " ++ show (take 5 ba)
  putStrLn $ "  Equal? " ++ show (ab == ba)
  putStrLn ""

  -- Demonstrate α range
  putStrLn "── α Refinement ──"
  putStrLn "  α=0.0: pure base"
  putStrLn "  α=0.5: equal blend (initial)"
  putStrLn "  α=1.0: ATTENTION from other, CORE from base"
  putStrLn ""
  mapM_ (\alpha -> do
    let c = compose geneA geneB alpha
    putStrLn $ "  α=" ++ showF alpha
            ++ "  ATTN[0]=" ++ showF (c !! 0)
            ++ "  CORE[-1]=" ++ showF (c !! (totalCount - 1))
    ) [0, 0.25, 0.5, 0.75, 1.0]
  putStrLn ""

  -- State machine
  putStrLn "── State Machine ──"
  let s0 = DualExplore 0
      s1 = transition s0 (Swipe DirUp)
      s2 = transition s1 (Swipe DirLeft)
      s3 = transition s2 (DragCompose AintoB)
      s4 = transition s3 StartRefine
      s5 = transition s4 (RotateCW 0.1)
      s6 = transition s5 (RotateCCW 0.05)
      s7 = transition s6 TapExport
  putStrLn $ "  " ++ show s0
  putStrLn $ "  → swipe up  → " ++ show s1
  putStrLn $ "  → swipe left → " ++ show s2
  putStrLn $ "  → drag A→B  → " ++ show s3 ++ "  (IRREVERSIBLE)"
  putStrLn $ "  → start     → " ++ show s4
  putStrLn $ "  → CW 0.1    → " ++ show s5
  putStrLn $ "  → CCW 0.05  → " ++ show s6
  putStrLn $ "  → tap export → " ++ show s7
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "CP1 compose(base, other, 0) = base"        [axiom_CP1]
  check "CP2 compose(base, other, 1) = other/base"  [axiom_CP2]
  check "CP3 A+B ≠ B+A (non-commutative)"           [axiom_CP3]
  check "CP4 compose(A, A, α) = A (identity)"        [axiom_CP4]
  check "CP5 α ∈ [0, 1] (bounded)"                  [axiom_CP5]
  check "CP6 CW→α+, CCW→α-"                          [axiom_CP6]
  check "CP7 CORE from base"                          [axiom_CP7]
  check "CP8 DragCompose is irreversible"             [axiom_CP8]
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn "  Phase 1: DUAL EXPLORE (↑↓←→ steer both GIFs)"
  putStrLn "  Phase 2: COMPOSE (drag A→B or B→A, irreversible)"
  putStrLn "  Phase 3: REFINE (↻CW/↺CCW adjust α, tap to export)"
  putStrLn "  A+B ≠ B+A. The base determines structure."
  putStrLn "  The residual adds the other's divergence."
  putStrLn "  The GIF is the memory. Composition is how you blend."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 1000) :: Int) / 1000.0 :: Double)
          in take 6 (s ++ repeat '0')

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
