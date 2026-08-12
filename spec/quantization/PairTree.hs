{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- PairTree: 256 colors as pairings of pairings
--
-- Daniel's ruling (2026-08-12): "pair pairs so that the 8:1 ratio
-- in all of the scales is grounded in latent algos." Design doc:
-- docs/pair-tree-palette.md.
--
-- The 8-bit index IS the structure: sibling maps s_ℓ(i) = i XOR 2^ℓ
-- are eight commuting involutions; their total composition is the
-- DYAD involution σ(i) = 255 − i (pairing pairs all the way up IS
-- the involution the table has carried since DY1); any THREE levels
-- compose to the 2×2×2 = 8:1 atom; and the binomial ladder
-- [1,1,2,4,8,16,32,64] is the balanced tree's growth rings — the
-- "strict binomial distribution" preserved as the tree's shadow.
--
--   PT1  the pairing algebra: involutions, commuting, σ = total
--   PT2  strata: bit-triples are 8:1 exactly; 256 → 32 → 4
--   PT3  pooling exactness: octet mean = pair-of-pair means, exact
--   PT4  the latent split: eigen-split at the mean, mass conserved,
--        balanced splits reproduce the binomial rings
--   PT5  the prefix law: truncated index = coarser-level nearest
--        (rung alignment), on separable dyadic fixtures
--   PT6  σ-compatibility: complement maps siblings to siblings at
--        every level — figure tree ≡ ground tree
-- ════════════════════════════════════════════════════════════════

module PairTree where

import Data.Bits (xor, complement, (.&.), shiftR)
import Data.List (minimumBy, nub, sort)
import Data.Ord (comparing)
import Data.Ratio ((%))

-- ════════════════════════════════════════════════════════════════
-- § 1. THE PAIRING ALGEBRA
-- ════════════════════════════════════════════════════════════════

-- | Level-ℓ sibling: flip one bit. Pairs (ℓ=0), pairs of pairs
--   (ℓ=1), and so on — every scale of pairing is one level.
sib :: Int -> Int -> Int
sib l i = i `xor` (2 ^ l)

-- | The DYAD involution (DY1): σ(i) = 255 − i.
sigma :: Int -> Int
sigma i = 255 - i

allIx :: [Int]
allIx = [0 .. 255]

levels :: [Int]
levels = [0 .. 7]

-- | The canonical strata: bit-triples LSB-first, 4 anchors on top.
strata :: [[Int]]
strata = [[0, 1, 2], [3, 4, 5], [6, 7]]

-- | Class of i at a stratum boundary: drop the given levels.
classAbove :: [Int] -> Int -> Int
classAbove ls i = foldl (\v l -> v .&. complement (2 ^ l)) i ls

-- ════════════════════════════════════════════════════════════════
-- § 2. THE LATENT SPLIT (v1 exact algorithm, 1-D exact model)
--
-- A node = weighted samples; split along the node's own principal
-- axis at its weighted mean; recurse. Here the law is pinned on the
-- exact 1-D model (Rational): the full OKLab version differs only
-- by projecting on the local top eigenvector first (RL4's n ∝ √λ
-- satisfied locally: each split gives both children equal codeword
-- budget, lawful when the split balances variance mass).
-- ════════════════════════════════════════════════════════════════

type W = (Rational, Rational)   -- (position, mass)

wMean :: [W] -> Rational
wMean ws = sum [ p * m | (p, m) <- ws ] / sum (map snd ws)

wMass :: [W] -> Rational
wMass = sum . map snd

-- | One split at the weighted mean (ties → left, deterministic).
splitAtMean :: [W] -> ([W], [W])
splitAtMean ws = let mu = wMean ws
                 in ( [ w | w@(p, _) <- ws, p <= mu ]
                    , [ w | w@(p, _) <- ws, p >  mu ] )

-- | Recursive split to depth d: the leaf list, left-to-right.
splitTree :: Int -> [W] -> [[W]]
splitTree 0 ws = [ws]
splitTree d ws
  | length ws <= 1 = [ws]                    -- degenerate: cannot split
  | null l || null r = [ws]                  -- collapsed mass: stop
  | otherwise = splitTree (d - 1) l ++ splitTree (d - 1) r
  where (l, r) = splitAtMean ws

-- | Binomial growth rings of a balanced tree: new nodes per
--   generation, level 0 = the centroid.
rings :: [Int]
rings = 1 : [ 2 ^ (g - 1) | g <- [1 .. 7 :: Int] ]

-- ════════════════════════════════════════════════════════════════
-- § 3. THE PREFIX LAW FIXTURE (separable dyadic positions)
--
-- Leaves at p(j) = Σ_k bit_k(j)·3^k: every level's separation
-- dominates everything below it, so nearest-leaf and nearest-
-- coarse-centroid agree on prefixes — the lawful regime the
-- ANE descent (P4) and the rung alignment (P2) live in.
-- ════════════════════════════════════════════════════════════════

leafPos :: Int -> Int -> Rational
leafPos bits j = sum [ fromIntegral ((j `shiftR` k) .&. 1) * 3 ^ k
                     | k <- [0 .. bits - 1] ]

-- | Level-ℓ centroid of a class c (low ℓ bits zero): mean of leaves.
levelPos :: Int -> Int -> Int -> Rational
levelPos bits l c =
  let members = [ c + r | r <- [0 .. 2 ^ l - 1] ]
  in sum (map (leafPos bits) members) / fromIntegral (length members)

nearestBy :: [(Int, Rational)] -> Rational -> Int
nearestBy cands x = fst (minimumBy (comparing (\(_, p) -> abs (p - x))) cands)

-- ════════════════════════════════════════════════════════════════
-- § 3b. THE ANALYTIC TREE (v1 solver law — the Swift port's law)
--
-- The provenance law (DYAD STATS: the GIF's 13 numbers regenerate
-- every palette byte) demands the tree be a CLOSED-FORM function of
-- (centroid, covariance) — so the splits act on the FITTED GAUSSIAN,
-- not the samples. Splitting N(μ, Σ) at its mean along eigenaxis u
-- (eigenvalue λ) gives two half-Gaussians with EXACT moments:
--
--   child mean      μ ± √λ · √(2/π) · u     (half-normal mean)
--   child variance  λ · (1 − 2/π) on u; other axes UNCHANGED
--                   (eigenbasis ⇒ independence ⇒ no rotation, ever)
--
-- √(2/π) and (1 − 2/π) are moments of the Gaussian — not tuned.
-- The basis never rotates, so the whole 7-generation tree is exact
-- arithmetic in the initial eigenbasis. Split axis = argmax variance
-- (tie → lowest axis index): larger λ gets split more — RL4's
-- allocation spirit, node by node.
-- ════════════════════════════════════════════════════════════════

halfMeanC, halfVarC :: Double
halfMeanC = sqrt (2 / pi)     -- E[|Z|] for Z ~ N(0,1)
halfVarC  = 1 - 2 / pi        -- Var[|Z|]

-- | Node state: mean (3 coords in the eigenbasis) and per-axis
--   variances. The eigenbasis is fixed at the root.
data GNode = GNode { gMean :: [Double], gVar :: [Double] }
  deriving (Eq, Show)

-- | Split axis = argmax variance, ties → LOWEST index (deterministic).
splitAxis :: GNode -> Int
splitAxis n = fst (foldl pick (0, head vs) (zip [1 ..] (tail vs)))
  where
    vs = gVar n
    pick (bi, bv) (i, v) = if v > bv then (i, v) else (bi, bv)

-- | The analytic half-split along the argmax axis.
splitG :: GNode -> (GNode, GNode)
splitG n = (child (-1), child 1)
  where
    a = splitAxis n
    v = gVar n !! a
    off = sqrt v * halfMeanC
    child s = GNode
      { gMean = [ if i == a then m + fromIntegral (s :: Int) * off else m
                | (i, m) <- zip [0 ..] (gMean n) ]
      , gVar  = [ if i == a then v * halfVarC else w
                | (i, w) <- zip [0 ..] (gVar n) ] }

-- | 7 generations → 128 leaves, left (−) first: leaf index bits are
--   generation choices, FIRST generation = MSB (bit 6) — so low
--   bits are the finest pairings and prefix truncation (PT5) pools
--   depth-first subtrees.
gLeaves :: Int -> GNode -> [GNode]
gLeaves 0 n = [n]
gLeaves d n = let (l, r) = splitG n in gLeaves (d - 1) l ++ gLeaves (d - 1) r

-- | Analytic node mean at depth d for a leaf-index prefix: rebuild
--   by descending d generations.
gNodeAt :: Int -> [Int] -> GNode -> GNode
gNodeAt _ [] n = n
gNodeAt d (b : bs) n =
  let (l, r) = splitG n in gNodeAt (d - 1) bs (if b == 0 then l else r)

-- ════════════════════════════════════════════════════════════════
-- § 4. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (PT1) The pairing algebra: every level map is an involution, the
--       maps commute, and the composition of ALL EIGHT is exactly
--       the DYAD involution σ(i) = 255 − i. Pairing pairs all the
--       way up is the table's own law.
axiom_PT1 :: Bool
axiom_PT1 =
     and [ sib l (sib l i) == i | l <- levels, i <- allIx ]
  && and [ sib l (sib m i) == sib m (sib l i)
         | l <- levels, m <- levels, i <- allIx ]
  && and [ foldr sib i levels == sigma i | i <- allIx ]
  && and [ sigma (sigma i) == i && sigma i >= 0 && sigma i <= 255 | i <- allIx ]

-- (PT2) Strata: the bit-triple quotients are EXACTLY the atom —
--       256 → 32 (8:1) → 4 (8:1) — and on the 7-bit figure half
--       128 → 16 → 2. Every class at every stratum has exactly the
--       atom's population.
axiom_PT2 :: Bool
axiom_PT2 =
     length c1 == 32 && length c2 == 4
  && (256 % 32 == 8) && (32 % 4 == 8)
  && all (\c -> length (filter ((== c) . classAbove (head strata)) allIx) == 8) c1
  && all (\c -> length (filter ((== c) . classAbove (concat (take 2 strata))) allIx) == 64) c2
  && length f1 == 16 && length f2 == 2
  where
    c1 = nub (map (classAbove (head strata)) allIx)
    c2 = nub (map (classAbove (concat (take 2 strata))) allIx)
    figs = [0 .. 127]
    f1 = nub (map (classAbove [0, 1, 2]) figs)
    f2 = nub (map (classAbove [0, 1, 2, 3, 4, 5]) figs)

-- (PT3) Pooling exactness: the octet mean equals the pair-of-pair-
--       of-pair means under ANY association order (weighted means
--       are associative given mass bookkeeping) — the palette twin
--       of the 2×2×2 ↔ 1 spacetime pool, exact in Rational.
axiom_PT3 :: Bool
axiom_PT3 = all ok probes
  where
    probes = [ [ ((fromIntegral k * 7 + fromIntegral s) % 3, (fromIntegral k + 1) % 2)
               | k <- [0 .. 7 :: Int] ]
             | s <- [1 .. 5 :: Int] ]
    pairUp xs = [ merge a b | (a, b) <- zip (evens xs) (odds xs) ]
    evens (x : _ : r) = x : evens r; evens [x] = [x]; evens [] = []
    odds (_ : y : r) = y : odds r; odds _ = []
    merge (p1, m1) (p2, m2) = ((p1 * m1 + p2 * m2) / (m1 + m2), m1 + m2)
    ok ws =
      let flatMean = wMean ws
          treeMean = fst (head (pairUp (pairUp (pairUp ws))))
      in treeMean == flatMean && wMass ws == snd (head (pairUp (pairUp (pairUp ws))))

-- (PT4) The latent split: mass is conserved at every generation;
--       symmetric data splits balanced, reproducing the binomial
--       rings (Σ rings = 128 = the figure count; ring g = 2^(g−1));
--       and the split point is the node's OWN mean — no constant.
axiom_PT4 :: Bool
axiom_PT4 = massConserved && balancedOnSymmetric && ringsLaw
  where
    sym = [ (fromIntegral k, 1) | k <- [0 .. 127 :: Int] ]
    leavesAt d = splitTree d sym
    massConserved = all (\d -> sum (map wMass (leavesAt d)) == wMass sym) [1 .. 7]
    balancedOnSymmetric = all (\d -> map length (leavesAt d)
                                       == replicate (2 ^ d) (128 `div` 2 ^ d)) [1 .. 7]
    ringsLaw = sum rings == 128
            && rings == [1, 1, 2, 4, 8, 16, 32, 64]

-- (PT5) The prefix law (rung alignment): on the separable dyadic
--       fixture, truncating ℓ bits of the nearest-leaf index equals
--       the nearest level-ℓ centroid — quantize-coarse ≡ coarsen-
--       quantized. This is the law P2 (chaos blur at the 32-level)
--       and P4 (ANE descent) rely on; near-ties outside separation
--       are XP2's territory.
axiom_PT5 :: Bool
axiom_PT5 = and
  [ classAbove [0 .. l - 1] (nearestBy leaves x) == nearestBy (lvl l) x
  | l <- [1 .. bits], x <- probeGrid ]
  where
    bits = 5   -- 32-leaf fixture: full law, tractable exactly
    leaves = [ (j, leafPos bits j) | j <- [0 .. 2 ^ bits - 1] ]
    lvl l = [ (c, levelPos bits l c)
            | c <- nub (map (classAbove [0 .. l - 1]) [0 .. 2 ^ bits - 1]) ]
    probeGrid = [ fromIntegral n % 4 | n <- [0 .. 4 * 121 :: Int] ]

-- (PT7) ANALYTIC CONSERVATION: at every node the children's mean
--       averages back to the parent EXACTLY, and the law of total
--       variance closes on the split axis — within-child variance
--       (1−2/π)λ plus between-child variance (2/π)λ equals λ. The
--       tree redistributes the Gaussian; it never invents mass.
axiom_PT7 :: Bool
axiom_PT7 = all ok probeNodes
  where
    probeNodes = [ GNode [0.6, 0.05, -0.02] [v1, v2, v3]
                 | (v1, v2, v3) <- [ (0.02, 0.008, 0.001)
                                   , (0.001, 0.001, 0.001)
                                   , (0.09, 0.0, 0.0)
                                   , (0.0, 0.0, 0.0) ] ]
    close a b = abs (a - b) <= 1e-12
    ok n =
      let (l, r) = splitG n
          a = splitAxis n
          v = gVar n !! a
          off = sqrt v * halfMeanC
      in and (zipWith close (gMean n)
                (zipWith (\x y -> (x + y) / 2) (gMean l) (gMean r)))
      && close (gVar l !! a + off * off) v      -- within + between = total
      && gVar l == gVar r
      && and [ gVar l !! i == gVar n !! i | i <- [0 .. 2], i /= a ]

-- (PT8) ALLOCATION BY VARIANCE: over the 7 generations the argmax
--       rule never splits a smaller-variance axis more often than a
--       larger one (monotone allocation — RL4's spirit node-wise),
--       the recursion is deterministic, and a degenerate (zero-
--       variance) node yields 128 coincident leaves — the collapsed
--       capture is lawful, not special-cased.
axiom_PT8 :: Bool
axiom_PT8 = monotone && deterministic && degenerate
  where
    -- count along the leftmost path: every path sees the same
    -- deterministic rule; monotonicity is checked on its tally
    pathAxes _ 0 = []
    pathAxes n d = let a = splitAxis n; (l, _) = splitG n
                   in a : pathAxes l (d - 1 :: Int)
    tally axes = [ length (filter (== i) axes) | i <- [0 .. 2] ]
    monotone = and
      [ and [ (vs !! i >= vs !! j) <= (t !! i >= t !! j)
            | i <- [0 .. 2], j <- [0 .. 2] ]
      | vs <- [ [0.04, 0.01, 0.0025], [0.09, 0.0001, 0.0001] ]
      , let t = tally (pathAxes (GNode [0, 0, 0] vs) 7) ]
    deterministic =
      gLeaves 7 (GNode [0.5, 0, 0] [0.02, 0.01, 0.005])
        == gLeaves 7 (GNode [0.5, 0, 0] [0.02, 0.01, 0.005])
    degenerate =
      let ls = gLeaves 7 (GNode [0.3, 0.1, -0.1] [0, 0, 0])
      in length ls == 128 && all (== head ls) ls

-- (PT9) LEAF/NODE COHERENCE: the depth-4 node reached by a leaf's
--       3-generation prefix has EXACTLY the mean of its 8-leaf
--       octet (pooling three levels = the palette's own 2×2×2 ↔ 1),
--       and the leaf count and prefix-class sizes match PT2's
--       figure strata (128 = 16 octets of 8).
axiom_PT9 :: Bool
axiom_PT9 = all ok roots && sizes
  where
    roots = [ GNode [0.62, 0.03, 0.01] [0.03, 0.012, 0.002]
            , GNode [0.4, -0.02, 0.05] [0.001, 0.02, 0.02] ]
    close a b = abs (a - b) <= 1e-9
    ok root =
      let ls = gLeaves 7 root
          octet c = [ gMean (ls !! (c * 8 + r)) | r <- [0 .. 7] ]
          flatMean ms = map (/ fromIntegral (length ms)) (foldr1 (zipWith (+)) ms)
          nodeMean c =
            let bits = [ (c `shiftR` k) .&. 1 | k <- [3, 2, 1, 0] ]
            in gMean (gNodeAt 4 bits root)
      in and [ and (zipWith close (flatMean (octet c)) (nodeMean c))
             | c <- [0 .. 15] ]
    sizes = length (gLeaves 7 (head roots)) == 128
         && (128 :: Int) == 16 * 8

-- (PT6) σ-compatibility: the complement maps level-ℓ siblings to
--       level-ℓ siblings — the ground half inherits the figure
--       half's tree exactly; and σ exchanges the two 7-bit halves.
axiom_PT6 :: Bool
axiom_PT6 =
     and [ sigma (sib l i) == sib l (sigma i) | l <- levels, i <- allIx ]
  && and [ (i < 128) == (sigma i >= 128) | i <- allIx ]
  && sort (map sigma [0 .. 127]) == [128 .. 255]

-- ════════════════════════════════════════════════════════════════
-- § 5. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " PairTree: 256 colors as pairings of pairings"
  putStrLn " σ = the total pairing; bit-triples = the 8:1 atom;"
  putStrLn " splits are latent (eigen/mean), not designed; the"
  putStrLn " binomial ladder survives as the tree's growth rings"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "PT1 algebra: 8 commuting involutions, total = σ = 255−i"   [axiom_PT1]
  check "PT2 strata: triples are 8:1 exact — 256→32→4, 128→16→2"    [axiom_PT2]
  check "PT3 pooling: octet mean = pair-of-pair means, exact"       [axiom_PT3]
  check "PT4 latent split: mass conserved, binomial rings = shadow" [axiom_PT4]
  check "PT5 prefix law: truncate index ≡ coarsen palette (fixture)" [axiom_PT5]
  check "PT6 σ-compatible: complement preserves every pairing level" [axiom_PT6]
  check "PT7 analytic split: means average back, variance closes"    [axiom_PT7]
  check "PT8 allocation: argmax-λ monotone, deterministic, total"    [axiom_PT8]
  check "PT9 coherence: depth-4 node mean = octet mean (2×2×2↔1)"    [axiom_PT9]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  Pair pairs: the palette is a dyadic tree whose every"
  putStrLn "  third level is the 2×2×2 atom, aligned with the cube's"
  putStrLn "  rungs. Splits come from the capture's own latent axes"
  putStrLn "  (and next, a model distilled from that algorithm — the"
  putStrLn "  capture-assist NN). The involution was the top of the"
  putStrLn "  tree all along."
  putStrLn "══════════════════════════════════════════════════════════"

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
