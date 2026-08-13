{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- AttractorRAG: the library as a retrievable colour corpus
--
-- Daniel (2026-08-13): "the web of connectivity just means that
-- these color attractors need to be RAG, so that we can easily
-- query and compose a GIF at the edit stage." Rulings taken: the
-- store is THE WHOLE LIBRARY, and the retrieval key is OKLab
-- POSITION.
--
-- ── WHAT CHANGES ────────────────────────────────────────────────
--
-- Today the library is a shelf of finished GIFs — write-once,
-- read-for-playback. Nothing indexes it, nothing queries it, and a
-- colour discovered in one capture can never appear in another.
--
-- This spec makes the library a CORPUS. Every capture contributes
-- its 16 attractor basins per frame to a store keyed by OKLab
-- position; editing retrieves the nearest concentrations by ΔE and
-- composes a palette from them. A GIF made on Tuesday can be built
-- from a colour that only ever existed on Monday.
--
-- ── ONE METRIC FOR THE WHOLE APP (AR2) ──────────────────────────
--
-- Retrieval distance is ΔE in OKLab — the SAME metric that
-- PhaseTiling's energy uses per bond (PD1) and that DyadPalette's
-- assignment uses per pixel. Not "a similar metric": the same one.
-- So a colour that is near in the energy is near in retrieval, and
-- the app has exactly one notion of colour distance.
--
-- ── RETRIEVAL IS A PREFIX CODE (AR4) ────────────────────────────
--
-- ★ k-NN is MONOTONE: the k+1 nearest attractors contain the k
-- nearest, as a prefix. So retrieval is itself successively
-- refinable — asking for more never revises what you already had.
-- The head:tail structure that RoleAllocation gives the palette and
-- Octave gives the cube, retrieval gets for free from the metric.
--
-- ── EIGHT BALANCED PAIRS (AR5, AR12, AR13) ──────────────────────
--
-- Daniel's correction (2026-08-13): the ladder is
--
--     1:1   1:1   2:2   4:4   8:8   16:16   32:32   64:64
--
-- — EIGHT PAIRS, each BALANCED, summing to 256. Three things were
-- collapsed into one in the first draft, and they are separate:
--
--   RETRIEVAL selects WHICH attractors  — by ΔE (AR3)
--   VARIANCE  allocates HOW MANY entries — by √λ, RL4/PT8 (AR13)
--   BALANCE   pairs each with its σ-twin at EQUAL size (AR12)
--
-- "Nearest takes the largest basin" conflated the first two and is
-- wrong: codewords belong where the basin is WIDE, not where the
-- query happened to land. And balance is not bookkeeping — because
-- comp negates (a, b), equal-sized pairs cancel their chroma
-- exactly, so the table's weighted chroma is ZERO and the palette
-- carries no net cast. Unequal pairs put a colour bias into every
-- frame that uses them.
--
-- ── REPRODUCIBILITY IS NOT FREE (AR8) ───────────────────────────
--
-- A query's answer depends on the store, and the store GROWS. So a
-- composed GIF is reproducible only if it records which store it
-- was composed against. AR8 states the obligation: the store
-- version travels with the composition, or the GIF is not
-- re-derivable — which would break EditMachine EM11's path
-- independence and RoleAllocation RA10's determinism.
--
-- ── AXIOMS ──────────────────────────────────────────────────────
--
--   AR1  every attractor carries position, basin weight and full
--        provenance (capture, frame, shell)
--   AR2  ★ the retrieval metric IS the energy metric: ΔE in OKLab
--   AR3  ★ retrieval is EXACT and DETERMINISTIC — exhaustive, with
--        provenance-ordered tie-breaking. No approximate index
--   AR4  ★ k-NN is MONOTONE: query (k+1) extends query k as a
--        prefix — retrieval is successively refinable
--   AR5  ★ EIGHT BALANCED PAIRS: 1:1 1:1 2:2 4:4 8:8 16:16 32:32
--        64:64, σ-symmetric, summing to 256
--   AR6  the composed table satisfies the σ-involution
--   AR7  provenance survives composition — every entry traces back
--   AR8  ★ a composition is reproducible only against a PINNED
--        store version
--   AR9  totality: the empty store retrieves nothing; k beyond the
--        store size returns the whole store, never an error
--   AR10 ★ the library IS the corpus: attractors cross captures, so
--        an edit can compose colours the capture never contained
--   AR11 self-retrieval: querying at an attractor's own position
--        returns that attractor first
--   AR12 ★ BALANCE: equal-sized pairs cancel chroma exactly, so the
--        table has ZERO net cast; unbalanced pairs bias it
--   AR13 ★ relevance SELECTS, variance ALLOCATES — the two orders
--        differ, so rank-based sizing is a different answer
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.List (nub, sort, sortOn, isPrefixOf)
import Data.Ratio ((%))

type Q = Rational
type Lab = (Q, Q, Q)

labSub :: Lab -> Lab -> Lab
labSub (l1, a1, b1) (l2, a2, b2) = (l1 - l2, a1 - a2, b1 - b2)

-- | ΔE² in OKLab. THE metric — the same one PhaseTiling uses per
--   bond and DyadPalette uses per pixel.
dE2 :: Lab -> Lab -> Q
dE2 p q = let (dl, da, db) = labSub p q in dl * dl + da * da + db * db

comp :: Lab -> Lab
comp (l, a, b) = (l, negate a, negate b)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE STORE
-- ════════════════════════════════════════════════════════════════

-- | Where an attractor came from. Total ordering on provenance is
--   what makes tie-breaking deterministic (AR3).
data Prov = Prov
  { pCapture :: Int      -- which capture in the library
  , pFrame   :: Int      -- which of its 64 frames
  , pShell   :: Int      -- which of the 16 basins
  } deriving (Eq, Ord, Show)

data Attractor = Attractor
  { aPos    :: Lab       -- OKLab position — the RETRIEVAL key
  , aSpread :: Q         -- the basin's variance — the ALLOCATION key
  , aProv   :: Prov
  } deriving (Eq, Show)

-- | ★ EIGHT BALANCED PAIRS (Daniel, 2026-08-13):
--
--     1:1  1:1  2:2  4:4  8:8  16:16  32:32  64:64
--
--   The ladder is not sixteen basins in a mirrored sequence — it is
--   EIGHT PAIRS, and each pair's two members carry the SAME size.
--   A figure attractor and its σ-complement are one attractor seen
--   from two sides, so an unequal split would be incoherent.
pairLadder :: [Int]
pairLadder = [1, 1, 2, 4, 8, 16, 32, 64]

-- | Both members of every pair, in table order.
ladder :: [Int]
ladder = pairLadder ++ reverse pairLadder

paletteSize :: Int
paletteSize = 256

-- | Allocation order: LARGEST basin first. Which attractor receives
--   it is decided by spread, not by rank (AR13).
descLadder :: [Int]
descLadder = reverse (sort pairLadder)         -- 64,32,16,8,4,2,1,1

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

-- | A library of captures, each contributing its basins. This is
--   the corpus: three captures, four frames each, sixteen shells.
store :: [Attractor]
store =
  [ Attractor
      { aPos = ( fromIntegral (lcg (h * 7 + 1) `mod` 1000) % 1000
               , fromIntegral (lcg (h * 13 + 2) `mod` 400 - 200) % 1000
               , fromIntegral (lcg (h * 29 + 3) `mod` 400 - 200) % 1000 )
      , aSpread = fromIntegral (lcg (h * 31 + 7) `mod` 997 + 1) % 1000
      , aProv = Prov c f s }
  | c <- [0 .. 2], f <- [0 .. 3], s <- [0 .. 15]
  , let h = c * 1000 + f * 100 + s ]

storeVersion :: [Attractor] -> Int
storeVersion = length

-- ════════════════════════════════════════════════════════════════
-- § 2. RETRIEVAL
-- ════════════════════════════════════════════════════════════════

-- | ★ Exact k-nearest by ΔE, ties broken by provenance. Exhaustive
--   — no approximate index, because an ANN structure could return
--   different neighbours between runs and a GIF must be
--   re-derivable (RA10, EM11).
query :: [Attractor] -> Lab -> Int -> [Attractor]
query st k n =
  take n (sortOn (\a -> (dE2 (aPos a) k, aProv a)) st)

-- ════════════════════════════════════════════════════════════════
-- § 3. COMPOSITION
-- ════════════════════════════════════════════════════════════════

-- | ★ ALLOCATION IS BY SPREAD, NOT BY RANK (AR13). Retrieval
--   selects WHICH attractors; reverse water-filling (RateLadder
--   RL4, PairTree PT8) decides HOW MANY entries each receives —
--   codewords go where the variance is, because that is where they
--   are needed to cover the basin. Ties break on provenance so the
--   allocation is deterministic.
allocate :: [Attractor] -> [(Attractor, Int)]
allocate as =
  zip (sortOn (\a -> (negate (aSpread a), aProv a)) as) descLadder

-- | The figure half: 128 entries. An entry names its basin's
--   CENTRE; DyadPalette's shell solver fills around it.
composeHalf :: [Attractor] -> [Lab]
composeHalf as = concat [ replicate n (aPos a) | (a, n) <- allocate as ]

-- | The full table: the figure half and its σ-mirror.
composeTable :: [Attractor] -> [Lab]
composeTable as = h ++ map comp (reverse h)
  where h = composeHalf as

-- | Provenance of every composed entry, in table order.
composeProv :: [Attractor] -> [Prov]
composeProv as =
  let hs = concat [ replicate n (aProv a) | (a, n) <- allocate as ]
  in hs ++ reverse hs

-- | A composition records the store it was made against (AR8).
data Composition = Composition
  { cTable   :: [Lab]
  , cProv    :: [Prov]
  , cVersion :: Int
  } deriving (Eq, Show)

composeAt :: [Attractor] -> Lab -> Composition
composeAt st k =
  let as = query st k 8
  in Composition { cTable = composeTable as
                 , cProv = composeProv as
                 , cVersion = storeVersion st }

probe :: Lab
probe = (1 % 2, 1 % 20, negate (1 % 20))

-- ════════════════════════════════════════════════════════════════
-- § 4. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (AR1) Every attractor carries a position, a basin weight from the
--       ladder, and full provenance — capture, frame and shell.
axiom_AR1 :: Bool
axiom_AR1 =
     length store == 3 * 4 * 16
  && all (\a -> aSpread a > 0) store
  && length (nub (map aProv store)) == length store
  && all (\a -> pShell (aProv a) >= 0 && pShell (aProv a) < 16) store
  && length (nub (map aPos store)) > 1

-- (AR2) ★ ONE METRIC. Retrieval distance is ΔE² in OKLab: the same
--       function PhaseTiling uses per bond. Symmetric, non-negative,
--       zero exactly on coincidence.
axiom_AR2 :: Bool
axiom_AR2 =
     all (\(p, q) -> dE2 p q == dE2 q p) pairs
  && all (\(p, q) -> dE2 p q >= 0) pairs
  && all (\(p, q) -> (dE2 p q == 0) == (p == q)) pairs
  where
    ps    = map aPos (take 10 store)
    pairs = [ (p, q) | p <- ps, q <- ps ]

-- (AR3) ★ EXACT AND DETERMINISTIC. The same query against the same
--       store gives the same answer, always; results are ordered by
--       distance; ties break on provenance, so no two runs disagree.
axiom_AR3 :: Bool
axiom_AR3 =
     query store probe 8 == query store probe 8
  && ordered (map (\a -> dE2 (aPos a) probe) (query store probe 12))
  && query store probe 8 == query (reverse store) probe 8   -- order-free
  && tieBreakStable
  where
    ordered xs = and (zipWith (<=) xs (tail xs))
    -- two attractors at the SAME distance resolve by provenance
    twin p = Attractor { aPos = probe, aSpread = 1 % 2, aProv = p }
    dupes  = [ twin (Prov 9 9 1), twin (Prov 9 9 0) ]
    tieBreakStable =
      map aProv (query (dupes ++ store) probe 2)
        == [Prov 9 9 0, Prov 9 9 1]

-- (AR4) ★ MONOTONE RETRIEVAL. query (k+1) extends query k as a
--       PREFIX — asking for more never revises what you had. So
--       retrieval is successively refinable, like the palette tree
--       and the octave.
axiom_AR4 :: Bool
axiom_AR4 =
     and [ query store probe n `isPrefixOf` query store probe (n + 1)
         | n <- [0 .. 15] ]
  && query store probe 0 == []
  && length (query store probe 5) == 5

-- (AR5) ★ THE LADDER ALLOCATES. The nearest retrieved attractor
--       takes the largest basin; the half sums to 128 and the table
--       to 256 — the palette width, exactly.
axiom_AR5 :: Bool
axiom_AR5 =
     pairLadder == [1, 1, 2, 4, 8, 16, 32, 64]
  && length pairLadder == 8                          -- EIGHT PAIRS
  && sum (map (* 2) pairLadder) == paletteSize       -- both members
  && ladder == pairLadder ++ reverse pairLadder
  && ladder == reverse ladder                        -- σ-symmetric
  && and [ ladder !! i == ladder !! (15 - i) | i <- [0 .. 7] ]  -- BALANCED
  && length (composeHalf as) == paletteSize `div` 2
  && length (composeTable as) == paletteSize
  where as = query store probe 8

-- (AR6) The composed table satisfies the σ-involution: entry 255−i
--       is the complement of entry i, for every i.
axiom_AR6 :: Bool
axiom_AR6 =
     and [ t !! (paletteSize - 1 - i) == comp (t !! i)
         | i <- [0 .. paletteSize `div` 2 - 1] ]
  && length t == paletteSize
  where t = composeTable (query store probe 8)

-- (AR7) Provenance survives composition: every one of the 256
--       entries names the capture, frame and shell it came from.
axiom_AR7 :: Bool
axiom_AR7 =
     length (cProv c) == paletteSize
  && length (cTable c) == paletteSize
  && length (nub (cProv c)) <= 8            -- eight sources, no more
  && all (\p -> p `elem` map aProv store) (cProv c)
  where c = composeAt store probe

-- (AR8) ★ REPRODUCIBILITY NEEDS A PIN. A query's answer depends on
--       the store, and the store grows — so a composition records
--       its store version. Without the pin the same edit yields a
--       different GIF after the library changes, breaking EM11.
axiom_AR8 :: Bool
axiom_AR8 =
     cVersion (composeAt store probe) == length store
  && cVersion (composeAt grown probe) /= cVersion (composeAt store probe)
  && cTable (composeAt grown probe) /= cTable (composeAt store probe)
  && composeAt store probe == composeAt store probe    -- pinned: stable
  where
    intruder = Attractor { aPos = probe, aSpread = 1, aProv = Prov 99 0 0 }
    grown    = intruder : store

-- (AR9) Totality: an empty store retrieves nothing; asking for more
--       than exists returns everything, never an error.
axiom_AR9 :: Bool
axiom_AR9 =
     query [] probe 8 == []
  && length (query store probe 10000) == length store
  && query store probe 1 == take 1 (query store probe 8)
  && null (composeHalf [])

-- (AR10) ★ THE LIBRARY IS THE CORPUS. Retrieval crosses captures:
--         a single query returns attractors from more than one
--         capture, so an edit can compose colours the capture it is
--         editing never contained.
axiom_AR10 :: Bool
axiom_AR10 =
     length (nub (map (pCapture . aProv) retrieved)) > 1
  && length (nub (map (pCapture . aProv) store)) == 3
  && any (\a -> pCapture (aProv a) /= pCapture (aProv (head retrieved)))
         retrieved
  where retrieved = query store probe 8

-- (AR11) Self-retrieval: querying at an attractor's own position
--        returns that attractor first, at distance zero.
axiom_AR11 :: Bool
axiom_AR11 =
     all selfFirst (take 12 store)
  where
    selfFirst a =
      let best = head (query store (aPos a) 1)
      in dE2 (aPos best) (aPos a) == 0

-- (AR12) ★ BALANCE, AND WHAT IT BUYS. A pair is a figure attractor
--         and its σ-complement, and they carry the SAME basin size.
--         Because comp negates (a, b), a balanced pair's weighted
--         centroid is ACHROMATIC — the chroma cancels exactly. So
--         the whole table's weighted chroma sums to ZERO and the
--         palette carries no net colour cast.
--
--         Equal sizes are not decoration: an UNBALANCED pair leaves
--         residual chroma, and the counterexample below shows the
--         cast appearing the moment the two members differ.
axiom_AR12 :: Bool
axiom_AR12 =
     all balancedPair (allocate as)                  -- n·x + n·comp x = 0
  && all skewLeavesResidue skewPairs                 -- ★ n1 ≠ n2 ⇒ residue
  && chromaSum (composeTable as) == (0, 0)           -- the table cancels
  && chromaSum unbalancedTable /= (0, 0)             -- ★ a skewed one casts
  && length unbalancedTable == paletteSize
  where
    as = query store probe 8

    chromaSum t = ( sum [ a | (_, a, _) <- t ], sum [ b | (_, _, b) <- t ] )

    -- a pair contributes n copies of x and n copies of comp x
    balancedPair (a, n) =
      let (_, x, y) = aPos a
      in (fromIntegral n * x + fromIntegral n * negate x
         , fromIntegral n * y + fromIntegral n * negate y) == (0, 0)

    -- an UNEQUAL pair: n1 figure entries against n2 ground entries.
    -- The chroma no longer cancels — a residue of (n1 - n2)·chroma.
    skewLeavesResidue (a, n1, n2) =
      let (_, x, y) = aPos a
          rx = fromIntegral n1 * x + fromIntegral n2 * negate x
          ry = fromIntegral n1 * y + fromIntegral n2 * negate y
      in (rx, ry) /= (0, 0)
    skewPairs = [ (a, n1, n2)
                | ((a, n1), n2) <- zip (allocate as) (reverse descLadder)
                , n1 /= n2
                , let (_, x, y) = aPos a, (x, y) /= (0, 0) ]

    unbalancedTable =
      let h  = composeHalf as
          g  = concat [ replicate n (comp (aPos a))
                      | ((a, _), n) <- zip (allocate as) (reverse descLadder) ]
      in h ++ g

-- (AR13) ★ RELEVANCE SELECTS; VARIANCE ALLOCATES. Distance decides
--         WHICH attractors are retrieved. Basin size follows the
--         attractor's own SPREAD, by reverse water-filling (RL4,
--         PT8) — codewords go where they are needed to cover the
--         basin, not where the query happened to land. The two
--         orders differ, so "nearest takes the largest" is a
--         different (and wrong) allocation.
axiom_AR13 :: Bool
axiom_AR13 =
     map snd (allocate as) == descLadder
  && spreadOrder /= rankOrder                        -- ★ they differ
  && allocate as == allocate as                      -- deterministic
  && sortOn negate (map (aSpread . fst) (allocate as))
       == map (aSpread . fst) (allocate as)          -- spread-descending
  where
    as          = query store probe 8
    spreadOrder = map (aProv . fst) (allocate as)
    rankOrder   = map aProv as

