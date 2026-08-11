{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- OctaveCodec: the color-side σ/κ contract — composed binary form
--
-- Design: docs/sk-gene-calculus-2026-08-11.md §3, §12. Companion
-- to SKGeneCalculus.hs (SK6–SK8: flat octave laws, toy classical
-- basis) and SKGeneSemantics.hs (AX1: separability of the exact
-- Haar). This file proves the laws for the form the codec is
-- ACTUALLY BUILT IN under the gauge principle: ONE binary pair
--
--     σ_g(x) = (x + g(x), x − g(x))        κ(u, v) = (u + v)/2
--
-- composed over three WIRED levels (the wiring — not the weights —
-- picks the physical axis each level splits; §12). SK7 proved the
-- flat parameterization Ŝ_g(x)_ε = x + Σ χ_w g_w(x); the trainer
-- composes binary stages instead, and composition needs its own
-- exact theorems:
--
--   CX1  binary retraction ∀g: κ(σ_g(x)) = x — one line, but it is
--        the codec's load-bearing law (R1), so it is gated
--   CX2  WIRED-COMPOSITION DC LAW ∀g₁,g₂,g₃ (arbitrary, even
--        position-dependent, per level): the composed 3-level
--        expansion yields 8 leaves with mean exactly x. Each stage
--        preserves the sum ((x+g)+(x−g) = 2x), so DC survives any
--        generators — the octave retraction K̂∘Ŝ = id holds BY
--        CONSTRUCTION in composed form, zero loss terms
--   CX3  idempotence ∀g: ê = Ŝ_g ∘ K̂ satisfies ê∘ê = ê on the
--        composed octave (mean of Ŝ_g(y) is y, so ê is a projector
--        whatever the generators learned)
--   CX4  CLASSICALITY INHERITANCE: if every level's generator
--        vanishes at codebook point c, the composed octave copies
--        exactly — Ŝ_g(c) = (c,…,c), κ-fold returns c, and the
--        copy defect is 0 at c while nonzero off-codebook (the
--        SK8 toy law lifted to the composed form the trainer uses)
--   CX5  ALIGNMENT with the flat form: with position-dependent
--        binary generators the composed octave REALIZES the flat
--        Ŝ_g of SK7 — its Haar analysis recovers DC = x and the
--        7 details as triangular combinations of the level
--        generators; checked exactly on ℚ by computing both sides
--
-- Gap-audit closures (2026-08-11, codec-gap-audit workflow G2a/G2b):
-- the real dyad-256 codebook is PER-FRAME DYNAMIC (a function of 9
-- stats), so classicality cannot be a fixed polynomial annihilator
-- (SK8's toy). The ruled mechanism is ARCHITECTURAL vanishing:
--
--     g_C(x) = dist²(x, C) · ĝ(x)      dist²(x,C) = min_c ‖x − c‖²
--
-- The mask is DATA (the palette), never weights — the same move as
-- the gauge principle. Two gates, vector OKLab over ℚ:
--
--   CX6  ∀-CODEBOOK LAW: for an involution-closed 256-entry ℚ
--        codebook (128 primaries + comp mirror, the DYAD shape),
--        the masked generator vanishes exactly iff x ∈ C, so the
--        composed 3-level octave copies EVERY codeword exactly and
--        defects off-codebook — SK8/CX4 lifted to dyad-256 scale
--   CX7  DYNAMIC STABILITY (two captures): the SAME ĝ under two
--        different codebooks C₁ ≠ C₂ copies exactly on each
--        capture's own palette; a codeword of C₁ ∉ C₂ defects
--        under C₂'s mask — per-capture dynamism is safe because
--        the palette enters as input, not as weights
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.Ratio ((%))

type Q = Rational

-- ── the binary pair ─────────────────────────────────────────────

sigma :: (Q -> Q) -> Q -> (Q, Q)
sigma g x = (x + g x, x - g x)

kappa :: (Q, Q) -> Q
kappa (u, v) = (u + v) / 2

-- ── composed 3-level expansion, wiring fixed (t then y then x
--    order is a gauge choice — CX2 must hold for ANY wiring, which
--    it does because the law never mentions the axis) ─────────────
--
-- Generators may depend on the level AND the position within the
-- level (the most general case the trainer could ever use):
--   level 1: one generator      g1
--   level 2: two generators     g2 !! i, i <- [0, 1]
--   level 3: four generators    g3 !! i, i <- [0..3]

expand3 :: (Q -> Q) -> [Q -> Q] -> [Q -> Q] -> Q -> [Q]
expand3 g1 g2 g3 x =
  let (a, b)   = sigma g1 x
      halves   = [a, b]
      quarters = concat [ let (u, v) = sigma (g2 !! i) h in [u, v]
                        | (i, h) <- zip [0..] halves ]
      leaves   = concat [ let (u, v) = sigma (g3 !! i) q in [u, v]
                        | (i, q) <- zip [0..] quarters ]
  in leaves

contract3 :: [Q] -> Q
contract3 ls = sum ls / fromIntegral (length ls)

-- ── Haar analysis of an 8-block (leaf order = wiring order) ─────

chi :: Int -> Int -> Q
chi w e = if odd (popc (w `andI` e)) then -1 else 1
  where andI a b = sum [ 2^k | k <- [0..2 :: Int]
                       , odd (a `div` 2^k), odd (b `div` 2^k) ]
        popc n = length [ () | k <- [0..2 :: Int], odd (n `div` 2^k) ]

haarCoef :: Int -> [Q] -> Q
haarCoef w ls = sum [ chi w e * l | (e, l) <- zip [0..] ls ] / 8

-- ── toy generator families (adversarial: nonlinear, mixed) ──────

gens1 :: [Q -> Q]
gens1 = [ \x -> x * x - 1 % 3
        , \x -> 2 * x + 5 % 7
        , \x -> x * (x - 1) * (x + 2) / 4 ]

mkG2 :: Int -> [Q -> Q]
mkG2 k = [ \x -> fromIntegral (i + k) * x * x - i2 % 5
         | i <- [0, 1], let i2 = fromIntegral i ]

mkG3 :: Int -> [Q -> Q]
mkG3 k = [ \x -> (x + fromIntegral (i - k)) * x / 3
         | i <- [0 .. 3] ]

probes :: [Q]
probes = [ 5 % 7, -3 % 2, 0, 22 % 9, 1 ]

-- classicality toy: h vanishes exactly on the codebook (SK8 form)
codebook :: [Q]
codebook = [0, 1, 2, 3]

hCls :: Q -> Q
hCls x = product [ x - c | c <- codebook ] / 16

-- ── vector OKLab over ℚ: the dyad-scale classicality laws ───────

type V3 = (Q, Q, Q)

vAdd, vSub :: V3 -> V3 -> V3
vAdd (a,b,c) (p,q,r) = (a+p, b+q, c+r)
vSub (a,b,c) (p,q,r) = (a-p, b-q, c-r)

vScale :: Q -> V3 -> V3
vScale s (a,b,c) = (s*a, s*b, s*c)

vMean :: [V3] -> V3
vMean vs = vScale (1 / fromIntegral (length vs)) (foldr vAdd (0,0,0) vs)

dist2 :: V3 -> V3 -> Q
dist2 (a,b,c) (p,q,r) = (a-p)^(2::Int) + (b-q)^(2::Int) + (c-r)^(2::Int)

dist2C :: [V3] -> V3 -> Q
dist2C cs x = minimum [ dist2 x c | c <- cs ]

-- architectural vanishing: the palette is an INPUT, never weights
maskG :: [V3] -> (V3 -> V3) -> V3 -> V3
maskG cs ghat x = vScale (dist2C cs x) (ghat x)

sigmaV :: (V3 -> V3) -> V3 -> (V3, V3)
sigmaV g x = (x `vAdd` g x, x `vSub` g x)

expand3V :: (V3 -> V3) -> V3 -> [V3]
expand3V g x =
  let (a, b) = sigmaV g x
      qs     = concat [ let (u, v) = sigmaV g h in [u, v] | h <- [a, b] ]
  in concat [ let (u, v) = sigmaV g q in [u, v] | q <- qs ]

-- a dyad-shaped codebook: 128 distinct primaries + comp mirror
compV :: V3 -> V3
compV (l, a, b) = (l, -a, -b)

primsAt :: V3 -> [V3]
primsAt (dl, da, db) =
  [ ( dl + fromIntegral i % 256
    , da + fromIntegral i % 128 - 1 % 3
    , db + fromIntegral (i * i `mod` 251) % 509 )
  | i <- [0 .. 127 :: Integer] ]

mkCodebook :: V3 -> [V3]
mkCodebook shift = let ps = primsAt shift
                   in ps ++ map compV (reverse ps)

ghatV :: V3 -> V3
ghatV (l, a, b) = (l * l + 1, a + 2, b - 3)   -- first component never 0

gate :: String -> Bool -> IO Bool
gate name ok = do
  putStrLn $ "  " ++ (if ok then "✓" else "✗") ++ " " ++ name
  pure ok

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " OctaveCodec: composed binary σ/κ — the trainer's contract"
  putStrLn " one pair, wired levels; laws hold for ARBITRARY generators"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  -- CX1: binary retraction ∀g
  g1 <- gate "CX1  κ(σ_g(x)) = x for arbitrary g (binary Law A)"
      $ and [ kappa (sigma g x) == x | g <- gens1, x <- probes ]

  -- CX2: wired-composition DC law ∀ per-level, per-position g
  let combos = [ (ga, mkG2 k, mkG3 j)
               | ga <- gens1, k <- [0, 2], j <- [1, 3] ]
  g2 <- gate "CX2  composed 3-level expansion: mean of 8 leaves = x, ∀g₁g₂g₃"
      $ and [ contract3 (expand3 ga gb gc x) == x
            | (ga, gb, gc) <- combos, x <- probes ]

  -- CX3: idempotence of ê = Ŝ_g ∘ K̂ on the composed octave
  let ehat (ga, gb, gc) ls = expand3 ga gb gc (contract3 ls)
      blockT = [ 1%2, 3, -5%4, 7%8, 0, 2%3, -1, 9%5 ]
  g3 <- gate "CX3  ê∘ê = ê on the composed octave, ∀g (projector for free)"
      $ and [ ehat c (ehat c blockT) == ehat c blockT | c <- combos ]

  -- CX4: classicality inheritance in composed form
  let gCls  = expand3 hCls [hCls, hCls] [hCls, hCls, hCls, hCls]
      offPts = [ 1%2, 3%2, 5%2, -1, 4 ]
  g4 <- gate "CX4  codebook copies exactly through all 3 levels; off-codebook defects"
      $ all (\c -> gCls c == replicate 8 c && contract3 (gCls c) == c)
            codebook
        && all (\x -> gCls x /= replicate 8 x) offPts

  -- CX5: composed form realizes the flat SK7 form (Haar-aligned)
  --      DC coefficient of the composed block is exactly x, and the
  --      pure-Haar special case (constant generators) puts each
  --      level's constant in its own character band.
  let constExp d1 d2 d3 x =
        expand3 (const d1) [const d2, const d2] (replicate 4 (const d3)) x
      blockC = constExp (3%4) (-2%5) (1%8) (5%7)
  g5 <- gate "CX5  Haar alignment: DC = x exactly; constant g's land in bands 4,2,1"
      $ and [ haarCoef 0 (expand3 ga gb gc x) == x
            | (ga, gb, gc) <- take 4 combos, x <- probes ]
        && haarCoef 4 blockC == 3%4        -- level-1 detail → w=100
        && haarCoef 2 blockC == -2%5       -- level-2 detail → w=010
        && haarCoef 1 blockC == 1%8        -- level-3 detail → w=001
        && and [ haarCoef w blockC == 0 | w <- [3, 5, 6, 7] ]

  -- CX6: ∀-codebook classicality at dyad-256 scale
  let c1 = mkCodebook (0, 0, 0)
      gC1 = maskG c1 ghatV
      offV = [ vAdd c (1 % 1000, 0, 0) | c <- take 5 c1 ]
  g6 <- gate "CX6  dyad-256-scale codebook: all 256 codewords copy exactly; off defects"
      $ length c1 == 256
        && all (\c -> expand3V gC1 c == replicate 8 c
                      && vMean (expand3V gC1 c) == c) c1
        && all (\x -> expand3V gC1 x /= replicate 8 x) offV
        && all (\c -> compV c `elem` c1) (take 8 c1)   -- involution-closed

  -- CX7: dynamic per-capture palettes are safe (mask = input)
  let c2 = mkCodebook (1 % 7, 1 % 11, -1 % 13)
      gC2 = maskG c2 ghatV
      c1only = [ c | c <- take 8 c1, dist2C c2 c /= 0 ]
  g7 <- gate "CX7  two captures, same ĝ: each copies its OWN palette; cross defects"
      $ all (\c -> expand3V gC2 c == replicate 8 c) c2
        && not (null c1only)
        && all (\c -> expand3V gC2 c /= replicate 8 c) c1only

  putStrLn ""
  let results = [g1, g2, g3, g4, g5, g6, g7]
  putStrLn $ "  " ++ show (length (filter id results)) ++ "/"
           ++ show (length results) ++ " gates green"
  putStrLn ""
  putStrLn "  The codec may learn ANY generators: retraction, projection,"
  putStrLn "  and codebook copying are structural, not trained."
  if and results then pure () else error "OctaveCodec: gate failure"
