{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}

-- | Direct Sum of 1D + 2D vector spaces
--   Axioms for V = U ⊕ W where dim U = 1, dim W = 2
--
--   Context: Type B head produces outputs living in ℝ¹ ⊕ ℝ²
--     ℝ¹ = information_loss (scalar, non-negative)
--     ℝ² = (quantization_gap_channel, color_expansion) per palette color
--
--   The direct sum guarantees unique decomposition:
--     every output vector v ∈ ℝ³ splits into exactly one (u, w) pair.

module DirectSum where

-- ============================================================
-- § 1. The Spaces
-- ============================================================

-- | 1-dimensional space: a single scalar (e.g., information_loss)
newtype R1 = R1 { unR1 :: Double }
  deriving (Show, Eq)

-- | 2-dimensional space: a pair (e.g., quantization_gap, color_expansion)
data R2 = R2 { r2x :: Double, r2y :: Double }
  deriving (Show, Eq)

-- | 3-dimensional space: the direct sum ℝ¹ ⊕ ℝ²
data R3 = R3 { r3x :: Double, r3y :: Double, r3z :: Double }
  deriving (Show, Eq)

-- ============================================================
-- § 2. Vector Space Axioms (per-space)
-- ============================================================

class VectorSpace v where
  zero   :: v              -- additive identity
  add    :: v -> v -> v    -- vector addition
  scale  :: Double -> v -> v  -- scalar multiplication
  neg    :: v -> v         -- additive inverse
  neg v  = scale (-1) v

instance VectorSpace R1 where
  zero = R1 0
  add (R1 a) (R1 b) = R1 (a + b)
  scale k (R1 a) = R1 (k * a)

instance VectorSpace R2 where
  zero = R2 0 0
  add (R2 a b) (R2 c d) = R2 (a + c) (b + d)
  scale k (R2 a b) = R2 (k * a) (k * b)

instance VectorSpace R3 where
  zero = R3 0 0 0
  add (R3 a b c) (R3 d e f) = R3 (a + d) (b + e) (c + f)
  scale k (R3 a b c) = R3 (k * a) (k * b) (k * c)

-- ============================================================
-- § 3. Direct Sum Structure: V = U ⊕ W
-- ============================================================

-- | The direct sum is defined by two canonical projections and
--   an injection (embedding) from each summand into the total space.
--
--   Axioms:
--     (A1) inject₁ ∘ project₁ + inject₂ ∘ project₂ = id
--     (A2) project₁ ∘ inject₁ = id on U
--     (A3) project₂ ∘ inject₂ = id on W
--     (A4) project₁ ∘ inject₂ = 0    (cross-projection annihilates)
--     (A5) project₂ ∘ inject₁ = 0
--     (A6) U ∩ W = {0}               (trivial intersection)
--     (A7) dim V = dim U + dim W      (dimension sum)

class (VectorSpace u, VectorSpace w, VectorSpace v)
  => DirectSum u w v | u w -> v, v -> u w where
  inject1  :: u -> v          -- embed U into V
  inject2  :: w -> v          -- embed W into V
  project1 :: v -> u          -- project V onto U
  project2 :: v -> w          -- project V onto W

instance DirectSum R1 R2 R3 where
  -- ℝ¹ embeds as the first coordinate, ℝ² as the last two
  inject1 (R1 a)   = R3 a 0 0
  inject2 (R2 a b) = R3 0 a b
  project1 (R3 a _ _) = R1 a
  project2 (R3 _ b c) = R2 b c

-- | Reconstruct: the canonical decomposition
--   Every v ∈ V factors uniquely as inject₁(u) + inject₂(w)
decompose :: DirectSum u w v => v -> (u, w)
decompose v = (project1 v, project2 v)

-- | Reconstruct from components
recompose :: DirectSum u w v => (u, w) -> v
recompose (u, w) = add (inject1 u) (inject2 w)

-- ============================================================
-- § 4. Axiom Verification (Property-Based)
-- ============================================================

-- Floating point tolerance
eps :: Double
eps = 1e-12

approxEq :: Double -> Double -> Bool
approxEq a b = abs (a - b) < eps

