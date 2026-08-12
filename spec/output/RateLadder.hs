{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- RateLadder: The Stratified Compression Contract
--
-- Daniel's ruling (2026-08-12): the pipeline is one compressor —
-- camera in, GIF89a out — redesigned as a STRATIFIED rate ladder.
-- The atom: 2×2×2 ↔ 1 is an 8:1 ratio of information. Every
-- stratum declares its factor; factors TELESCOPE; the wire carries
-- its own meter (Birkhoff M = O/C in Rigau's operational form:
-- order = what the entropy coder removes).
--
-- Design doc: docs/rate-ladder-redesign.md. This spec is the
-- algebra those steps are gated against:
--
--   RL1  the pooling atom and its rung composition (exact)
--   RL2  the ladder telescopes (product law, exact)
--   RL3  the 8 polyphase offsets partition the torus (per rung)
--   RL4  eigenvalue rate allocation: b_i − b_j = ½·log₂(λ_i/λ_j)
--   RL5  the meter: M = (H_max − K̂)/H_max, monotone, anchored
--   RL6  the coverage code: Bayer 4×4 = exactly 17 rates ≤ log₂17
-- ════════════════════════════════════════════════════════════════

module RateLadder where

import Data.List (nub, sort)
import Data.Ratio ((%))

-- ════════════════════════════════════════════════════════════════
-- § 1. THE ATOM AND THE LADDER
-- ════════════════════════════════════════════════════════════════

-- | One rung of spacetime pooling: a 2×2×2 block ↔ 1 cell.
atomRatio :: Rational
atomRatio = 8

-- | Rung sides of the export cube (TriScale): 64³ → 32³ → 16³.
rungSides :: [Int]
rungSides = [64, 32, 16]

-- | Ratio of one rung step between adjacent sides (s → s/2).
rungRatio :: Int -> Int -> Rational
rungRatio fine coarse =
  (fromIntegral fine ^ (3 :: Int)) % (fromIntegral coarse ^ (3 :: Int))

-- | A stratum: name and its declared information ratio (in : out).
data Stratum = Stratum { sName :: String, sRatio :: Rational }

-- The declared ladder (docs §1). Content-dependent strata (aerial
-- compander, coverage, LZW) declare 1 here — their factors are
-- MEASURED per capture by the RATE LEDGER, not assumed; the exact
-- strata are structural and compose.
ladder :: [Stratum]
ladder =
  [ Stratum "S0 acquisition 768²→64²"   (fromIntegral ((768 * 768) `div` (64 * 64)))
  , Stratum "S1 metric OKLab"            1
  , Stratum "S2 aerial compander"        1      -- measured (≤2:1 chroma)
  , Stratum "S5 VQ 24b→8b"               3
  , Stratum "S7 coverage code"           1      -- measured (≤log₂17 b/tile)
  , Stratum "S8 LZW"                     1      -- measured (the meter)
  ]

-- | The composition law: ratios telescope by multiplication.
totalRatio :: [Stratum] -> Rational
totalRatio = product . map sRatio

-- ════════════════════════════════════════════════════════════════
-- § 2. POLYPHASE PARTITION (the 8 offsets of one rung)
--
-- Stride-2 pooling with offset o ∈ (ℤ/2)³ reads the fine torus in
-- 8 disjoint phase patterns; together the 8 phases read every fine
-- cell EXACTLY once per pooled output cell they contribute to.
-- (TriScale TL10 proves the partition on the loop torus; here the
-- law is restated at the rate level: each phase is one 8:1 read,
-- and the 8 phases tile the identity.)
-- ════════════════════════════════════════════════════════════════

type Cell = (Int, Int, Int)

torus :: Int -> [Cell]
torus n = [ (x, y, z) | x <- [0 .. n-1], y <- [0 .. n-1], z <- [0 .. n-1] ]

offsets8 :: [Cell]
offsets8 = [ (a, b, c) | a <- [0, 1], b <- [0, 1], c <- [0, 1] ]

-- | The 8 cells pooled into output cell (bx,by,bz) at offset o,
--   with torus wrap on side n.
blockAt :: Int -> Cell -> Cell -> [Cell]
blockAt n (ox, oy, oz) (bx, by, bz) =
  [ ( (2*bx + dx + ox) `mod` n
    , (2*by + dy + oy) `mod` n
    , (2*bz + dz + oz) `mod` n )
  | dx <- [0, 1], dy <- [0, 1], dz <- [0, 1] ]

-- ════════════════════════════════════════════════════════════════
-- § 3. EIGENVALUE RATE ALLOCATION (reverse water-filling)
--
-- Transform coding's classic law: with per-axis variances λ_i, the
-- optimal bit split satisfies b_i − b_j = ½·log₂(λ_i/λ_j), i.e.
-- codewords per axis n_i = 2^{b_i} ∝ √λ_i. The shell solver's
-- in-plane radii already scale by √λ₁, √λ₂ (DY4 whitening); the
-- lawful PC3 lift (step S3) must allocate by the SAME law — the
-- axiom pins the law itself so the port has a contract.
-- ════════════════════════════════════════════════════════════════

-- | Codeword allocation ∝ √λ, exact on squares of rationals:
--   (n_i / n_j)² == λ_i / λ_j.
allocLawful :: [Rational] -> [Rational] -> Bool
allocLawful ns lams =
  and [ (ns !! i / ns !! j) ^ (2 :: Int) == lams !! i / lams !! j
      | i <- ix, j <- ix, i /= j ]
  where ix = [0 .. length ns - 1]

-- ════════════════════════════════════════════════════════════════
-- § 4. THE METER (Rigau's operational Birkhoff measure)
--
--   H_max = 8                 the wire's own index width (no constant)
--   K̂     = 8·bytes/N         bits per pixel the coder actually spent
--   M     = (H_max − K̂)/H_max order ratio: what compression discovered
-- ════════════════════════════════════════════════════════════════

hMax :: Double
hMax = 8

meterM :: Double -> Double
meterM kHat = (hMax - kHat) / hMax

-- | Order-0 entropy of a histogram (bits/symbol).
entropy0 :: [Int] -> Double
entropy0 counts =
  let n = fromIntegral (sum counts) :: Double
      terms = [ let p = fromIntegral c / n in -(p * logBase 2 p)
              | c <- counts, c > 0 ]
  in if n <= 0 then 0 else sum terms

-- ════════════════════════════════════════════════════════════════
-- § 5. THE COVERAGE CODE (Bayer 4×4)
-- ════════════════════════════════════════════════════════════════

bayer4 :: [Double]
bayer4 = [ (fromIntegral v + 0.5) / 16
         | v <- [0,8,2,10, 12,4,14,6, 3,11,1,9, 15,7,13,5 :: Int] ]

-- | Number of tile cells shown σ-side at coverage t.
coverageCount :: Double -> Int
coverageCount t = length (filter (< t) bayer4)

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (RL1) The atom: one rung is exactly 8:1; the TriScale rungs are
--       exactly one and two atoms; the full descent 64³→16³ is 8².
axiom_RL1 :: Bool
axiom_RL1 =
     rungRatio 64 32 == atomRatio
  && rungRatio 32 16 == atomRatio
  && rungRatio 64 16 == atomRatio * atomRatio
  && rungRatio 64 16 == 512 % 8      -- 64:1 — two composed atoms
  && atomRatio == 8

-- (RL2) The ladder telescopes: the product of declared structural
--       ratios equals the end-to-end structural ratio, exactly —
--       and S0's factor is the audit's 144.
axiom_RL2 :: Bool
axiom_RL2 =
     totalRatio ladder == 144 * 3
  && sRatio (head ladder) == 144
  && all ((> 0) . sRatio) ladder

-- (RL3) Polyphase partition, per rung on a 4³ torus: at EVERY
--       offset the pooled blocks tile the torus exactly (each fine
--       cell read once — one lawful 8:1), and across the 8 offsets
--       every fine cell is read exactly 8 times (the phases tile
--       the identity; reading all phases costs exactly one fine
--       pass per phase, which is the tent-at-box-cost identity's
--       rate-level shadow).
axiom_RL3 :: Bool
axiom_RL3 = all tileOK offsets8 && countsOK
  where
    n = 4
    outs = [ (bx, by, bz) | bx <- [0 .. 1], by <- [0 .. 1], bz <- [0 .. 1] ]
    -- n=4 pools to 2³ outputs of 8 cells each
    tileOK o =
      let cells = concatMap (blockAt n o) outs
      in length cells == n * n * n && sort cells == sort (torus n)
    countsOK =
      let allReads = concat [ concatMap (blockAt n o) outs | o <- offsets8 ]
      in all (\c -> length (filter (== c) allReads) == 8) (torus n)

-- (RL4) Eigen allocation: n ∝ √λ satisfies the pairwise bit law
--       (n_i/n_j)² = λ_i/λ_j exactly; a lawless allocation fails.
axiom_RL4 :: Bool
axiom_RL4 =
     allocLawful [6, 3, 2]  [36, 9, 4]     -- √λ = 6,3,2
  && allocLawful [10, 5, 1] [100, 25, 1]
  && not (allocLawful [6, 4, 2] [36, 9, 4])
  && allocLawful [1, 1] [5, 5]             -- equal variance ⇒ equal split

-- (RL5) The meter: anchored at M(0)=1 and M(8)=0, strictly
--       monotone decreasing in K̂; entropy is bounded 0 ≤ H₀ ≤ 8
--       on 256-bin histograms, 0 exactly on constant streams and
--       8 exactly on uniform ones.
axiom_RL5 :: Bool
axiom_RL5 =
     meterM 0 == 1
  && meterM hMax == 0
  && and (zipWith (>) (map meterM ks) (map meterM (tail ks)))
  && entropy0 (256 : replicate 255 0) == 0
  && abs (entropy0 (replicate 256 16) - 8) < 1e-12
  && all (\h -> let e = entropy0 h in e >= 0 && e <= 8 + 1e-12) hists
  where
    ks = [0, 1 .. 8] :: [Double]
    hists = [ [ ((i * 37 + s) `mod` 97) | i <- [0 .. 255] ] | s <- [1 .. 5] ]

-- (RL6) The coverage code: 16 distinct thresholds ⇒ exactly 17
--       representable coverages (0..16 σ cells), monotone in t,
--       hitting both ends — a ≤log₂17-bit rate decided by the
--       mixture posterior, never by a tuned constant.
axiom_RL6 :: Bool
axiom_RL6 =
     length (nub bayer4) == 16
  && counts == [0 .. 16]
  && head counts == 0 && last counts == 16
  where
    -- probe just below/above every threshold plus the ends
    probes = 0 : concat [ [th - 1e-9, th + 1e-9] | th <- sort bayer4 ] ++ [1]
    counts = nub (map coverageCount (sort probes))

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " RateLadder: the stratified compression contract"
  putStrLn " camera → GIF89a is one compressor; every stratum declares"
  putStrLn " its ratio; 2×2×2 ↔ 1 = 8:1 is the atom; the wire carries"
  putStrLn " its own meter (RATE LEDGER)"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "RL1 atom: rung = 8:1 exact, 64³→16³ = 8² composed"        [axiom_RL1]
  check "RL2 telescoping: structural ratios multiply exactly"      [axiom_RL2]
  check "RL3 polyphase: every offset tiles; 8 phases = identity"   [axiom_RL3]
  check "RL4 allocation: n ∝ √λ ⇔ (nᵢ/nⱼ)² = λᵢ/λⱼ exact"          [axiom_RL4]
  check "RL5 meter: M anchored + monotone, H₀ ∈ [0,8] tight"       [axiom_RL5]
  check "RL6 coverage: exactly 17 rates, both ends reachable"      [axiom_RL6]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  Beauty math is compression math (Birkhoff M = O/C in"
  putStrLn "  Rigau's operational form; Schmidhuber's shortest"
  putStrLn "  description). A stratum may lose information only"
  putStrLn "  lawfully: declared ratio, perceptual metric, measured"
  putStrLn "  progress on the ledger. Accidental loss — aliasing,"
  putStrLn "  undeclared truncation, unmeasured wire cost — is debt,"
  putStrLn "  and the ladder's steps retire it one stratum at a time."
  putStrLn "══════════════════════════════════════════════════════════"

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