-- ════════════════════════════════════════════════════════════════
-- § 5. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AttractorRAG: the library as a retrievable colour corpus"
  putStrLn " key = OKLab position; metric = the SAME ΔE as the energy"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The store ──"
  putStrLn ""
  putStrLn $ "  captures : " ++ show (length (nub (map (pCapture . aProv) store)))
  putStrLn $ "  frames   : " ++ show (length (nub (map (pFrame . aProv) store)))
           ++ " each (the app: 64)"
  putStrLn $ "  basins   : " ++ show (length ladder) ++ " per frame"
  putStrLn $ "  total    : " ++ show (length store) ++ " attractors"
  putStrLn ""

  putStrLn "── One query, composed ──"
  putStrLn ""
  putStrLn "  rank │ basin │ from (capture, frame, shell)"
  putStrLn "  ─────┼───────┼─────────────────────────────"
  mapM_ line (zip3 [1 :: Int ..] (query store probe 8) descLadder)
  putStrLn ""
  putStrLn $ "  → " ++ show (length (composeTable (query store probe 8)))
           ++ " entries, σ-involuted, pinned at store version "
           ++ show (cVersion (composeAt store probe))
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "AR1  attractors carry position, SPREAD, and provenance"    [axiom_AR1]
  check "AR2  ★ the retrieval metric IS the energy metric (ΔE)"     [axiom_AR2]
  check "AR3  ★ exact + deterministic; ties break on provenance"    [axiom_AR3]
  check "AR4  ★ k-NN is MONOTONE — retrieval is refinable"          [axiom_AR4]
  check "AR5  ★ EIGHT BALANCED PAIRS 1:1 1:1 2:2 ... 64:64 = 256"   [axiom_AR5]
  check "AR6  the composed table satisfies the σ-involution"        [axiom_AR6]
  check "AR7  provenance survives composition, all 256 entries"     [axiom_AR7]
  check "AR8  ★ reproducibility needs a PINNED store version"       [axiom_AR8]
  check "AR9  totality: empty store, oversized k, both safe"        [axiom_AR9]
  check "AR10 ★ the library IS the corpus — retrieval crosses it"   [axiom_AR10]
  check "AR11 self-retrieval returns the attractor itself first"    [axiom_AR11]
  check "AR12 ★ BALANCED pairs ⇒ zero net chroma; unbalanced casts" [axiom_AR12]
  check "AR13 ★ relevance SELECTS, variance ALLOCATES (RL4)"        [axiom_AR13]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  The library stops being a shelf of outputs and becomes"
  putStrLn "  a corpus. Every capture contributes its basins; an edit"
  putStrLn "  retrieves the nearest concentrations by ΔE and composes"
  putStrLn "  a palette from them. A GIF made today can be built from"
  putStrLn "  a colour that only ever existed last week."
  putStrLn ""
  putStrLn "  Retrieval uses the SAME metric as the energy, so near"
  putStrLn "  in one is near in the other — the app has exactly one"
  putStrLn "  notion of colour distance. And k-NN is monotone, so"
  putStrLn "  asking for more never revises what you had: retrieval"
  putStrLn "  is head:tail too."
  putStrLn ""
  putStrLn "  The price is a pin. A query depends on the store, and"
  putStrLn "  the store grows — so a composition carries its store"
  putStrLn "  version, or the GIF is not re-derivable."
  putStrLn "══════════════════════════════════════════════════════════"

line :: (Int, Attractor, Int) -> IO ()
line (i, a, n) =
  let Prov c f s = aProv a
  in putStrLn $ "  " ++ pad 4 (show i)
             ++ " │ " ++ pad 5 (show n)
             ++ " │ (" ++ show c ++ ", " ++ show f ++ ", " ++ show s ++ ")"

pad :: Int -> String -> String
pad n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = and results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
