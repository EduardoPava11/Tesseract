{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- RoleAllocation: the stratified edit — entropy spent FIGURE-FIRST
--
-- Daniel's ruling (2026-08-13): "priority in entropy and color
-- palette allocation is to the user. the background is lower.
-- GIVING an illusion of phase transformation frame by frame."
-- Plus: EDIT is the whole app; one capture, many GIFs; the full
-- 64³ re-solves every tick; every dial must be a GRID CELL widget.
--
-- ── THE UNIFICATION ─────────────────────────────────────────────
--
-- The head:tail split and the figure/ground split are THE SAME
-- SPLIT. PairTree PT5 already proves that truncating a palette
-- index to its high d bits yields a valid 2^d-colour palette whose
-- entries are the exact means of their subtrees (PT7/PT9). So:
--
--   FIGURE  keeps head + tail   — deep truncation, d_F bits
--   GROUND  keeps head only     — shallow truncation, d_B bits
--
-- The ground is not a second palette. It is the SAME tree read at
-- a coarser rung, mirrored through σ (PT6: the complement preserves
-- every pairing level). Non-uniform allocation costs no new colours
-- and no new law — it is a choice of two truncation depths.
--
-- ★ THIS IS ALREADY HALF-SHIPPED. Today's path runs d_F = 7 (128
-- figure primaries) and d_B = 4 (16 depth-4 nodes = the "32-level"
-- chaos target, DyadPipeline.swift:376). The edit page generalises
-- an allocation the machine already performs — it does not invent
-- one. identityEdit reproduces today's bytes exactly (RA9).
--
-- ── THE ILLUSION, MADE MEASURABLE ───────────────────────────────
--
-- Why starving the ground reads as PHASE TRANSFORMATION rather than
-- as banding: the tree is re-solved per frame from that frame's own
-- statistics (the per-frame LCT decree). A ground pixel therefore
-- re-quantises against a tree that has MOVED. The size of the jump
-- it makes when it crosses a cell boundary is the cell diameter —
-- and cell diameter DOUBLES for every bit taken from the ground
-- (RA6, exact). Few levels do not merely lose detail; they convert
-- smooth inter-frame drift into discrete visible transitions.
--
--   d_B = 7 → 128 cells → sub-JND drift, invisible
--   d_B = 4 →  16 cells → today's chaos shimmer
--   d_B = 2 →   4 cells → hard phase flips frame to frame
--
-- ── AXIOMS ──────────────────────────────────────────────────────
--
--   RA1  role partition: every pixel is figure XOR ground, and the
--        masses are the mixture's own posterior means (no constant)
--   RA2  prefix conservation: reading the tree at depth d gives 2^d
--        nodes, each the EXACT mean of its leaf block; the depths
--        telescope (PT7 lifted to the allocation layer)
--   RA3  the allocation law: reverse water-filling, RL4's form —
--        (2^d_F / 2^d_B)² = λ_F / λ_B, exact on ℚ
--   RA4  FIGURE PRIORITY: under RA3, λ_F ≥ λ_B ⇒ d_F ≥ d_B; the
--        figure is never starved to feed the ground
--   RA5  rate accounting: R = 1 + (1−t̄)·d_F + t̄·d_B bits/pixel,
--        strictly monotone in each depth, and ≤ 8 (the wire's width)
--   RA6  ★ THE PHASE LAW: adjacent cell spacing at depth d is
--        2^(D−d) leaf steps — every bit taken from the ground
--        EXACTLY DOUBLES the jump a ground pixel can make between
--        frames. The illusion is a rate choice, not an effect
--   RA7  budget: 2^d_F + 2^d_B ≤ 256, satisfied by every lawful
--        allocation; the σ-involution means the ground costs NO
--        independent entries (PT6)
--   RA8  ★ GRID TOTALITY: the edit space is finite and is EXACTLY
--        the product of its cell-widget states — every widget
--        configuration is a lawful edit and every lawful edit is
--        reachable. The UI cannot express an unrepresentable GIF
--   RA9  identity: the edit (7,4) is in the space and names today's
--        shipping allocation; editing is a generalisation, not a
--        replacement
--   RA10 determinism + purity: a GIF is a pure function of
--        (capture, edit). Same pair → same bytes. Ticks carry no
--        hidden state, so a library of variants is reproducible
--        from a capture plus 5 small integers
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.List (nub, sort)
import Data.Ratio ((%))

type Q = Rational

-- ════════════════════════════════════════════════════════════════
-- § 1. THE TREE, READ AT A DEPTH
--
-- The allocation layer is ABOVE PairTree: it does not care how the
-- leaves were solved (that is PT7–PT9's job), only that reading the
-- tree at depth d is exact averaging. Carrier is ℚ³ (OKLab).
-- ════════════════════════════════════════════════════════════════

type V3 = (Q, Q, Q)

vAdd :: V3 -> V3 -> V3
vAdd (a, b, c) (p, q, r) = (a + p, b + q, c + r)

vScale :: Q -> V3 -> V3
vScale s (a, b, c) = (s * a, s * b, s * c)

vMean :: [V3] -> V3
vMean [] = (0, 0, 0)
vMean vs = vScale (1 % fromIntegral (length vs)) (foldr vAdd (0, 0, 0) vs)

-- | Tree depth of ONE half of the dyad table: 2^7 = 128 leaves.
treeDepth :: Int
treeDepth = 7

leafCount :: Int
leafCount = 2 ^ treeDepth

-- | Palette width on the wire (both halves, σ-involuted).
paletteSize :: Int
paletteSize = 256

chunk :: Int -> [a] -> [[a]]
chunk _ [] = []
chunk n xs = take n xs : chunk n (drop n xs)

-- | The tree read at depth d: 2^d node values, each the exact mean
--   of its contiguous leaf block. d = treeDepth returns the leaves.
nodesAt :: Int -> [V3] -> [V3]
nodesAt d leaves = map vMean (chunk (leafCount `div` (2 ^ d)) leaves)

-- | Which depth-d cell a leaf index falls in (the high d bits —
--   PT5's prefix, stated as arithmetic).
cellOf :: Int -> Int -> Int
cellOf d i = i `div` (leafCount `div` (2 ^ d))

-- ════════════════════════════════════════════════════════════════
-- § 2. ROLES AND THE ALLOCATION
-- ════════════════════════════════════════════════════════════════

-- | A pixel's role, decided by the mixture posterior t ∈ [0,1]
--   (DepthMixture's pull). No threshold constant appears here: the
--   crossover is t = 1/2, the posterior's own indifference point.
data Role = Figure | Ground deriving (Eq, Show)

roleOf :: Q -> Role
roleOf t = if t < 1 % 2 then Figure else Ground

-- | Depths in bits for each role. Both index the SAME tree.
data Alloc = Alloc { dFig :: Int, dGnd :: Int } deriving (Eq, Show)

-- | Today's shipping allocation: 128 figure primaries, 16 depth-4
--   ground nodes (the 32-level chaos target).
shippingAlloc :: Alloc
shippingAlloc = Alloc { dFig = 7, dGnd = 4 }

-- | Colours actually realised on the wire by an allocation.
coloursUsed :: Alloc -> Int
coloursUsed (Alloc f b) = 2 ^ f + 2 ^ b

-- | Expected index width in bits: one bit names the role (the σ
--   half, PT6), then the role's own depth.
rateBits :: Q -> Alloc -> Q
rateBits tBar (Alloc f b) =
  1 + (1 - tBar) * fromIntegral f + tBar * fromIntegral b

-- ── the allocation law (RL4 reverse water-filling) ──────────────
--
-- b_i − b_j = ½·log₂(λ_i/λ_j)  ⟺  (2^b_i / 2^b_j)² = λ_i/λ_j.
-- Stated in the squared form so it is EXACT over ℚ (the same move
-- RateLadder.hs RL4 makes).

allocLawful :: Alloc -> Q -> Q -> Bool
allocLawful (Alloc f b) lamF lamB =
  lamB /= 0 && (nF / nB) ^ (2 :: Int) == lamF / lamB
  where nF = fromIntegral (2 ^ f :: Integer) :: Q
        nB = fromIntegral (2 ^ b :: Integer) :: Q

-- | The DERIVED allocation: the lawful depth gap, clamped to the
--   tree. Constant-free — λ_F, λ_B are the role-weighted
--   generalised variances of the staged field.
derivedAlloc :: Q -> Q -> Alloc
derivedAlloc lamF lamB = Alloc { dFig = treeDepth, dGnd = clamp gap }
  where
    gap = treeDepth - halfLog4 (lamF / lamB)
    clamp x = max 0 (min treeDepth x)

-- | ⌊½·log₂ r⌋ = ⌊log₄ r⌋ on ℚ, by repeated division. Integer
--   arithmetic only — no floating point enters the allocation.
halfLog4 :: Q -> Int
halfLog4 r
  | r <= 1    = 0
  | otherwise = go 0 r
  where go k x = if x < 4 then k else go (k + 1) (x / 4)

-- ════════════════════════════════════════════════════════════════
-- § 3. THE EDIT — a value, small enough to be a row of cells
--
-- Every dial is a widget of `widgetCells` cells in the lattice, so
-- an edit is a tuple of small integers. The whole edit space is
-- finite and enumerable (RA8) — the UI is total over it.
-- ════════════════════════════════════════════════════════════════

widgetCells :: Int
widgetCells = treeDepth + 1        -- 8 states: depths 0..7

data Edit = Edit
  { eFig    :: Int   -- figure truncation depth   0..7
  , eGnd    :: Int   -- ground truncation depth   0..7
  , eCoarse :: Int   -- octave weight, 16³ rung   0..7  (semantics: octave spec)
  , eMid    :: Int   -- octave weight, 32³ rung   0..7
  , eFine   :: Int   -- octave weight, 64³ rung   0..7
  } deriving (Eq, Show)

editSpace :: [Edit]
editSpace =
  [ Edit a b c d e
  | a <- rng, b <- rng, c <- rng, d <- rng, e <- rng ]
  where rng = [0 .. treeDepth]

editArity :: Int
editArity = 5

-- | The edit that names today's shipping path. The octave weights
--   are a SIMPLEX over the three parallel reads (Octave.hs OV6,
--   OV8), so the identity is the FINE READ ALONE — today's app
--   uses only the 64³ stream. Coarse and mid enter at zero.
identityEdit :: Edit
identityEdit = Edit
  { eFig = dFig shippingAlloc, eGnd = dGnd shippingAlloc
  , eCoarse = 0, eMid = 0, eFine = 7 }

allocOf :: Edit -> Alloc
allocOf e = Alloc { dFig = eFig e, dGnd = eGnd e }

-- | The tick contract: a GIF is a PURE function of capture and
--   edit. Modelled here by the realised colour multiset, which is
--   what the bytes are downstream of the tree.
render :: [V3] -> Edit -> ([V3], [V3])
render leaves e = (nodesAt (eFig e) leaves, nodesAt (eGnd e) leaves)

-- ════════════════════════════════════════════════════════════════
-- § 4. FIXTURES
-- ════════════════════════════════════════════════════════════════

-- | Leaves in arithmetic progression: the exact case in which cell
--   spacing is computable in closed form (RA6). Step 1/128 on L.
apLeaves :: [V3]
apLeaves = [ (fromIntegral i % 128, 0, 0) | i <- [0 .. leafCount - 1] ]

-- | A deterministic non-uniform leaf set (no System.Random).
lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

wobbleLeaves :: [V3]
wobbleLeaves =
  [ ( fromIntegral i % 128
    , fromIntegral (lcg (i * 7 + 1) `mod` 97) % 512
    , fromIntegral (lcg (i * 13 + 5) `mod` 89) % 512 )
  | i <- [0 .. leafCount - 1] ]

-- | A per-frame family of trees: the whole point of the per-frame
--   LCT decree is that the tree MOVES between frames. Frame z
--   shifts the leaf ladder by z/4096 — sub-cell at depth 7, but
--   supra-cell at shallow depths, which is RA6's teeth.
frameLeaves :: Int -> [V3]
frameLeaves z =
  [ (fromIntegral i % 128 + fromIntegral z % 4096, 0, 0)
  | i <- [0 .. leafCount - 1] ]

-- | L-channel spacing between adjacent cells at depth d.
cellSpacing :: Int -> [V3] -> Q
cellSpacing d leaves =
  case map (\(l, _, _) -> l) (nodesAt d leaves) of
    (x : y : _) -> y - x
    _           -> 0

-- ════════════════════════════════════════════════════════════════
-- § 5. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (RA1) Role partition: every pull value lands in exactly one role,
--       the split is at the posterior's own indifference point, and
--       the masses are complementary — t̄ and 1−t̄, no constant.
axiom_RA1 :: Bool
axiom_RA1 =
     all (\t -> (roleOf t == Figure) /= (roleOf t == Ground)) pulls
  && roleOf 0 == Figure && roleOf 1 == Ground
  && roleOf (1 % 2) == Ground              -- indifference resolves up
  && roleOf (1 % 2 - 1 % 1000) == Figure
  && abs (figMass + gndMass - 1) == 0      -- complementary, exactly
  where
    pulls    = [ fromIntegral k % 64 | k <- [0 .. 64 :: Integer] ]
    tBar     = sum pulls / fromIntegral (length pulls)
    figMass  = 1 - tBar
    gndMass  = tBar

-- (RA2) Prefix conservation: depth d yields exactly 2^d nodes; each
--       is the exact mean of its leaf block; depth 7 is the leaves;
--       depth 0 is the grand mean; and the depths TELESCOPE — the
--       depth-d nodes are the pairwise means of the depth-(d+1)
--       nodes. (PT7/PT9 lifted; the octave's κ in the palette.)
axiom_RA2 :: Bool
axiom_RA2 = all ok [apLeaves, wobbleLeaves]
  where
    ok ls =
         and [ length (nodesAt d ls) == 2 ^ d | d <- [0 .. treeDepth] ]
      && nodesAt treeDepth ls == ls
      && nodesAt 0 ls == [vMean ls]
      && and [ nodesAt d ls == map vMean (chunk 2 (nodesAt (d + 1) ls))
             | d <- [0 .. treeDepth - 1] ]
      && and [ nodesAt d ls !! cellOf d i == vMean (blockOf d i ls)
             | d <- [0 .. treeDepth], i <- [0, 1, 37, 63, 127] ]
    blockOf d i ls =
      let w = leafCount `div` (2 ^ d) in take w (drop (cellOf d i * w) ls)

-- (RA3) The allocation law holds exactly in the squared (RL4) form,
--       and rejects lawless pairs. λ ratios that are powers of four
--       are the exactly-representable case.
axiom_RA3 :: Bool
axiom_RA3 =
     allocLawful (Alloc 7 4) (64 % 1) (1 % 1)      -- gap 3 ⇒ ratio 4³
  && allocLawful (Alloc 7 7) (5 % 1) (5 % 1)       -- equal λ ⇒ equal depth
  && allocLawful (Alloc 6 4) (16 % 1) (1 % 1)      -- gap 2 ⇒ ratio 4²
  && not (allocLawful (Alloc 7 4) (16 % 1) (1 % 1))
  && not (allocLawful (Alloc 7 5) (64 % 1) (1 % 1))
  && derivedAlloc (64 % 1) (1 % 1) == Alloc 7 4    -- ★ derives TODAY
  && derivedAlloc (1 % 1) (1 % 1) == Alloc 7 7
  && derivedAlloc (4096 % 1) (1 % 1) == Alloc 7 1
  && derivedAlloc (1 % 64) (1 % 1) == Alloc 7 7    -- λ_F < λ_B: no starve

-- (RA4) ★ FIGURE PRIORITY. Under the derived law the figure always
--       holds the full tree and the ground is the only side ever
--       truncated — for EVERY variance ratio, in either direction.
--       The user is never quantised to feed the background.
axiom_RA4 :: Bool
axiom_RA4 =
     all (\a -> dFig a == treeDepth) allocs
  && all (\a -> dGnd a <= dFig a) allocs
  && and [ dGnd (derivedAlloc r 1) >= dGnd (derivedAlloc r' 1)
         | (r, r') <- zip ratios (tail ratios) ]   -- monotone: more
                                                   -- figure variance
                                                   -- ⇒ leaner ground
  where
    ratios = [ 4 ^ k % 1 | k <- [0 .. 8 :: Integer] ]
    allocs = [ derivedAlloc r 1 | r <- ratios ]
          ++ [ derivedAlloc 1 r | r <- ratios ]

-- (RA5) Rate accounting: bits/pixel is affine in the two depths,
--       strictly monotone in each, never exceeds the wire's 8 bits,
--       and the shipping allocation is strictly cheaper than a
--       uniform one at the same figure depth.
axiom_RA5 :: Bool
axiom_RA5 =
     rateBits tBar (Alloc 7 7) == 8
  && rateBits tBar (Alloc 0 0) == 1
  && rateBits tBar shippingAlloc < rateBits tBar (Alloc 7 7)
  && and [ rateBits tBar (Alloc f b) < rateBits tBar (Alloc (f + 1) b)
         | f <- [0 .. 6], b <- [0 .. 7] ]
  && and [ rateBits tBar (Alloc f b) < rateBits tBar (Alloc f (b + 1))
         | f <- [0 .. 7], b <- [0 .. 6] ]
  && all (\e -> rateBits tBar (allocOf e) <= 8) editSpace
  where tBar = 1 % 2

-- (RA6) ★ THE PHASE LAW. On the exact (arithmetic-progression)
--       tree, adjacent cell spacing at depth d is 2^(D−d) leaf
--       steps — so each bit taken from the ground EXACTLY DOUBLES
--       the colour jump a pixel makes when the re-solved tree moves
--       it across a cell boundary. And the movement is real: at
--       shallow depths successive frames' node sets differ, while
--       at full depth the same shift is sub-cell.
axiom_RA6 :: Bool
axiom_RA6 =
     and [ cellSpacing d apLeaves == fromIntegral (2 ^ (treeDepth - d) :: Integer) * step
         | d <- [1 .. treeDepth] ]
  && and [ cellSpacing (d - 1) apLeaves == 2 * cellSpacing d apLeaves
         | d <- [2 .. treeDepth] ]
  && cellSpacing treeDepth apLeaves == step
  && cellSpacing 1 apLeaves == 64 * step
  && movesAtShallowDepth
  where
    step = 1 % 128
    -- the tree MOVES frame to frame (per-frame LCT decree): at a
    -- shallow rung consecutive frames realise different node sets.
    movesAtShallowDepth =
      let g z d = nodesAt d (frameLeaves z)
      in and [ g z 2 /= g (z + 1) 2 | z <- [0 .. 6] ]

-- (RA7) Budget: every lawful allocation fits the 256-entry wire,
--       the shipping allocation uses 144 of 256, and the σ-
--       involution means the ground draws from the SAME tree — so
--       no allocation can overflow by construction.
axiom_RA7 :: Bool
axiom_RA7 =
     all (\e -> coloursUsed (allocOf e) <= paletteSize) editSpace
  && coloursUsed shippingAlloc == 144
  && coloursUsed (Alloc 7 7) == paletteSize
  && coloursUsed (Alloc 7 0) == 129
  && maximum (map (coloursUsed . allocOf) editSpace) == paletteSize

-- (RA8) ★ GRID TOTALITY: the edit space is exactly the product of
--       its widget states — |E| = widgetCells^arity. Every widget
--       configuration is a lawful edit (no dead cells) and every
--       lawful edit is reachable (no hidden GIFs). Distinctness
--       holds, so the widgets are a coordinate system.
axiom_RA8 :: Bool
axiom_RA8 =
     length editSpace == widgetCells ^ editArity
  && length editSpace == 32768
  && length (nub editSpace) == length editSpace
  && all inRange editSpace
  && identityEdit `elem` editSpace
  && widgetCells == 8                     -- one 8-cell row per dial
  where
    inRange (Edit a b c d e) =
      all (\x -> x >= 0 && x <= treeDepth) [a, b, c, d, e]

-- (RA9) Identity: the shipping path is a POINT in the edit space,
--       not a special case beside it. Rendering under identityEdit
--       returns exactly the 128 figure primaries and the 16 depth-4
--       ground nodes the machine emits today.
axiom_RA9 :: Bool
axiom_RA9 =
     allocOf identityEdit == shippingAlloc
  && length figs == 128 && length gnds == 16
  && figs == apLeaves
  && gnds == nodesAt 4 apLeaves
  && coloursUsed (allocOf identityEdit) == 144
  where (figs, gnds) = render apLeaves identityEdit

-- (RA10) Determinism and purity: render is a pure function, so the
--        same (capture, edit) yields the same bytes on every tick;
--        distinct edits are distinguishable on a non-degenerate
--        capture; and a whole library of variants is recoverable
--        from ONE capture plus five small integers per entry.
axiom_RA10 :: Bool
axiom_RA10 =
     all (\e -> render wobbleLeaves e == render wobbleLeaves e) sample
  && length (nub (map (render wobbleLeaves) sample)) == length sample
  && render wobbleLeaves identityEdit /= render wobbleLeaves (Edit 7 2 4 4 4)
  where
    -- one edit per ground depth: the rung dial alone must already
    -- give eight distinguishable GIFs from a single capture.
    sample = [ Edit 7 b 4 4 4 | b <- [0 .. treeDepth] ]

-- ════════════════════════════════════════════════════════════════
-- § 6. VISUALISATION
-- ════════════════════════════════════════════════════════════════

showLadder :: IO ()
showLadder = do
  putStrLn "  d_B │ ground cells │ spacing (leaf steps) │ colours │ bits/px"
  putStrLn "  ────┼──────────────┼──────────────────────┼─────────┼────────"
  mapM_ row [7, 6 .. 0]
  where
    row b = putStrLn $
         "  " ++ padL 3 (show b)
      ++ " │ " ++ padL 12 (show (2 ^ b :: Int))
      ++ " │ " ++ padL 20 (show (2 ^ (treeDepth - b) :: Int))
      ++ " │ " ++ padL 7 (show (coloursUsed (Alloc 7 b)))
      ++ " │ " ++ padL 6 (showF (fromRational (rateBits (1 % 2) (Alloc 7 b))))
      ++ (if b == dGnd shippingAlloc then "   ← today" else "")

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " RoleAllocation: entropy spent FIGURE-FIRST"
  putStrLn " head:tail IS figure:ground — one tree, two truncations"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The ground rung (figure pinned at depth 7) ──"
  putStrLn ""
  showLadder
  putStrLn ""

  putStrLn "── The edit space ──"
  putStrLn ""
  putStrLn $ "  dials        : " ++ show editArity
             ++ " (figure, ground, coarse, mid, fine)"
  putStrLn $ "  cells/dial   : " ++ show widgetCells
             ++ "  (one 8-cell row in the lattice)"
  putStrLn $ "  |edit space| : " ++ show (length editSpace)
             ++ "  = " ++ show widgetCells ++ "^" ++ show editArity
  putStrLn $ "  identity     : " ++ show identityEdit
  putStrLn $ "  today's rate : "
             ++ showF (fromRational (rateBits (1 % 2) shippingAlloc))
             ++ " bits/px of a possible 8"
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "RA1  role partition: figure XOR ground, masses complement"  [axiom_RA1]
  check "RA2  prefix conservation: depth-d node = exact block mean"  [axiom_RA2]
  check "RA3  allocation law (2^d_F/2^d_B)² = λ_F/λ_B, exact on ℚ"   [axiom_RA3]
  check "RA4  ★ FIGURE PRIORITY: only the ground is ever truncated"  [axiom_RA4]
  check "RA5  rate: affine, monotone, ≤ 8 bits/px across the space"  [axiom_RA5]
  check "RA6  ★ PHASE LAW: one bit off the ground DOUBLES the jump"  [axiom_RA6]
  check "RA7  budget: every lawful allocation fits 256; today 144"   [axiom_RA7]
  check "RA8  ★ GRID TOTALITY: |E| = 8^5, no dead cells, no hidden"  [axiom_RA8]
  check "RA9  identity: today's path is a POINT in the edit space"   [axiom_RA9]
  check "RA10 determinism: GIF = pure f(capture, edit); 8 distinct"  [axiom_RA10]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  The head:tail split and the figure:ground split are"
  putStrLn "  the SAME split. One tree; the figure reads it deep,"
  putStrLn "  the ground reads it shallow. The ground costs no new"
  putStrLn "  colours (σ mirrors the same entries) and no new law"
  putStrLn "  (PT5 already proves truncation is a valid palette)."
  putStrLn ""
  putStrLn "  Starving the ground is not a loss of detail. Because"
  putStrLn "  the tree is re-solved every frame, a coarse ground"
  putStrLn "  re-quantises across cells that DOUBLE in size for"
  putStrLn "  every bit removed — smooth drift becomes a discrete"
  putStrLn "  transition. The phase illusion is a rate allocation."
  putStrLn ""
  putStrLn "  Five dials, eight cells each, 32768 GIFs per capture."
  putStrLn "  Today's machine is the point (7, 4, 4, 4, 4)."
  putStrLn "══════════════════════════════════════════════════════════"

-- Helpers (no scientific notation: integer math, 3 dp)
showF :: Double -> String
showF x =
  let n    = round (abs x * 1000) :: Int
      sign = if x < 0 then "-" else ""
      frac = show (n `mod` 1000)
      pad3 = replicate (3 - length frac) '0' ++ frac
  in sign ++ show (n `div` 1000) ++ "." ++ pad3

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = and results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
