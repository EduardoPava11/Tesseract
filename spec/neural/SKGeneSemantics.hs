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
--
-- Daniel's question (2026-08-11): "S(x,y,t) and K(x,y)/K(y,x)?!"
-- Answer, made exact under the axis clock (axis = depth mod 3):
--
--   AX6  S IS the ternary all-axes operator: its 3-App spine sits
--        at depths d,d+1,d+2 (all three axes once) and its
--        operands root one-per-phase (x@a, z@a+1, y@a+2). The
--        ROTATION LAW, checked on every event via exact per-axis
--        App-histogram accounting: the copied argument z rotates
--        +1 (both copies), the function context x rotates −1, y
--        stays; net spine budget +1 on axis a+1, −1 on a+2
--   AX7  K rotation law: spine covers exactly the ordered pair
--        (a, a+1) — forward-cyclic only, never reversed; discard
--        y roots at phase a+1, keep x at a+2, and the kept
--        subtree rotates +1 on survival (contraction twists)
--   AX8  chirality is charged: the mirrored projection K(y,x) is
--        NOT primitive — keep-right = K·(SKK), size 4 vs 1,
--        realizing y in exactly 3 steps [K,S,K] vs K's 1
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

-- The redex, with its depth and operands (the raw material of the
-- rotation laws): K-spine holds y@d+1(discard), x@d+2(keep);
-- S-spine holds z@d+1, y@d+2, x@d+3.
data Redex = RK Int C C          -- depth, x (kept), y (discarded)
           | RS Int C C C        -- depth, x, y, z (copied)
  deriving (Eq, Show)

symOf :: Redex -> Sym
symOf (RK {}) = SymK
symOf (RS {}) = SymS

depthOf :: Redex -> Int
depthOf (RK d _ _)   = d
depthOf (RS d _ _ _) = d

-- One leftmost-outermost step with full redex information.
stepR :: C -> Maybe (Redex, C)
stepR = go 0
  where
    go d (App (App K x) y)         = Just (RK d x y, x)
    go d (App (App (App S x) y) z) = Just (RS d x y z, App (App x z) (App y z))
    go d (App f a) = case go (d + 1) f of
      Just (r, f') -> Just (r, App f' a)
      Nothing      -> fmap (App f) <$> go (d + 1) a
    go _ _ = Nothing

stepD :: C -> Maybe ((Sym, Int), C)
stepD t = (\(r, t') -> ((symOf r, depthOf r), t')) <$> stepR t

unroll, sizeCap :: Int
unroll  = 16
sizeCap = 50000

-- Truncated trajectory (the JEPA sees exactly this):
-- events = [(redex, term-before, term-after)]; Bool = halted.
traj :: C -> ([(Redex, C, C)], C, Bool)
traj = go 0 []
  where
    go n acc t
      | n >= unroll || size t > sizeCap = (reverse acc, t, False)
      | otherwise = case stepR t of
          Nothing      -> (reverse acc, t, True)
          Just (r, t') -> go (n + 1) ((r, t, t') : acc) t'

actOf :: Redex -> Action
actOf r = (symOf r, axisOf (depthOf r))

pool :: [C]
pool = trees 7

corpus :: [(C, [(Redex, C, C)], C, Bool)]
corpus = [ (g, es, nf, h) | g <- pool, let (es, nf, h) = traj g ]

-- ════════════════════════════════════════════════════════════════
-- § 1b. Per-axis App-histogram accounting (the rotation laws)
--       H r t = App counts of subtree t (rooted at depth r) by
--       axis phase; hAt d = a single App at depth d.
-- ════════════════════════════════════════════════════════════════

type Hist = (Int, Int, Int)

hZero :: Hist
hZero = (0, 0, 0)

hAt :: Int -> Hist
hAt d = case d `mod` 3 of
  0 -> (1,0,0); 1 -> (0,1,0); _ -> (0,0,1)

hAdd, hSub :: Hist -> Hist -> Hist
hAdd (a,b,c) (p,q,r) = (a+p, b+q, c+r)
hSub (a,b,c) (p,q,r) = (a-p, b-q, c-r)

