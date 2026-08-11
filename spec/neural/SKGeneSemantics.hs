{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

-- ════════════════════════════════════════════════════════════════
-- SKGeneSemantics: axis-typed S,K actions + the learned-semantics
-- training corpus for the gene JEPA
--
-- Design: docs/sk-gene-calculus-2026-08-11.md §8–§10. Companion to
-- SKGeneCalculus.hs (which fixes the octave retract laws).
--
-- Daniel's ruling (2026-08-11): operations occur in LATENT space;
-- the S/K strings are symbols and the model learns WHAT they do.
-- So the calculus stops prescribing semantics and starts
-- prescribing DATA: every reduction step becomes a supervised
-- (state, action, next-state) tuple for an action-conditioned
-- H-JEPA, where action = (symbol, axis) and both states are terms
-- embedded in the tower. Semantics = whatever latent maps make
-- reduction an invariance. The two exact structures that survive
-- as hard law: axis separability (AX1) and the corpus itself
-- (AX2–AX5), pinned so the training set can never drift silently.
--
-- Axis typing: the octree cycles axes x → y → t with pyramid
-- depth (third axis of the capture cube is TIME — the 4³ blocks
-- are spacetime). The redex's App-depth mod 3 assigns the axis.
--
-- Gates (exact, Integer/Rational):
--
--   AX1  separability: the 2×2×2 Haar octave IS the cube of the
--        binary 2-point primitive — three axis stages (t, y, x)
--        equal the direct (ℤ/2)³ character transform, exactly,
--        and invert exactly
--   AX2  action vocabulary: exactly 6 typed actions (S/K × x/y/t),
--        all realized in SK₇; histogram pinned:
--        K: 7441/6892/4649, S: 3988/2995/1454 by axis
--   AX3  corpus size: 27,419 reduction pairs at UNROLL=16, and
--        self-consistent with the halting distribution:
--        Σ t·n_t + 2·16 = 27,387 + 32
--   AX4  semantic quotient: the 16,894 halting genes denote only
--        2,692 distinct normal forms (largest class 1,148); all
--        normal forms irreducible — the latent denotation space
--        is 2,692 attractors + 2 orbits, NOT 16,896 points
--   AX5  capacity constants DERIVED: halting trajectories never
--        exceed term size 41 (= max normal form size); divergers
--        reach exactly 187 at the unroll horizon — the per-
--        activation term-tree capacity the tower must host
-- ════════════════════════════════════════════════════════════════

module Main where

import qualified Data.Map.Strict as M
import Data.Ratio ((%))

-- ════════════════════════════════════════════════════════════════
-- § 1. Calculus with typed events
-- ════════════════════════════════════════════════════════════════

data C = S | K | App C C deriving (Eq, Ord)

instance Show C where
  show S = "s"
  show K = "k"
  show (App f x) = show f ++ "[" ++ show x ++ "]"

size :: C -> Int
size S = 1
size K = 1
size (App f x) = size f + size x

trees :: Int -> [C]
trees 1 = [S, K]
trees n = [ App f x | i <- [1 .. n - 1], f <- trees i, x <- trees (n - i) ]

data Sym  = SymS | SymK          deriving (Eq, Ord, Show)
data Axis = AxX | AxY | AxT      deriving (Eq, Ord, Show, Enum, Bounded)

-- redex App-depth mod 3 → axis (octree axis clock x → y → t)
axisOf :: Int -> Axis
axisOf d = toEnum (d `mod` 3)

type Action = (Sym, Axis)

-- One leftmost-outermost step tagged (symbol, redex depth).
stepD :: C -> Maybe ((Sym, Int), C)
stepD = go 0
  where
    go d (App (App K x) _)         = Just ((SymK, d), x)
    go d (App (App (App S x) y) z) = Just ((SymS, d), App (App x z) (App y z))
    go d (App f a) = case go (d + 1) f of
      Just (t, f') -> Just (t, App f' a)
      Nothing      -> fmap (App f) <$> go (d + 1) a
    go _ _ = Nothing

unroll, sizeCap :: Int
unroll  = 16
sizeCap = 50000

-- Truncated trajectory (the JEPA sees exactly this):
-- events = [(action, term-after)]; Bool = halted within unroll.
traj :: C -> ([(Action, C)], C, Bool)
traj = go 0 []
  where
    go n acc t
      | n >= unroll || size t > sizeCap = (reverse acc, t, False)
      | otherwise = case stepD t of
          Nothing            -> (reverse acc, t, True)
          Just ((sym, d), t') ->
            go (n + 1) (((sym, axisOf d), t') : acc) t'

pool :: [C]
pool = trees 7

corpus :: [(C, [(Action, C)], C, Bool)]
corpus = [ (g, es, nf, h) | g <- pool, let (es, nf, h) = traj g ]

-- ════════════════════════════════════════════════════════════════
-- § 2. Axis-separable Haar on ℚ: the octave as cube of the
--      binary primitive.  2-point stage: (u,v) ↦ ((u+v)/2,(u−v)/2)
-- ════════════════════════════════════════════════════════════════

type Q = Rational
type Corner = (Int, Int, Int)

corners :: [Corner]
corners = [ (a,b,c) | a <- [0,1], b <- [0,1], c <- [0,1] ]

chi :: Corner -> Corner -> Q
chi (w1,w2,w3) (e1,e2,e3) = if odd (w1*e1 + w2*e2 + w3*e3) then -1 else 1

type Field = Corner -> Q

-- One binary Haar stage along one axis, applied to the whole array
-- (index along that axis becomes the frequency bit).
stage :: Int -> Field -> Field
stage ax f (i1,i2,i3) =
  let get b = f (setAt ax b (i1,i2,i3))
      bit   = getAt ax (i1,i2,i3)
  in if bit == 0 then (get 0 + get 1) / 2 else (get 0 - get 1) / 2

unstage :: Int -> Field -> Field
unstage ax f (i1,i2,i3) =
  let coef b = f (setAt ax b (i1,i2,i3))
      bit    = getAt ax (i1,i2,i3)
  in if bit == 0 then coef 0 + coef 1 else coef 0 - coef 1

getAt :: Int -> Corner -> Int
getAt 0 (a,_,_) = a; getAt 1 (_,b,_) = b; getAt _ (_,_,c) = c

setAt :: Int -> Int -> Corner -> Corner
setAt 0 v (_,b,c) = (v,b,c); setAt 1 v (a,_,c) = (a,v,c)
setAt _ v (a,b,_) = (a,b,v)

-- Three axis stages t, y, x  vs  direct character transform.
separable :: Field -> Field
separable = stage 0 . stage 1 . stage 2      -- t then y then x

direct :: Field -> Field
direct f w = sum [ chi w e * f e | e <- corners ] / 8

unseparable :: Field -> Field
unseparable = unstage 2 . unstage 1 . unstage 0

-- ════════════════════════════════════════════════════════════════
-- § 3. Gates
-- ════════════════════════════════════════════════════════════════

gate :: String -> Bool -> IO Bool
gate name ok = do
  putStrLn $ "  " ++ (if ok then "✓" else "✗") ++ " " ++ name
  pure ok

expectedHist :: [(Action, Int)]
expectedHist =
  [ ((SymK, AxX), 7441), ((SymK, AxY), 6892), ((SymK, AxT), 4649)
  , ((SymS, AxX), 3988), ((SymS, AxY), 2995), ((SymS, AxT), 1454) ]

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " SKGeneSemantics: typed actions + the gene-JEPA corpus"
  putStrLn " symbols stay symbols — the model learns what they do"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  -- AX1: octave = cube of the binary primitive, exactly
  let blockA, blockB :: Field
      blockA (a,b,c) = fromIntegral (1 + a + 2*b + 4*c) % 3
      blockB (a,b,c) = [1%2, -3, 7%5, 0, 22%7, -1%9, 4, 5%6]
                       !! (a + 2*b + 4*c)
      eqField f g = all (\e -> f e == g e) corners
  g1 <- gate "AX1  separability: 3 axis stages ≡ (ℤ/2)³ characters; exact inverse"
      $ all (\f -> eqField (separable f) (direct f)
                 && eqField (unseparable (separable f)) f)
            [blockA, blockB]

  -- shared corpus statistics
  let allEvents = [ a | (_, es, _, _) <- corpus, (a, _) <- es ]
      hist      = M.toList $ M.fromListWith (+) [ (a, 1::Int) | a <- allEvents ]
      halters   = [ (es, nf) | (_, es, nf, True) <- corpus ]
      divergers = [ es | (_, es, _, False) <- corpus ]

  -- AX2: the 6-token action vocabulary, pinned
  g2 <- gate "AX2  6 typed actions, all realized; histogram pinned"
      $ M.fromList hist == M.fromList expectedHist
        && length hist == 6

  -- AX3: corpus size + self-consistency with the halting distribution
  let times  = [ length es | (es, _) <- halters ]
      pairs  = length allEvents
  g3 <- gate "AX3  corpus = 27,419 pairs = Σ t·n_t + 2·16 (self-consistent)"
      $ pairs == 27419
        && pairs == sum times + 2 * unroll
        && length divergers == 2

  -- AX4: semantic quotient
  let nfClasses = M.fromListWith (+)
                    [ (show nf, 1::Int) | (_, nf) <- halters ]
      nfsIrreducible = all (\(_, nf) -> stepD nf == Nothing) halters
  g4 <- gate "AX4  16,894 halters → 2,692 normal forms (largest class 1,148)"
      $ M.size nfClasses == 2692
        && maximum (M.elems nfClasses) == 1148
        && nfsIrreducible
        && length halters == 16894

  -- AX5: derived capacity constants
  let haltMax = maximum [ size t | (es, _) <- halters, (_, t) <- es ]
      nfMax   = maximum [ size nf | (_, nf) <- halters ]
      divMax  = maximum [ size t | es <- divergers, (_, t) <- es ]
  g5 <- gate "AX5  capacity: halters ≤ 41 (= max NF), divergers reach 187 at unroll"
      $ haltMax == 41 && nfMax == 41 && divMax == 187

  putStrLn ""
  let results = [g1, g2, g3, g4, g5]
  putStrLn $ "  " ++ show (length (filter id results)) ++ "/"
           ++ show (length results) ++ " gates green"
  putStrLn ""
  putStrLn "  The corpus is the semantics: 27,419 typed reduction pairs,"
  putStrLn "  2,692 attractors, 2 orbits. The JEPA learns the rest."
  if and results then pure () else error "SKGeneSemantics: gate failure"