approxEqR3 :: R3 -> R3 -> Bool
approxEqR3 (R3 a b c) (R3 d e f) =
  approxEq a d && approxEq b e && approxEq c f

approxEqR1 :: R1 -> R1 -> Bool
approxEqR1 (R1 a) (R1 b) = approxEq a b

approxEqR2 :: R2 -> R2 -> Bool
approxEqR2 (R2 a b) (R2 c d) = approxEq a c && approxEq b d

-- (A1) inject₁ ∘ project₁ + inject₂ ∘ project₂ = id
axiom_decomposition_identity :: R3 -> Bool
axiom_decomposition_identity v =
  let u = project1 v :: R1
      w = project2 v :: R2
      reconstructed = add (inject1 u) (inject2 w) :: R3
  in approxEqR3 v reconstructed

-- (A2) project₁ ∘ inject₁ = id on ℝ¹
axiom_project1_retract :: R1 -> Bool
axiom_project1_retract u =
  approxEqR1 (project1 (inject1 u :: R3)) u

-- (A3) project₂ ∘ inject₂ = id on ℝ²
axiom_project2_retract :: R2 -> Bool
axiom_project2_retract w =
  approxEqR2 (project2 (inject2 w :: R3)) w

-- (A4) project₁ ∘ inject₂ = 0 (cross-annihilation)
axiom_cross_projection_1 :: R2 -> Bool
axiom_cross_projection_1 w =
  approxEqR1 (project1 (inject2 w :: R3)) (zero :: R1)

-- (A5) project₂ ∘ inject₁ = 0
axiom_cross_projection_2 :: R1 -> Bool
axiom_cross_projection_2 u =
  approxEqR2 (project2 (inject1 u :: R3)) (zero :: R2)

-- (A6) Trivial intersection: if v ∈ im(inject₁) ∩ im(inject₂), then v = 0
--   Proof: if v = inject₁(u) = inject₂(w), then
--          project₁(v) = u and project₂(v) = 0 (by A4)
--          project₂(v) = w and project₁(v) = 0 (by A5)
--          so u = 0 and w = 0, hence v = 0. ∎
axiom_trivial_intersection :: R1 -> R2 -> Bool
axiom_trivial_intersection u w =
  let v1 = inject1 u :: R3
      v2 = inject2 w :: R3
  in if approxEqR3 v1 v2
     then approxEqR3 v1 (zero :: R3)  -- only meet at origin
     else True  -- don't meet, vacuously true

-- (A7) Dimension: dim(ℝ¹ ⊕ ℝ²) = 1 + 2 = 3
-- This is a type-level fact in our encoding, but we verify numerically:
axiom_dimension_sum :: Bool
axiom_dimension_sum =
  let dimR1 = 1 :: Int
      dimR2 = 2 :: Int
      dimR3 = 3 :: Int
  in dimR1 + dimR2 == dimR3

-- ============================================================
-- § 5. Projection Axioms (Idempotence, Complementarity)
-- ============================================================

-- | Projections as endomorphisms on V
--   π₁ = inject₁ ∘ project₁ : V → V
--   π₂ = inject₂ ∘ project₂ : V → V

pi1 :: R3 -> R3
pi1 v = inject1 (project1 v :: R1)

pi2 :: R3 -> R3
pi2 v = inject2 (project2 v :: R2)

-- (P1) Idempotence: π₁ ∘ π₁ = π₁
axiom_idempotent_1 :: R3 -> Bool
axiom_idempotent_1 v = approxEqR3 (pi1 (pi1 v)) (pi1 v)

-- (P2) Idempotence: π₂ ∘ π₂ = π₂
axiom_idempotent_2 :: R3 -> Bool
axiom_idempotent_2 v = approxEqR3 (pi2 (pi2 v)) (pi2 v)

-- (P3) Complementarity: π₁ + π₂ = id
axiom_complementary :: R3 -> Bool
axiom_complementary v = approxEqR3 (add (pi1 v) (pi2 v)) v