appHist :: Int -> C -> Hist
appHist _ S = hZero
appHist _ K = hZero
appHist r (App f a) =
  hAt r `hAdd` appHist (r+1) f `hAdd` appHist (r+1) a

-- Closed-form prediction of the post-term's axis histogram from
-- the pre-term and the redex alone — the ROTATION LAWS:
--   K: lose spine (a, a+1) and all of y@d+1 and x@d+2; regain x
--      rooted at d (kept subtree rotates +1 ≡ −2)
--   S: spine trades one a+2-App for a second a+1-App; x re-roots
--      d+3 → d+2 (rotates −1); z re-roots d+1 → d+2 twice
--      (both copies rotate +1); y stays at d+2
predictHist :: C -> Redex -> Hist
predictHist pre (RK d x y) =
  appHist 0 pre
    `hSub` hAt d `hSub` hAt (d+1)
    `hSub` appHist (d+1) y
    `hSub` appHist (d+2) x
    `hAdd` appHist d x
predictHist pre (RS d x _y z) =
  appHist 0 pre
    `hAdd` hAt (d+1) `hSub` hAt (d+2)
    `hAdd` appHist (d+2) x `hSub` appHist (d+3) x
    `hAdd` appHist (d+2) z `hAdd` appHist (d+2) z
    `hSub` appHist (d+1) z

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
  let allEvents = [ actOf r | (_, es, _, _) <- corpus, (r, _, _) <- es ]
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
  let haltMax = maximum [ size t | (es, _) <- halters, (_, _, t) <- es ]
      nfMax   = maximum [ size nf | (_, nf) <- halters ]
      divMax  = maximum [ size t | es <- divergers, (_, _, t) <- es ]
  g5 <- gate "AX5  capacity: halters ≤ 41 (= max NF), divergers reach 187 at unroll"
      $ haltMax == 41 && nfMax == 41 && divMax == 187

  -- AX6/AX7: the rotation laws, exact on every event
  let events    = [ ev | (_, es, _, _) <- corpus, ev <- es ]
      lawHolds (r, pre, post) = predictHist pre r == appHist 0 post
      sEvents   = [ ev | ev@(RS {}, _, _) <- events ]
      kEvents   = [ ev | ev@(RK {}, _, _) <- events ]
  g6 <- gate "AX6  S rotation law exact on all S-events (z +1 twice, x −1, y 0)"
      $ all lawHolds sEvents
        && length sEvents == 3988 + 2995 + 1454
  g7 <- gate "AX7  K rotation law exact on all K-events (kept subtree rotates +1)"
      $ all lawHolds kEvents
        && length kEvents == 7441 + 6892 + 4649

  -- AX8: chirality is charged — keep-right only as composite K·(SKK)
  let i'        = App (App S K) K                    -- I = SKK
      keepRight = App K i'                            -- K̃ = K·I, size 4
      apply2 p a b = App (App p a) b
      mirrorRun a b = traj (apply2 keepRight a b)
      mirrorOK (a, b) =
        let (es, final, halted) = mirrorRun a b
        in halted && final == b
           && map (symOf . (\(r,_,_) -> r)) es == [SymK, SymS, SymK]
      probes = [ (K, S), (S, K), (App S K, App K K) ]
      directK (a, b) =
        let (es, final, halted) = traj (apply2 K a b)
        in halted && final == a && length es == 1
  g8 <- gate "AX8  K(y,x) not primitive: keep-right = K·(SKK), 3 steps [K,S,K] vs 1"
      $ size keepRight == 4 && size K == 1
        && all mirrorOK probes
        && all directK probes

  putStrLn ""
  let results = [g1, g2, g3, g4, g5, g6, g7, g8]
  putStrLn $ "  " ++ show (length (filter id results)) ++ "/"
           ++ show (length results) ++ " gates green"
  putStrLn ""
  putStrLn "  The corpus is the semantics: 27,419 typed reduction pairs,"
  putStrLn "  2,692 attractors, 2 orbits. The JEPA learns the rest."
  if and results then pure () else error "SKGeneSemantics: gate failure"
