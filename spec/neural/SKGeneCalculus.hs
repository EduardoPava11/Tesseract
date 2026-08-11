{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

-- ════════════════════════════════════════════════════════════════
-- SKGeneCalculus: S,K combinators as genes on the 2×2×2 ↔ 1 octave
--
-- Design: docs/sk-gene-calculus-2026-08-11.md. Provenance: the
-- exhaustive size-7 enumeration (~/SKCentennial), after Wolfram,
-- "Combinators: A Centennial View" (2020).
--
-- The abstraction: do not train 16,896 genes — train TWO primitive
-- maps, σ : L → L² (expansion, the S side) and κ : L² → L
-- (contraction, the K side). The octave 2×2×2 ↔ 1 is the CUBE of
-- the binary primitives (depth-3 octree fold/unfold). Genes are
-- size-7 S,K terms; activation = one normal-order reduction step
-- per frame; K-events contract blocks, S-events expand them.
--
-- Gates (all exact — Integer / Rational arithmetic):
--
--   SK1  |SK₇| = Catalan(6)·2⁷ = 16,896
--   SK2  halting-time distribution pinned; max halter t=15 is
--        s[s[s[s]]][s][s][s]
--   SK3  divergers = exactly the two pure-S terms
--        s[s][s][s[s]][s][s] and s[s[s]][s][s][s][s]
--   SK4  size dynamics exact on EVERY reduction event of EVERY
--        gene trajectory: Δ_K = −(|y|+1), Δ_S = |z|−1; per-
--        trajectory bookkeeping identity Σ holds
--   SK5  UNROLL = 16 is DERIVED: classification at cap 16 equals
--        classification at cap 1000 (halted/diverged identical)
--   SK6  Haar octave on ℚ: K̂∘Ŝ = id, ê∘ê = ê, character
--        orthogonality Σ_ε χ_w χ_w' = 8δ, bands 3:3:1 by |w|
--   SK7  Law A by parameterization: DC(Ŝ_g x) = x for ARBITRARY
--        detail generators g_w — the retraction cannot fail
--   SK8  palette = classical basis (toy): copy defect vanishes
--        exactly on codebook states, nonzero off it; κ∘σ = id
--        everywhere (Frobenius specialness on the codebook)
--   SK9  fixed-point law: step is undefined (Nothing) on every
--        halted gene's final term — halted genes idle safely
--        inside the fixed unroll
--   SK10 phase partition: ORDER(t≤2) + BOUNDARY(3≤t≤15) + CHAOS
--        = 13,644 + 3,250 + 2 = 16,896
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.List (sortOn, groupBy)
import Data.Ratio ((%))

-- ════════════════════════════════════════════════════════════════
-- § 1. The calculus
-- ════════════════════════════════════════════════════════════════

data C = S | K | App C C
  deriving (Eq)

instance Show C where
  show S = "s"
  show K = "k"
  show (App f x) = show f ++ "[" ++ show x ++ "]"

size :: C -> Int
size S = 1
size K = 1
size (App f x) = size f + size x

pureS :: C -> Bool
pureS S = True
pureS K = False
pureS (App f x) = pureS f && pureS x

-- All expressions with exactly n leaves.
trees :: Int -> [C]
trees 1 = [S, K]
trees n = [ App f x | i <- [1 .. n - 1], f <- trees i, x <- trees (n - i) ]

catalan :: Integer -> Integer
catalan n = product [n+2 .. 2*n] `div` product [2 .. n]

-- One leftmost-outermost step, tagged with its event:
--   KEv dy  : K-contraction, dy = |y|+1  (size strictly drops by dy)
--   SEv dz  : S-expansion,  dz = |z|−1  (size grows by dz ≥ 0)
data Event = KEv Int | SEv Int deriving (Eq, Show)

delta :: Event -> Int
delta (KEv dy) = negate dy
delta (SEv dz) = dz

stepE :: C -> Maybe (Event, C)
stepE (App (App K x) y)         = Just (KEv (size y + 1), x)
stepE (App (App (App S x) y) z) = Just (SEv (size z - 1),
                                        App (App x z) (App y z))
stepE (App f a) =
  case stepE f of
    Just (ev, f') -> Just (ev, App f' a)
    Nothing       -> fmap (fmap (App f)) (stepE a)
stepE _ = Nothing

step :: C -> Maybe C
step = fmap snd . stepE

-- Bounded trajectory: list of (event, term-after) up to caps.
-- Right t  = halted in t steps;  Left ()  = still going at a cap.
data Fate = Halted Int | Diverged deriving (Eq, Show)

trajectory :: Int -> Int -> C -> (Fate, [(Event, C, C)])
trajectory cap sizeCap = go 0 []
  where
    go n acc t
      | n > cap          = (Diverged, reverse acc)
      | size t > sizeCap = (Diverged, reverse acc)
      | otherwise = case stepE t of
          Nothing       -> (Halted n, reverse acc)
          Just (ev, t') -> go (n + 1) ((ev, t, t') : acc) t'

-- ════════════════════════════════════════════════════════════════
-- § 2. The gene pool: SK₇ enumerated once
-- ════════════════════════════════════════════════════════════════

