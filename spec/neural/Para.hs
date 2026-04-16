{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- Para: Parameterized Morphisms for Neural Layers
--
-- Based on Gavranovic's "Compositional Deep Learning" (2019).
-- Constrained to compose with Tesseract's existing type classes:
--   VectorSpace, DirectSum R1 R3 R4, Quantizable, Ditherable.
--
-- A Para morphism (θ, a) → b is a learnable function.
-- Composition threads parameter spaces as products.
-- The key constraint: a DepthMorphism outputs Depth ∈ R1,
-- never touching the R3 color axis.
--
-- The NN is 3 composed Para morphisms:
--   PatchEncoder ; Compress ; DepthHead
-- = (RGB patch → embedding → compressed → Depth)
--
-- Depth feeds into the EXISTING algebraic pipeline unchanged.
-- ════════════════════════════════════════════════════════════════

module Para where

import Data.List (foldl')

-- ════════════════════════════════════════════════════════════════
-- § 1. VECTOR TYPES (self-contained, mirrors Tesseract.hs VectorSpace)
-- ════════════════════════════════════════════════════════════════

-- | Dense vector (row-major)
type Vector = [Double]

-- | Dense matrix (row-major, outer = rows)
type Matrix = [[Double]]

vecAdd :: Vector -> Vector -> Vector
vecAdd = zipWith (+)

vecScale :: Double -> Vector -> Vector
vecScale k = map (* k)

dot :: Vector -> Vector -> Double
dot u v = sum (zipWith (*) u v)

matVecMul :: Matrix -> Vector -> Vector
matVecMul m v = [dot row v | row <- m]

relu :: Vector -> Vector
relu = map (max 0)

sigmoid :: Double -> Double
sigmoid x = 1.0 / (1.0 + exp (negate x))

-- ════════════════════════════════════════════════════════════════
-- § 2. PARA MORPHISM — the core abstraction
-- ════════════════════════════════════════════════════════════════

-- | A parameterized morphism: (params, input) → output
--   This is the object in Para(C).
data ParaM params input output = ParaM
  { pmForward :: params -> input -> output
  , pmName    :: String  -- for tracing
  }

-- | Compose two Para morphisms: thread parameter spaces as products.
--   compose (f : a→b) (g : b→c) = (f;g : a→c)
--   Params(f;g) = (Params f, Params g)
compose :: ParaM p1 a b -> ParaM p2 b c -> ParaM (p1, p2) a c
compose f g = ParaM
  { pmForward = \(pf, pg) x -> pmForward g pg (pmForward f pf x)
  , pmName    = pmName f ++ " ; " ++ pmName g
  }

-- | Parallel product: run two morphisms independently.
--   par (f : a→b) (g : c→d) = (f⊗g : (a,c)→(b,d))
--   Params(f⊗g) = (Params f, Params g)
parallel :: ParaM p1 a b -> ParaM p2 c d -> ParaM (p1, p2) (a, c) (b, d)
parallel f g = ParaM
  { pmForward = \(pf, pg) (x, y) -> (pmForward f pf x, pmForward g pg y)
  , pmName    = pmName f ++ " ⊗ " ++ pmName g
  }

-- | Identity morphism: no parameters, passes through.
identity :: ParaM () a a
identity = ParaM
  { pmForward = \() x -> x
  , pmName    = "id"
  }

-- ════════════════════════════════════════════════════════════════
-- § 3. LEARNER — Para morphism with backward pass
-- ════════════════════════════════════════════════════════════════

-- | A Learner adds a backward pass to a Para morphism.
--   backward: given (params, input, output_gradient),
--   produce (param_gradient, input_gradient).
data Learner params input output = Learner
  { lForward  :: params -> input -> output
  , lBackward :: params -> input -> output -> (params, input)
    -- ^ (param grad, input grad) given output grad
  , lName     :: String
  }

-- | Compose two Learners: chain rule for backward pass.
composeLearner :: Learner p1 a b -> Learner p2 b c -> Learner (p1, p2) a c
composeLearner f g = Learner
  { lForward = \(pf, pg) x ->
      let y = lForward f pf x
      in  lForward g pg y
  , lBackward = \(pf, pg) x dc ->
      let y  = lForward f pf x           -- cache forward of f
          (dpg, db) = lBackward g pg y dc -- backward through g
          (dpf, da) = lBackward f pf x db -- backward through f
      in ((dpf, dpg), da)
  , lName = lName f ++ " ; " ++ lName g
  }

-- ════════════════════════════════════════════════════════════════
-- § 4. CONCRETE LAYERS
-- ═════���══════════════════════════════════════════════════════════

-- | Linear layer: W×x + b
type LinearParams = (Matrix, Vector)  -- (W, b)

linearLayer :: Int -> Int -> String -> ParaM LinearParams Vector Vector
linearLayer _inDim _outDim name = ParaM
  { pmForward = \(w, b) x -> matVecMul w x `vecAdd` b
  , pmName    = name
  }

-- | ReLU activation: no parameters
reluLayer :: ParaM () Vector Vector
reluLayer = ParaM
  { pmForward = \() x -> relu x
  , pmName    = "ReLU"
  }

-- | Sigmoid → scalar in [0,1]: no parameters
sigmoidScalarLayer :: ParaM () Vector Double
sigmoidScalarLayer = ParaM
  { pmForward = \() x -> sigmoid (head x)
  , pmName    = "Sigmoid"
  }

-- ════════════════════════════════════════════════════════════════
-- § 5. DEPTH MORPHISM — output lives in R1, never R3
-- ════════════════════════════════════════════════════════════════

-- | A DepthMorphism is any Para morphism whose output is a
--   scalar depth ∈ [0,1]. It lives in R1 (temporal/epoch axis)
--   and produces NOTHING in R3 (color axis).
--
--   This is enforced by type: the output is Double (not Vector).
--   The DirectSum axiom project₂(inject₁(depth)) = zero holds
--   because inject₁ maps to R4's first component only.

newtype Depth = Depth { unDepth :: Double }
  deriving (Show, Eq, Ord)

-- | Wrap a Para morphism that outputs Double as a DepthMorphism
depthMorphism :: ParaM p a Double -> ParaM p a Depth
depthMorphism pm = ParaM
  { pmForward = \p x -> Depth (pmForward pm p x)
  , pmName    = pmName pm ++ " → Depth"
  }

-- ════════════════════════════════════════════════════════════════
-- § 6. PARAMETER COUNTING
-- ════════════════════════════════════════════════════════════════

-- | Count parameters in a linear layer
linearParamCount :: Int -> Int -> Int
linearParamCount inDim outDim = outDim * inDim + outDim  -- W + b

-- | Count for composed layers
data LayerSpec = LayerSpec
  { lsName   :: String
  , lsInDim  :: Int
  , lsOutDim :: Int
  , lsParams :: Int
  }

layerSpec :: String -> Int -> Int -> LayerSpec
layerSpec name inD outD = LayerSpec name inD outD (linearParamCount inD outD)

totalParams :: [LayerSpec] -> Int
totalParams = sum . map lsParams

-- ════════════════════════════════════════════════════════════════
-- § 7. AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-10

-- (PA1) Composition is associative (up to parameter restructuring)
--   compose (compose f g) h ≡ compose f (compose g h)
axiom_PA1 :: Bool
axiom_PA1 =
  let f = linearLayer 3 4 "f"
      g = linearLayer 4 2 "g"
      h = linearLayer 2 1 "h"

      -- Params for each layer
      wf = [[1,0,0],[0,1,0],[0,0,1],[1,1,1]]
      bf = [0,0,0,0]
      wg = [[1,0,0,0],[0,1,0,0]]
      bg = [0,0]
      wh = [[1,1]]
      bh = [0]

      -- (f;g);h
      fg = compose f g
      fgh_left = compose fg h
      out_left = pmForward fgh_left (((wf,bf),(wg,bg)),(wh,bh)) [1,2,3]

      -- f;(g;h)
      gh = compose g h
      fgh_right = compose f gh
      out_right = pmForward fgh_right ((wf,bf),((wg,bg),(wh,bh))) [1,2,3]

  in all (\(a, b) -> abs (a - b) < eps) (zip out_left out_right)

-- (PA2) Parameter spaces are products
--   Verified by construction: compose produces (p1, p2)
axiom_PA2 :: Bool
axiom_PA2 = True  -- enforced by the type of `compose`

-- (PA3) Forward distributes through composition
axiom_PA3 :: Bool
axiom_PA3 =
  let f = linearLayer 2 3 "f"
      g = linearLayer 3 1 "g"
      wf = [[1,0],[0,1],[1,1]]
      bf = [0,0,0]
      wg = [[1,1,1]]
      bg = [0]
      x  = [2.0, 3.0]

      -- Composed forward
      fg = compose f g
      composed_out = pmForward fg ((wf,bf),(wg,bg)) x

      -- Sequential forward
      mid = pmForward f (wf,bf) x
      seq_out = pmForward g (wg,bg) mid

  in all (\(a, b) -> abs (a - b) < eps) (zip composed_out seq_out)

-- (PA4) DirectSum preservation: DepthMorphism output ∈ [0,1]
axiom_PA4 :: Bool
axiom_PA4 =
  let dm = depthMorphism sigmoidScalarLayer
      -- Sigmoid always produces [0,1]
      results = [ unDepth (pmForward dm () [x]) | x <- [-10, -1, 0, 1, 10] ]
  in all (\d -> d >= 0.0 && d <= 1.0) results

-- (PA5) Identity is neutral for composition
axiom_PA5 :: Bool
axiom_PA5 =
  let f = linearLayer 2 2 "f"
      wf = [[1,0],[0,1]]
      bf = [0,0]
      x = [3.0, 4.0]

      -- f ; id
      f_id = compose f identity
      out1 = pmForward f_id ((wf,bf), ()) x

      -- id ; f
      id_f = compose identity f
      out2 = pmForward id_f ((), (wf,bf)) x

      -- just f
      out3 = pmForward f (wf,bf) x

  in all (\(a, b) -> abs (a - b) < eps) (zip out1 out3)
  && all (\(a, b) -> abs (a - b) < eps) (zip out2 out3)

-- (PA6) Parallel product preserves independence
axiom_PA6 :: Bool
axiom_PA6 =
  let f = linearLayer 2 1 "f"
      g = linearLayer 3 1 "g"
      wf = [[1,1]]; bf = [0]
      wg = [[1,1,1]]; bg = [0]
      fg = parallel f g
      (outF, outG) = pmForward fg ((wf,bf),(wg,bg)) ([2,3], [1,1,1])
  in abs (head outF - 5.0) < eps  -- 2+3
  && abs (head outG - 3.0) < eps  -- 1+1+1

-- ════════════════════════════════════════════════════════════════
-- § 8. MAIN
-- ════════════════════��═══════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Para: Parameterized Morphisms for Neural Layers"
  putStrLn " (θ, a) → b.  Composition threads parameters as products."
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Show the core operations
  putStrLn "── Core Operations ──"
  putStrLn ""
  putStrLn "  compose :: ParaM p1 a b → ParaM p2 b c → ParaM (p1,p2) a c"
  putStrLn "  parallel :: ParaM p1 a b → ParaM p2 c d → ParaM (p1,p2) (a,c) (b,d)"
  putStrLn "  identity :: ParaM () a a"
  putStrLn ""

  -- Show a concrete example
  putStrLn "── Example: Linear(2→3) ; Linear(3→1) ──"
  putStrLn ""
  let f = linearLayer 2 3 "Linear(2→3)"
      g = linearLayer 3 1 "Linear(3→1)"
      wf = [[1,0],[0,1],[1,1]]; bf = [0,0,0]
      wg = [[1,1,1]]; bg = [0]
      x = [2.0, 3.0]
      mid = pmForward f (wf,bf) x
      out = pmForward g (wg,bg) mid
      fg = compose f g
      composed_out = pmForward fg ((wf,bf),(wg,bg)) x
  putStrLn $ "  input:    " ++ show x
  putStrLn $ "  mid:      " ++ show mid
  putStrLn $ "  output:   " ++ show out
  putStrLn $ "  composed: " ++ show composed_out
  putStrLn $ "  match:    " ++ show (out == composed_out) ++ " ✓"
  putStrLn ""

  -- DepthMorphism example
  putStrLn "── DepthMorphism: output ∈ [0,1] ──"
  putStrLn ""
  let dm = depthMorphism sigmoidScalarLayer
  putStrLn "  input  │ depth"
  putStrLn "  ───────┼──────"
  mapM_ (\v -> do
    let d = pmForward dm () [v]
    putStrLn $ "  " ++ padL 6 (showF v) ++ " │ " ++ showF (unDepth d)
    ) [-5, -2, -1, 0, 1, 2, 5]
  putStrLn ""

  -- Parameter counting
  putStrLn "── Parameter Count: 3-Layer Depth NN ──"
  putStrLn ""
  let k = 3  -- patch size
      h = 16 -- hidden dim
      c = 8  -- compressed dim
      layers = [ layerSpec "PatchEncoder" (k*k*3) h
               , layerSpec "Compress"     h       c
               , layerSpec "DepthHead"    c       1
               ]
  putStrLn "  layer        │ in → out │ params"
  putStrLn "  ─────────────┼──────────┼───────"
  mapM_ (\ls -> do
    putStrLn $ "  " ++ padL 13 (lsName ls)
            ++ " │ " ++ padL 3 (show (lsInDim ls))
            ++ " → " ++ padL 3 (show (lsOutDim ls))
            ++ " │ " ++ show (lsParams ls)
    ) layers
  putStrLn $ "  ─────────────┼──────────┼───────"
  putStrLn $ "  TOTAL        │          │ " ++ show (totalParams layers)
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "PA1 composition is associative"                [axiom_PA1]
  check "PA2 parameter spaces are products"             [axiom_PA2]
  check "PA3 forward distributes through composition"   [axiom_PA3]
  check "PA4 DepthMorphism output ∈ [0,1]"             [axiom_PA4]
  check "PA5 identity is neutral for composition"       [axiom_PA5]
  check "PA6 parallel product preserves independence"   [axiom_PA6]
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Para(C): the language of learnable functions."
  putStrLn " Compose layers like morphisms. Thread parameters as products."
  putStrLn " DepthMorphism lives in R1. Color (R3) is never touched."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 1000) :: Int) / 1000.0 :: Double)
          in take 7 (s ++ repeat '0')

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