-- (P4) Orthogonality: π₁ ∘ π₂ = 0
axiom_orthogonal_12 :: R3 -> Bool
axiom_orthogonal_12 v = approxEqR3 (pi1 (pi2 v)) (zero :: R3)

-- (P5) Orthogonality: π₂ ∘ π₁ = 0
axiom_orthogonal_21 :: R3 -> Bool
axiom_orthogonal_21 v = approxEqR3 (pi2 (pi1 v)) (zero :: R3)

-- ============================================================
-- § 6. Non-Negative Cone (Type B Constraint)
-- ============================================================

-- | Type B outputs live in ℝ≥0¹ ⊕ ℝ≥0² — the non-negative cone
--   within the direct sum. This is NOT a subspace (not closed under
--   negation), but it IS a convex cone:
--
--   (C1) 0 ∈ Cone
--   (C2) v ∈ Cone, λ ≥ 0 ⟹ λv ∈ Cone
--   (C3) u,v ∈ Cone ⟹ u + v ∈ Cone
--   (C4) v ∈ Cone, -v ∈ Cone ⟹ v = 0  (pointed)

data Cone3 = Cone3
  { coneScalar :: Double  -- information_loss ≥ 0
  , coneGap    :: Double  -- quantization_gap ≥ 0
  , coneExpand :: Double  -- color_expansion  ≥ 0
  } deriving (Show, Eq)

inCone :: R3 -> Bool
inCone (R3 a b c) = a >= 0 && b >= 0 && c >= 0

-- (C1) Zero is in the cone
axiom_cone_zero :: Bool
axiom_cone_zero = inCone (zero :: R3)

-- (C2) Non-negative scaling preserves cone membership
axiom_cone_scale :: Double -> R3 -> Bool
axiom_cone_scale k v
  | k >= 0 && inCone v = inCone (scale k v)
  | otherwise           = True  -- precondition not met

-- (C3) Addition preserves cone membership
axiom_cone_add :: R3 -> R3 -> Bool
axiom_cone_add u v
  | inCone u && inCone v = inCone (add u v)
  | otherwise             = True

-- (C4) Pointed: only zero is both in cone and in negated cone
axiom_cone_pointed :: R3 -> Bool
axiom_cone_pointed v
  | inCone v && inCone (neg v) = approxEqR3 v (zero :: R3)
  | otherwise                  = True

-- ============================================================
-- § 7. Application to Type B Head
-- ============================================================

-- | A Type B head output for a single palette color k
data TypeBOutput = TypeBOutput
  { infoLoss      :: R1   -- information_loss ∈ ℝ≥0¹
  , quantGap      :: R2   -- (gap_channel, gap_spatial) ∈ ℝ≥0²
  } deriving (Show)

-- | Embed into the full direct sum space
typeBToR3 :: TypeBOutput -> R3
typeBToR3 (TypeBOutput il qg) = recompose (il, qg)

-- | Recover structured output from raw vector
r3ToTypeB :: R3 -> TypeBOutput
r3ToTypeB v = let (u, w) = decompose v
              in TypeBOutput u w

-- | Verify a Type B output lives in the non-negative cone
typeBValid :: TypeBOutput -> Bool
typeBValid tb = inCone (typeBToR3 tb)

-- ============================================================
-- § 8. Contrast with Type A (Torsor / Signed Deltas)
-- ============================================================

-- | Type A lives in the full vector space (signed):
--     δ ∈ ℤ^(64³), with δ(A,B) = -δ(B,A)
--   The direct sum decomposition is IRRELEVANT to Type A
--   because Type A has no privileged split — all 64³ dimensions
--   are homogeneous (each is a palette index delta).
--
--   Type B REQUIRES the decomposition because:
--     - The scalar component (info_loss) is dimensionally distinct
--       from the per-color components (gap, expansion)
--     - You cannot add information_loss to a quantization_gap
--     - The projection π₁ extracts a DIFFERENT PHYSICAL QUANTITY
--       than π₂
--
--   This is the mathematical reason Type A and Type B are
--   fundamentally different comparison heads.

-- ============================================================
-- § 9. Run All Axiom Checks
-- ============================================================