geneSize, unroll, bigCap, sizeCap :: Int
geneSize = 7
unroll   = 16      -- DERIVED: max halting time 15 + one idle step (SK5)
bigCap   = 1000
sizeCap  = 50000

pool :: [C]
pool = trees geneSize

runs :: [(C, Fate, [(Event, C, C)])]
runs = [ (g, f, evs) | g <- pool
       , let (f, evs) = trajectory bigCap sizeCap g ]

fateAt :: Int -> C -> Fate
fateAt cap g = fst (trajectory cap sizeCap g)

haltDist :: [(Int, Int)]
haltDist = map (\xs -> (head xs, length xs))
         . groupBy (==) . sortOn id
         $ [ t | (_, Halted t, _) <- runs ]

divergers :: [C]
divergers = [ g | (g, Diverged, _) <- runs ]

-- ════════════════════════════════════════════════════════════════
-- § 3. The octave on ℚ: Haar skeleton, one latent channel
--      Corners ε ∈ {0,1}³; characters χ_w(ε) = (−1)^{w·ε}.
-- ════════════════════════════════════════════════════════════════

type Q = Rational
type Corner = (Int, Int, Int)                 -- ε
type Block  = [(Corner, Q)]                   -- 8 corners

corners :: [Corner]
corners = [ (a,b,c) | a <- [0,1], b <- [0,1], c <- [0,1] ]

chi :: Corner -> Corner -> Q
chi (w1,w2,w3) (e1,e2,e3) =
  if odd (w1*e1 + w2*e2 + w3*e3) then -1 else 1

weight :: Corner -> Int
weight (a,b,c) = a + b + c

dc :: Block -> Q                              -- K̂₀: pure weakening
dc b = sum (map snd b) / 8

detail :: Corner -> Block -> Q                -- d_w
detail w b = sum [ chi w e * v | (e, v) <- b ] / 8

-- Ŝ_g: expansion with arbitrary detail generators g_w : ℚ → ℚ.
-- DC(Ŝ_g x) = x holds for ANY g because Σ_ε χ_w(ε) = 0, w ≠ 0.
expandWith :: (Corner -> Q -> Q) -> Q -> Block
expandWith g x =
  [ (e, x + sum [ chi w e * g w x | w <- corners, w /= (0,0,0) ])
  | e <- corners ]

expand0 :: Q -> Block                         -- Ŝ₀: constant block (copy³)
expand0 = expandWith (\_ _ -> 0)

reconstruct :: Q -> [(Corner, Q)] -> Block
reconstruct a ds =
  [ (e, a + sum [ chi w e * d | (w, d) <- ds ]) | e <- corners ]

-- ════════════════════════════════════════════════════════════════
-- § 4. Toy classical structure: codebook = copyable states
--      σ(x) = (x + h(x), x − h(x)) with h vanishing EXACTLY on the
--      codebook; κ = mean. Then κ∘σ = id everywhere (Law A) and
--      copy defect 2|h(x)| = 0 iff x is a codeword.
-- ════════════════════════════════════════════════════════════════

codebook :: [Q]
codebook = [0, 1, 2, 3]

h :: Q -> Q
h x = product [ x - c | c <- codebook ] / 16

sigma :: Q -> (Q, Q)
sigma x = (x + h x, x - h x)

kappa :: (Q, Q) -> Q
kappa (a, b) = (a + b) / 2

copyDefect :: Q -> Q
copyDefect x = let (a, b) = sigma x in abs (a - x) + abs (b - x)

-- ════════════════════════════════════════════════════════════════
-- § 5. Gates
-- ════════════════════════════════════════════════════════════════

expectedDist :: [(Int, Int)]
expectedDist =
  [ (0,2128), (1,6976), (2,4540), (3,2204), (4,723), (5,204)
  , (6,77), (7,25), (8,4), (9,3), (10,6), (11,2), (14,1), (15,1) ]

expectedDivergers :: [String]
expectedDivergers = [ "s[s][s][s[s]][s][s]", "s[s[s]][s][s][s][s]" ]

