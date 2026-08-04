-- CentroidRefine.hs
-- Tesseract spec — quantization layer
--
-- PASS 2: FACE-WEIGHTED CENTROID REFINEMENT WITH A TRACED TRAJECTORY.
-- Companion to Centers.hs (CN1-CN6) and docs/REFINE-PASSES.md.
--
-- Pass 1 (the spine) fixes the partition and the index stream. Pass 2
-- refines the RECONSTRUCTION of each palette entry i by K fixed
-- proximal steps that PUSH toward the capture's empirical (face-mass-
-- weighted) mean m_i and PULL toward the canonical cell center c_i:
--
--   r⁰_i     = c_i                                  (start at the spine)
--   r^{k+1}_i = r^k_i + η·( a_i·(m_i − r^k_i) − b_i·(r^k_i − c_i) )
--   a_i      = face mass of entry i ∈ [0,1]         (the PUSH gain)
--   b_i      = μ·(1 − a_i)                          (the PULL gain)
--
-- The K per-step values ARE the trace ("the steps it takes to push and
-- pull colors"); K is FIXED, never data-dependent — the ANE constraint
-- (no data-dependent trip counts) and the provenance requirement are
-- the same design decision.
--
-- Laws (exact Rational arithmetic, zero floating point):
--
--   WL1  containment      every iterate of every entry stays inside its
--                         lattice cell (so CN2/CN6 idempotence extends
--                         to every refined table; epoch-sibling spread
--                         is bounded by the cell width as a corollary)
--   WL2  monotone energy  E^k = a(r−m)² + b(r−c)² never increases
--   WL3  background law   zero face mass ⇒ the trace is CONSTANT: the
--                         entry never leaves the canonical center —
--                         the background gains no options, exactly
--   WL4  exact contraction r^K − r* = (r⁰ − r*)·(1 − η(a+b))^K with
--                         fixed point r* = (a·m + b·c)/(a+b) — the
--                         trajectory is a geometric approach, provable
--                         to the last digit
--   WL5  trace telescope  the deltas sum to the total displacement:
--                         Σ_k (r^{k+1} − r^k) = r^K − r⁰ — the trace is
--                         complete provenance, nothing off the books
--
-- Face allocation emerges from WL3 + WL4: entries with face mass chase
-- their empirical colors (diversity where the face is); entries without
-- it collapse to the canonical spine (fewer options in the background).

module Main where

import Data.Ratio ((%))
import System.Exit (exitFailure, exitSuccess)

-- ── The schedule (all rational, all fixed) ──────────────────────

eta :: Rational
eta = 1 % 2          -- step size η

mu :: Rational
mu = 1 % 2           -- pull strength μ

bigK :: Int
bigK = 8             -- FIXED iteration count (ANE: no data-dependent trips)

-- ── One entry of the synthetic capture ──────────────────────────

data Entry = Entry
  { name :: String
  , lo   :: Rational   -- cell lower bound
  , hi   :: Rational   -- cell upper bound (half-open)
  , c    :: Rational   -- canonical center
  , m    :: Rational   -- empirical (weighted) mean, m ∈ [lo, hi)
  , a    :: Rational   -- face mass ∈ [0,1]
  }

-- | Smart constructor — the record's invariants, enforced at the only
--   door (mirrors RefineSchedule's precondition-validated init on the
--   Swift side). A malformed synthetic is a spec bug and dies loudly.
mkEntry :: String -> Rational -> Rational -> Rational -> Rational -> Rational -> Entry
mkEntry nm lo' hi' c' m' a'
  | not (0 <= a' && a' <= 1)   = error (nm ++ ": face mass outside [0,1]")
  | not (lo' < hi')            = error (nm ++ ": empty cell")
  | not (lo' <= c' && c' < hi') = error (nm ++ ": center outside cell")
  | not (lo' <= m' && m' < hi') = error (nm ++ ": mean outside cell")
  | otherwise = Entry nm lo' hi' c' m' a'

pullGain :: Entry -> Rational
pullGain e = mu * (1 - a e)

-- | WL0, the schedule sanity every other law leans on: η·(a+b) ≤ 1 for
--   all a ∈ [0,1] ⇔ η·max(1, μ) ≤ 1. Checked here AND precondition'd
--   in Swift's RefineSchedule.init — same boundary, both languages.
law_WL0 :: Bool
law_WL0 = eta * max 1 mu <= 1

-- The synthetic capture: one FACE display cell (level 2, four epoch
-- siblings with distinct means and falling face mass) and one
-- BACKGROUND display cell (level 1, zero face mass).
entries :: [Entry]
entries =
  [ mkEntry "face/d0" (1%2) (3%4) (5%8) (17%32) 1
  , mkEntry "face/d1" (1%2) (3%4) (5%8) (9%16)  (3%4)
  , mkEntry "face/d2" (1%2) (3%4) (5%8) (5%8)   (1%2)
  , mkEntry "face/d3" (1%2) (3%4) (5%8) (11%16) (1%4)
  , mkEntry "bg/d0"   (1%4) (1%2) (3%8) (7%16)  0
  , mkEntry "bg/d1"   (1%4) (1%2) (3%8) (5%16)  0
  ]

-- ── The iteration and its trace ─────────────────────────────────

step :: Entry -> Rational -> Rational
step e r = r + eta * (a e * (m e - r) - pullGain e * (r - c e))

-- | trace e = [r⁰, r¹, …, r^K]  (K+1 points, K steps)
trace' :: Entry -> [Rational]
trace' e = take (bigK + 1) (iterate (step e) (c e))

fixedPoint :: Entry -> Rational
fixedPoint e
  | a e + pullGain e == 0 = c e
  | otherwise = (a e * m e + pullGain e * c e) / (a e + pullGain e)

energy :: Entry -> Rational -> Rational
energy e r = a e * (r - m e)^(2::Int) + pullGain e * (r - c e)^(2::Int)

-- ── Laws ────────────────────────────────────────────────────────

law_WL1 :: Bool
law_WL1 = all (\e -> all (\r -> r >= lo e && r < hi e) (trace' e)) entries

law_WL2 :: Bool
law_WL2 = all (\e ->
    let es = map (energy e) (trace' e)
    in and (zipWith (>=) es (tail es))) entries

law_WL3 :: Bool
law_WL3 = all (\e -> a e /= 0 || all (== c e) (trace' e)) entries

law_WL4 :: Bool
law_WL4 = all (\e ->
    let r0 = c e
        rK = last (trace' e)
        rStar = fixedPoint e
        rho = 1 - eta * (a e + pullGain e)
    in rK - rStar == (r0 - rStar) * rho ^ bigK) entries

law_WL5 :: Bool
law_WL5 = all (\e ->
    let t = trace' e
        deltas = zipWith (-) (tail t) t
    in sum deltas == last t - head t) entries

-- Corollary of WL1, stated for the face cell explicitly: the spread of
-- the four epoch siblings never exceeds the cell width.
law_WL1_spread :: Bool
law_WL1_spread =
  let finals = [last (trace' e) | e <- entries, take 4 (name e) == "face"]
  in maximum finals - minimum finals < (3%4 - 1%2)

laws :: [(String, Bool)]
laws =
  [ ("WL0 schedule sane: η·max(1,μ) ≤ 1",             law_WL0)
  , ("WL1 containment (every iterate in its cell)",   law_WL1)
  , ("WL1c epoch-sibling spread < cell width",        law_WL1_spread)
  , ("WL2 monotone push/pull energy",                 law_WL2)
  , ("WL3 zero face mass ⇒ constant trace",           law_WL3)
  , ("WL4 exact geometric contraction to r*",         law_WL4)
  , ("WL5 trace telescopes to total displacement",    law_WL5)
  ]

main :: IO ()
main = do
  putStrLn "── CentroidRefine.hs: weighted push/pull, traced, exact ──"
  results <- mapM (\(nm, ok) -> do
    putStrLn $ "  " ++ (if ok then "✓" else "✗") ++ " " ++ nm
    pure ok) laws
  putStrLn ""
  putStrLn $ "  schedule: η=" ++ show eta ++ " μ=" ++ show mu
          ++ " K=" ++ show bigK ++ " (fixed — ANE-legal, fully traced)"
  if and results
    then do
      putStrLn $ "  " ++ show (length results) ++ "/" ++ show (length results)
               ++ " refinement laws hold (Rational-exact)"
      exitSuccess
    else do
      putStrLn "  REFINEMENT AXIOM FAILURE"
      exitFailure