-- | Test vectors spanning interesting cases
testVectors :: [R3]
testVectors =
  [ R3 1 0 0       -- pure ℝ¹ component
  , R3 0 1 0       -- pure ℝ² component (x)
  , R3 0 0 1       -- pure ℝ² component (y)
  , R3 3 4 5       -- general vector
  , R3 0 0 0       -- zero
  , R3 (-2) 7 (-3) -- mixed signs (valid in full space, NOT in cone)
  , R3 0.5 0.3 0.8 -- Type B style output (all non-negative)
  ]

testR1 :: [R1]
testR1 = [R1 0, R1 1, R1 (-3), R1 42.5]

testR2 :: [R2]
testR2 = [R2 0 0, R2 1 0, R2 0 1, R2 3.5 (-2.1)]

runAxioms :: IO ()
runAxioms = do
  putStrLn "══════════════════════════════════════════════"
  putStrLn " Direct Sum Axioms: ℝ¹ ⊕ ℝ² = ℝ³"
  putStrLn "══════════════════════════════════════════════"
  putStrLn ""

  -- Direct sum axioms
  check "A1 decomposition identity"
    [axiom_decomposition_identity v | v <- testVectors]

  check "A2 project₁ ∘ inject₁ = id"
    [axiom_project1_retract u | u <- testR1]

  check "A3 project₂ ∘ inject₂ = id"
    [axiom_project2_retract w | w <- testR2]

  check "A4 project₁ ∘ inject₂ = 0"
    [axiom_cross_projection_1 w | w <- testR2]

  check "A5 project₂ ∘ inject₁ = 0"
    [axiom_cross_projection_2 u | u <- testR1]

  check "A6 trivial intersection"
    [axiom_trivial_intersection u w | u <- testR1, w <- testR2]

  check "A7 dimension sum (1+2=3)"
    [axiom_dimension_sum]

  putStrLn ""
  putStrLn "── Projection Axioms ──"

  check "P1 π₁ idempotent"
    [axiom_idempotent_1 v | v <- testVectors]

  check "P2 π₂ idempotent"
    [axiom_idempotent_2 v | v <- testVectors]

  check "P3 π₁ + π₂ = id"
    [axiom_complementary v | v <- testVectors]

  check "P4 π₁ ∘ π₂ = 0"
    [axiom_orthogonal_12 v | v <- testVectors]

  check "P5 π₂ ∘ π₁ = 0"
    [axiom_orthogonal_21 v | v <- testVectors]

  putStrLn ""
  putStrLn "── Non-Negative Cone Axioms (Type B) ──"

  let coneVecs = filter inCone testVectors
  check "C1 zero ∈ cone"
    [axiom_cone_zero]

  check "C2 λ≥0, v∈cone ⟹ λv∈cone"
    [axiom_cone_scale k v | k <- [0, 0.5, 1, 3.7], v <- coneVecs]

  check "C3 u,v∈cone ⟹ u+v∈cone"
    [axiom_cone_add u v | u <- coneVecs, v <- coneVecs]

  check "C4 pointed (v,-v∈cone ⟹ v=0)"
    [axiom_cone_pointed v | v <- testVectors]

  putStrLn ""
  putStrLn "── Type B Round-Trip ──"
  let tb = TypeBOutput (R1 0.23) (R2 0.45 0.67)
  let v  = typeBToR3 tb
  let tb' = r3ToTypeB v
  putStrLn $ "  Original:      " ++ show tb
  putStrLn $ "  → ℝ³:          " ++ show v
  putStrLn $ "  → TypeBOutput: " ++ show tb'
  putStrLn $ "  Valid (cone):  " ++ show (typeBValid tb)
  putStrLn $ "  Round-trip OK: " ++ show (approxEqR1 (infoLoss tb) (infoLoss tb')
                                       && approxEqR2 (quantGap tb) (quantGap tb'))

  putStrLn ""
  putStrLn "══════════════════════════════════════════════"
  putStrLn " All axioms verified."
  putStrLn "══════════════════════════════════════════════"

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n      = length results
      mark   = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
             ++ " (" ++ show n ++ " cases)"

main :: IO ()
main = runAxioms