gate :: String -> Bool -> IO Bool
gate name ok = do
  putStrLn $ "  " ++ (if ok then "✓" else "✗") ++ " " ++ name
  pure ok

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " SKGeneCalculus: S,K genes on the 2×2×2 ↔ 1 octave"
  putStrLn " S = expansion (σ, copy+differentiate)  K = contraction (κ)"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  -- SK1: pool size
  g1 <- gate "SK1  |SK₇| = Catalan(6)·2⁷ = 16,896"
      $ length pool == 16896
        && 16896 == fromInteger (catalan 6) * 2 ^ (7 :: Int)

  -- SK2: pinned halting distribution + longest halter
  let maxT     = maximum [ t | (_, Halted t, _) <- runs ]
      champs   = [ g | (g, Halted t, _) <- runs, t == maxT ]
  g2 <- gate "SK2  halting distribution pinned; t_max = 15 by s[s[s[s]]][s][s][s]"
      $ haltDist == expectedDist
        && maxT == 15
        && map show champs == ["s[s[s[s]]][s][s][s]"]

  -- SK3: the two divergers, both pure S
  g3 <- gate "SK3  divergers = the two pure-S terms (Wolfram's pair)"
      $ sortOn id (map show divergers) == sortOn id expectedDivergers
        && all pureS divergers

  -- SK4: exact size dynamics on every event of every trajectory
  let evOK (ev, before, after) =
        size after - size before == delta ev
        && case ev of KEv dy -> dy >= 2       -- strict contraction
                      SEv dz -> dz >= 0       -- expansion (≥ 0)
      bookOK (g, _, evs) =
        case evs of
          [] -> True
          _  -> let (_, _, final) = last evs
                in size final - size g == sum (map (\(e,_,_) -> delta e) evs)
  g4 <- gate "SK4  Δ_K = −(|y|+1) ≤ −2, Δ_S = |z|−1 ≥ 0, bookkeeping Σ exact"
      $ all (\(_, _, evs) -> all evOK evs) runs
        && all bookOK runs

  -- SK5: UNROLL = 16 is derived (cap 16 ≡ cap 1000)
  let classify cap = [ case fateAt cap g of Halted _ -> True; _ -> False
                     | g <- pool ]
  g5 <- gate "SK5  UNROLL = 16 derived: classification at cap 16 ≡ cap 1000"
      $ classify unroll == [ case f of Halted _ -> True; _ -> False
                           | (_, f, _) <- runs ]

  -- SK6: Haar octave exact on ℚ
  let xs      = [ 5 % 7, -3 % 2, 22 % 9 ]
      blockT  = zip corners [ 1%2, 3, -5%4, 7%8, 0, 2%3, -1, 9%5 ]
      analysis b = ( dc b, [ (w, detail w b) | w <- corners, w /= (0,0,0) ] )
      roundtrip b = let (a, ds) = analysis b in reconstruct a ds
      ehat b  = expand0 (dc b)
      orthoOK = and [ sum [ chi w e * chi w' e | e <- corners ]
                        == (if w == w' then 8 else 0)
                    | w <- corners, w' <- corners ]
      bands   = [ length [ w | w <- corners, w /= (0,0,0), weight w == k ]
                | k <- [1,2,3] ]
  g6 <- gate "SK6  Haar: K̂∘Ŝ=id, ê²=ê, ⟨χ_w,χ_w'⟩=8δ, bands 3:3:1"
      $ all (\x -> dc (expand0 x) == x) xs                    -- K̂∘Ŝ = id
        && sortOn fst (roundtrip blockT) == sortOn fst blockT -- synthesis exact
        && ehat (ehat blockT) == ehat blockT                  -- ê idempotent
        && orthoOK
        && bands == [3, 3, 1]

  -- SK7: Law A survives ARBITRARY detail generators
  let gens = [ \_ x -> x * x                                  -- quadratic
             , \w x -> fromIntegral (weight w) * x - 1 % 3    -- band-linear
             , \w x -> chi w (1,1,0) * (x + 2)                -- signed affine
             ]
  g7 <- gate "SK7  DC(Ŝ_g x) = x for arbitrary g_w — Law A by construction"
      $ and [ dc (expandWith g x) == x | g <- gens, x <- xs ]

  -- SK8: palette = classical basis (toy): copy exact iff codeword
  let offPoints = [ 1%2, 3%2, 5%2, -1, 4 ]
  g8 <- gate "SK8  copy defect = 0 iff codeword; κ∘σ = id everywhere"
      $ all (\c -> copyDefect c == 0 && sigma c == (c, c)
                   && kappa (c, c) == c) codebook
        && all (\x -> copyDefect x /= 0) offPoints
        && all (\x -> kappa (sigma x) == x) (codebook ++ offPoints ++ xs)

  -- SK9: fixed-point law — halted finals are normal forms
  let finals = [ if null evs then g else (\(_,_,t) -> t) (last evs)
               | (g, Halted _, evs) <- runs ]
  g9 <- gate "SK9  step ≡ id on all 16,894 halted finals (safe idle in unroll)"
      $ all (\t -> stepE t == Nothing) finals

  -- SK10: phase partition ORDER / BOUNDARY / CHAOS
  let order    = length [ () | (_, Halted t, _) <- runs, t <= 2 ]
      boundary = length [ () | (_, Halted t, _) <- runs, t >= 3 ]
      chaos    = length divergers
  g10 <- gate "SK10 phases: ORDER 13,644 + BOUNDARY 3,250 + CHAOS 2 = 16,896"
      $ order == 13644 && boundary == 3250 && chaos == 2
        && order + boundary + chaos == 16896

  putStrLn ""
  let results = [g1,g2,g3,g4,g5,g6,g7,g8,g9,g10]
  putStrLn $ "  " ++ show (length (filter id results)) ++ "/"
           ++ show (length results) ++ " gates green"
  putStrLn ""
  putStrLn "  Train two maps, not 16,896 genes: σ expands, κ contracts;"
  putStrLn "  the octave is their cube, the gene is their composition."
  if and results then pure () else error "SKGeneCalculus: gate failure"
