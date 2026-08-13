{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- PhaseTiling: the 64³ tiled by phase, with the energy computed in
-- OKLab — the correct space
--
-- Daniel (2026-08-13): "I need tight phase diagram energy
-- computation so that I can tile the 64³ … please do the energy
-- calculation in the correct color space!"
--
-- ── WHY THE SPACE IS THE WHOLE POINT (PD1, PD2) ─────────────────
--
-- A domain-wall count — "do these two cells differ?" — is a
-- COLOURBLIND energy. It cannot tell a wall between two near-
-- identical greens from a wall between black and white; both cost
-- exactly 1. Tiling on that energy would place boundaries where
-- indices happen to change rather than where the image changes.
--
-- In OKLab the metric is Euclidean AND perceptual, so
--
--   E = Σ over adjacent cells ‖c_p − c_q‖²
--
-- is a genuine quadratic form whose value is squared perceptual
-- distance. That is the only reason this energy can be both TIGHT
-- (additive, incremental) and MEANINGFUL (a wall costs what it
-- looks like it costs). PD2 exhibits a configuration where the two
-- energies rank tiles in DIFFERENT ORDERS — the colourblind form
-- is not an approximation of the right one, it is a different
-- answer.
--
-- PhaseEnergy.hs already works in OKLab for E_pal (chroma² over
-- the a,b axes). This file extends the same discipline to E_dist,
-- which the earlier draft of FeedCompression got wrong.
--
-- ── WHAT "TIGHT" MEANS (PD3, PD9) ───────────────────────────────
--
-- Additive: E(cube) = Σ tile interiors + walls, EXACTLY. And
-- incremental: re-solving ONE tile changes E by that tile's
-- interior delta plus its own wall delta, touching no other tile's
-- interior. That is what makes a full 64³ re-solve per tick
-- affordable — 4096 tiles, each independently recomputable.
--
-- ── THE TILING IS THE BOUNDARY (PD7, PD8) ───────────────────────
--
-- Depth gives the user/background split (FeedCompression FC6), and
-- RoleAllocation spends the entropy budget across it. At tile
-- granularity that split has exactly three phases:
--
--   FACE   φ = 0   every cell figure   — deep palette, d_F = 7
--   SOLID  φ = 1   every cell ground   — shallow palette, d_B
--   BAND   0<φ<1   mixed               — THE BOUNDARY
--
-- No threshold is invented: the classifier reads only whether the
-- σ-fraction is 0, 1, or neither. m_st (the staggered
-- magnetisation, PhaseEnergy's Néel detector for the Bayer band)
-- and s (index entropy) are MEASURED per tile and reported — never
-- used as axes. PhaseEnergy's honesty note applies unchanged.
--
-- ★ PD10: the BAND tiles are where the rate goes. They are the
-- only tiles carrying both depths, so the boundary's tile-area is
-- the app's real bit budget — and it is a tiny fraction of the
-- cube.
--
-- ── AXIOMS ──────────────────────────────────────────────────────
--
--   PD1  the energy is Euclidean in OKLab: symmetric, non-negative,
--        zero exactly on identical colours, and a true metric²
--   PD2  ★ OKLab ≠ index-count: the two energies RANK TILES
--        DIFFERENTLY, so the colourblind form is a different
--        answer, not a cheap approximation
--   PD3  additivity: E = Σ tile interiors + walls, exactly
--   PD4  ★ gauge invariance: E is unchanged by any isometry of
--        OKLab — it sees structure, never absolute colour
--   PD5  σ-invariance: the involution (negating a, b) preserves E
--   PD6  κ contracts: pooling to a coarser rung lowers energy per
--        bond — coarse rungs are literally calmer
--   PD7  the phase of a tile is a TOTAL function of φ; the three
--        phases are exhaustive and mutually exclusive
--   PD8  the tiling is total: every cell lies in exactly one tile,
--        every tile carries exactly one phase
--   PD9  ★ incrementality: editing one tile changes only its own
--        interior term and its own walls
--   PD10 ★ the boundary is thin: BAND tiles are a small minority,
--        and they are exactly the tiles needing both palettes
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.List (nub, sort, sortOn)
import Data.Ratio ((%))

type Q = Rational

-- | OKLab. The L axis is lightness; (a, b) are the opponent axes.
--   Distance is Euclidean here BY CONSTRUCTION — that is what the
--   space is for.
type Lab = (Q, Q, Q)

labSub :: Lab -> Lab -> Lab
labSub (l1, a1, b1) (l2, a2, b2) = (l1 - l2, a1 - a2, b1 - b2)

-- | Squared perceptual distance: ΔE_OK². The energy's bond weight.
dE2 :: Lab -> Lab -> Q
dE2 p q = let (dl, da, db) = labSub p q in dl * dl + da * da + db * db

-- | The σ involution: the complement negates the opponent axes and
--   keeps lightness (DyadPalette's comp, PhaseEnergy PE2).
comp :: Lab -> Lab
comp (l, a, b) = (l, negate a, negate b)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE CUBE
--
-- Model at side 8 tiled by 2³ (64 tiles), standing for 64³ tiled
-- by 4³ (4096 tiles). The decomposition is size-independent.
-- ════════════════════════════════════════════════════════════════

modelSide, modelTile :: Int
modelSide = 8
modelTile = 2

paletteSize :: Int
paletteSize = 256

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

-- | The palette: 128 figure primaries and their σ mirrors. Index
--   i < 128 is figure; 255 − i is its ground partner.
palette :: [Lab]
palette = figs ++ map comp (reverse figs)
  where
    figs = [ ( fromIntegral (lcg (i * 7 + 1) `mod` 900 + 50) % 1000
             , fromIntegral (lcg (i * 13 + 2) `mod` 400 - 200) % 1000
             , fromIntegral (lcg (i * 29 + 5) `mod` 400 - 200) % 1000 )
           | i <- [0 .. 127] ]

colourOf :: Int -> Lab
colourOf i = palette !! (i `mod` paletteSize)

type Cube = [Int]                      -- one palette index per cell

coords :: Int -> [(Int, Int, Int)]
coords n = [ (t, y, x) | t <- [0 .. n-1], y <- [0 .. n-1], x <- [0 .. n-1] ]

idx :: (Int, Int, Int) -> Int
idx (t, y, x) = t * modelSide * modelSide + y * modelSide + x

cellAt :: Cube -> (Int, Int, Int) -> Int
cellAt c p = c !! idx p

-- | A cube with a figure region, a ground region and a boundary —
--   the shape depth actually produces.
cube :: Cube
cube =
  [ if inFigure p
      then lcg (idx p * 3 + 1) `mod` 128            -- figure half
      else 255 - (lcg (idx p * 5 + 2) `mod` 16)     -- ground, shallow
  | p <- coords modelSide ]
  where
    inFigure (t, y, x) = (y - 4) * (y - 4) + (x - 4) * (x - 4) <= 4 + t `mod` 2

-- ════════════════════════════════════════════════════════════════
-- § 2. BONDS, TILES, AND THE ENERGY
-- ════════════════════════════════════════════════════════════════

type Bond = ((Int, Int, Int), (Int, Int, Int))

-- | Every adjacent pair, over all three axes — TIME included.
bonds :: [Bond]
bonds =
  [ (p, q)
  | p@(t, y, x) <- coords modelSide
  , q <- [ (t+1, y, x), (t, y+1, x), (t, y, x+1) ]
  , inside q ]
  where inside (t, y, x) = all (\v -> v >= 0 && v < modelSide) [t, y, x]

-- | ★ THE ENERGY, IN OKLab. Squared perceptual distance per bond.
energy :: Cube -> [Bond] -> Q
energy c bs = sum [ dE2 (colourOf (cellAt c p)) (colourOf (cellAt c q))
                  | (p, q) <- bs ]

-- | The colourblind alternative, kept only to be refuted (PD2).
energyIndex :: Cube -> [Bond] -> Q
energyIndex c bs =
  fromIntegral (length [ () | (p, q) <- bs, cellAt c p /= cellAt c q ])

tileOf :: (Int, Int, Int) -> (Int, Int, Int)
tileOf (t, y, x) = (t `div` modelTile, y `div` modelTile, x `div` modelTile)

tiles :: [(Int, Int, Int)]
tiles = coords (modelSide `div` modelTile)

cellsOfTile :: (Int, Int, Int) -> [(Int, Int, Int)]
cellsOfTile (tb, yb, xb) =
  [ (tb * modelTile + dt, yb * modelTile + dy, xb * modelTile + dx)
  | dt <- [0 .. modelTile-1], dy <- [0 .. modelTile-1], dx <- [0 .. modelTile-1] ]

interiorBonds, wallBonds :: [Bond]
interiorBonds = [ b | b@(p, q) <- bonds, tileOf p == tileOf q ]
wallBonds     = [ b | b@(p, q) <- bonds, tileOf p /= tileOf q ]

bondsOfTile :: (Int, Int, Int) -> [Bond]
bondsOfTile tl = [ b | b@(p, q) <- interiorBonds, tileOf p == tl, tileOf q == tl ]

tileEnergy :: Cube -> (Int, Int, Int) -> Q
tileEnergy c tl = energy c (bondsOfTile tl)

-- ════════════════════════════════════════════════════════════════
-- § 3. THE ORDER PARAMETERS AND THE PHASE
--
-- PhaseEnergy's triple, computed tile-local. φ is the ONLY thing
-- the classifier reads; m_st and s are measured and reported.
-- ════════════════════════════════════════════════════════════════

isGround :: Int -> Bool
isGround i = i >= 128

-- | φ: the σ-side fraction (the magnetisation analogue).
phi :: Cube -> (Int, Int, Int) -> Q
phi c tl =
  fromIntegral (length [ () | p <- cs, isGround (cellAt c p) ])
    % fromIntegral (length cs)
  where cs = cellsOfTile tl

-- | m_st: the STAGGERED magnetisation — PhaseEnergy's Néel
--   detector for the Bayer band. Alternating signs on the
--   spacetime checkerboard.
mSt :: Cube -> (Int, Int, Int) -> Q
mSt c tl =
  abs (sum [ sign p * spin p | p <- cs ]) % 1 / fromIntegral (length cs)
  where
    cs = cellsOfTile tl
    sign (t, y, x) = if even (t + y + x) then 1 else -1
    spin p = if isGround (cellAt c p) then 1 else -1

-- | s: index diversity within the tile, normalised by tile size.
sDiv :: Cube -> (Int, Int, Int) -> Q
sDiv c tl =
  fromIntegral (length (nub [ cellAt c p | p <- cs ]))
    % fromIntegral (length cs)
  where cs = cellsOfTile tl

data Phase = FACE | BAND | SOLID deriving (Eq, Ord, Show, Enum, Bounded)

-- | Total, and constant-free: the classifier reads only whether
--   the σ-fraction is 0, 1, or neither.
phaseOf :: Cube -> (Int, Int, Int) -> Phase
phaseOf c tl
  | p == 0 = FACE
  | p == 1 = SOLID
  | otherwise = BAND
  where p = phi c tl

tiling :: Cube -> [((Int, Int, Int), Phase)]
tiling c = [ (tl, phaseOf c tl) | tl <- tiles ]

-- ════════════════════════════════════════════════════════════════
-- § 4. κ IN OKLab (the pooling that must NOT happen in sRGB)
-- ════════════════════════════════════════════════════════════════

labMean :: [Lab] -> Lab
labMean [] = (0, 0, 0)
labMean vs =
  let n = fromIntegral (length vs)
      (sl, sa, sb) = foldr (\(l, a, b) (x, y, z) -> (x + l, y + a, z + b))
                           (0, 0, 0) vs
  in (sl / n, sa / n, sb / n)

-- | The colour field of the cube, and its κ-pool. Pooling is done
--   on COLOURS in OKLab — never on indices, which are labels.
field :: Cube -> [Lab]
field c = map (colourOf . cellAt c) (coords modelSide)

poolLab :: Int -> [Lab] -> [Lab]
poolLab n f =
  [ labMean [ f !! (tt * n * n + yy * n + xx)
            | dt <- [0,1], dy <- [0,1], dx <- [0,1]
            , let tt = 2*tb+dt, let yy = 2*yb+dy, let xx = 2*xb+dx ]
  | tb <- [0 .. h-1], yb <- [0 .. h-1], xb <- [0 .. h-1] ]
  where h = n `div` 2

bondsAt :: Int -> [Bond]
bondsAt n =
  [ (p, q)
  | p@(t, y, x) <- coords n
  , q <- [ (t+1, y, x), (t, y+1, x), (t, y, x+1) ]
  , inside q ]
  where inside (t, y, x) = all (\v -> v >= 0 && v < n) [t, y, x]

energyField :: Int -> [Lab] -> Q
energyField n f =
  sum [ dE2 (f !! ix p) (f !! ix q) | (p, q) <- bondsAt n ]
  where ix (t, y, x) = t * n * n + y * n + x

-- ════════════════════════════════════════════════════════════════
-- § 5. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (PD1) The energy is a squared Euclidean metric in OKLab:
--       symmetric, non-negative, and zero exactly when the colours
--       coincide. (In sRGB none of this would mean anything
--       perceptual; in OKLab it is ΔE².)
axiom_PD1 :: Bool
axiom_PD1 =
     all (\(p, q) -> dE2 p q == dE2 q p) pairs
  && all (\(p, q) -> dE2 p q >= 0) pairs
  && all (\p -> dE2 p p == 0) sample
  && all (\(p, q) -> (dE2 p q == 0) == (p == q)) pairs
  && energy cube bonds > 0
  where
    sample = take 12 palette
    pairs  = [ (p, q) | p <- sample, q <- sample ]

-- (PD2) ★ THE COLOUR SPACE CHANGES THE ANSWER. The OKLab energy
--       and the index count RANK TILES DIFFERENTLY — so the
--       colourblind form is not a cheap approximation of the right
--       one, it is a different answer. A tiling built on it would
--       place boundaries where indices change rather than where
--       the image changes.
axiom_PD2 :: Bool
axiom_PD2 =
     rankLab /= rankIdx
  && energy cube bonds /= energyIndex cube bonds
  && any (\tl -> tileEnergy cube tl /= energyIndex cube (bondsOfTile tl)) tiles
  where
    rankLab = map fst (sortOn (negate . snd)
                [ (tl, tileEnergy cube tl) | tl <- tiles ])
    rankIdx = map fst (sortOn (negate . snd)
                [ (tl, energyIndex cube (bondsOfTile tl)) | tl <- tiles ])

-- (PD3) Additivity — the tightness law, now with real weights.
--       Bond weights being rationals rather than 0/1 changes
--       nothing about the decomposition.
axiom_PD3 :: Bool
axiom_PD3 =
     energy cube bonds
       == sum (map (tileEnergy cube) tiles) + energy cube wallBonds
  && length interiorBonds + length wallBonds == length bonds
  && null [ b | b <- interiorBonds, b `elem` wallBonds ]
  && sum (map (tileEnergy cube) tiles) == energy cube interiorBonds

-- (PD4) ★ GAUGE INVARIANCE. The energy is built from DIFFERENCES,
--       so any isometry of OKLab — a global lightness shift, a
--       rotation of the (a,b) plane — leaves it exactly unchanged.
--       The energy sees structure, never absolute colour.
axiom_PD4 :: Bool
axiom_PD4 =
     energyField modelSide shifted == energyField modelSide original
  && energyField modelSide swapped == energyField modelSide original
  && energyField modelSide negated == energyField modelSide original
  where
    original = field cube
    shifted  = map (\(l, a, b) -> (l + 3 % 10, a, b)) original
    swapped  = map (\(l, a, b) -> (l, b, a)) original      -- a 90° flip
    negated  = map (\(l, a, b) -> (l, negate a, negate b)) original

-- (PD5) σ-invariance: complementing every colour (the involution
--       that builds the ground half) preserves the energy exactly
--       — PhaseEnergy PE2's statement, for E_dist.
axiom_PD5 :: Bool
axiom_PD5 =
     energyField modelSide (map comp (field cube))
       == energyField modelSide (field cube)
  && all (\p -> comp (comp p) == p) (take 16 palette)

-- (PD6) κ contracts: pooling to the next rung lowers the energy
--       PER BOND — coarse rungs are literally calmer, which is why
--       a starved ground reads as still.
axiom_PD6 :: Bool
axiom_PD6 =
     densityAt 8 (field cube) > densityAt 4 (poolLab 8 (field cube))
  && densityAt 4 (poolLab 8 (field cube))
       > densityAt 2 (poolLab 4 (poolLab 8 (field cube)))
  where
    densityAt n f = energyField n f / fromIntegral (length (bondsAt n))

-- (PD7) The phase is a TOTAL function of φ, and the three phases
--       are exhaustive and mutually exclusive.
axiom_PD7 :: Bool
axiom_PD7 =
     all (\tl -> phaseOf cube tl `elem` [FACE, BAND, SOLID]) tiles
  && all consistent tiles
  && length [minBound .. maxBound :: Phase] == 3
  where
    consistent tl =
      let p = phi cube tl
          f = phaseOf cube tl
      in (f == FACE && p == 0) || (f == SOLID && p == 1)
         || (f == BAND && p > 0 && p < 1)

-- (PD8) The tiling is total: every cell in exactly one tile, every
--       tile exactly one phase, no cell orphaned or doubled.
axiom_PD8 :: Bool
axiom_PD8 =
     sort (concatMap cellsOfTile tiles) == sort (coords modelSide)
  && length (nub (concatMap cellsOfTile tiles)) == modelSide ^ (3 :: Int)
  && length (tiling cube) == length tiles
  && length (nub (map fst (tiling cube))) == length tiles
  && all (\tl -> length (cellsOfTile tl) == modelTile ^ (3 :: Int)) tiles

-- (PD9) ★ INCREMENTALITY. Re-solving ONE tile changes only that
--       tile's interior term and its own walls; every other tile's
--       interior is untouched. This is what licenses a full re-solve
--       per tick — 4096 independent recomputations, not one.
axiom_PD9 :: Bool
axiom_PD9 =
     all unchanged [ tl | tl <- tiles, tl /= target ]
  && tileEnergy edited target /= tileEnergy cube target
  && delta == deltaInterior + deltaWalls
  where
    target  = (1, 1, 1)
    edited  = [ if tileOf p == target then (cellAt cube p + 7) `mod` 128
                                      else cellAt cube p
              | p <- coords modelSide ]
    unchanged tl = tileEnergy edited tl == tileEnergy cube tl
    delta         = energy edited bonds - energy cube bonds
    deltaInterior = tileEnergy edited target - tileEnergy cube target
    deltaWalls    = energy edited wallBonds - energy cube wallBonds

-- (PD10) ★ THE BOUNDARY IS THIN. BAND tiles — the mixed ones — are
--         a minority, and they are exactly the tiles that need both
--         palettes. The rate concentrates on the boundary, which is
--         why figure-first allocation is affordable.
axiom_PD10 :: Bool
axiom_PD10 =
     bandCount > 0                                   -- there IS a boundary
  && bandCount < length tiles                        -- and it is not all
  && faceCount > 0 && solidCount > 0
  && bandCount + faceCount + solidCount == length tiles
  && 2 * bandCount < length tiles                    -- a minority
  && all (\tl -> phaseOf cube tl /= BAND
                 || (phi cube tl > 0 && phi cube tl < 1)) tiles
  where
    phases     = map snd (tiling cube)
    bandCount  = length (filter (== BAND) phases)
    faceCount  = length (filter (== FACE) phases)
    solidCount = length (filter (== SOLID) phases)

-- ════════════════════════════════════════════════════════════════
-- § 6. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " PhaseTiling: the cube tiled by phase, energy in OKLab"
  putStrLn " a bond costs ΔE² — what the wall LOOKS like it costs"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The tiling ──"
  putStrLn ""
  let phases = map snd (tiling cube)
      count p = length (filter (== p) phases)
  putStrLn $ "  tiles  : " ++ show (length tiles)
           ++ "   (model 2³ over 8³; the app is 4³ over 64³ = 4096)"
  putStrLn $ "  FACE   : " ++ show (count FACE)  ++ "   φ = 0, all figure — deep palette"
  putStrLn $ "  BAND   : " ++ show (count BAND)  ++ "   0 < φ < 1 — ★ THE BOUNDARY"
  putStrLn $ "  SOLID  : " ++ show (count SOLID) ++ "   φ = 1, all ground — shallow palette"
  putStrLn ""

  putStrLn "── Energy, both ways ──"
  putStrLn ""
  putStrLn $ "  OKLab  ΔE² total : "
           ++ showQ (energy cube bonds)
  putStrLn $ "  index count      : "
           ++ showQ (energyIndex cube bonds) ++ "   (colourblind)"
  putStrLn $ "  interiors + walls: "
           ++ showQ (sum (map (tileEnergy cube) tiles))
           ++ " + " ++ showQ (energy cube wallBonds)
  putStrLn ""

  putStrLn "── Energy density falls with the rung (PD6) ──"
  putStrLn ""
  let f0 = field cube
      f1 = poolLab 8 f0
      f2 = poolLab 4 f1
      dens n f = energyField n f / fromIntegral (length (bondsAt n))
  putStrLn $ "  rung 8³ : " ++ showQ (dens 8 f0)
  putStrLn $ "  rung 4³ : " ++ showQ (dens 4 f1)
  putStrLn $ "  rung 2³ : " ++ showQ (dens 2 f2)
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "PD1  energy is ΔE² in OKLab: symmetric, ≥0, zero iff equal" [axiom_PD1]
  check "PD2  ★ OKLab and index-count RANK TILES DIFFERENTLY"        [axiom_PD2]
  check "PD3  additivity: E = Σ tile interiors + walls, exactly"     [axiom_PD3]
  check "PD4  ★ gauge invariance under any OKLab isometry"           [axiom_PD4]
  check "PD5  σ-invariance: the involution preserves E"              [axiom_PD5]
  check "PD6  κ contracts: coarser rungs are calmer per bond"        [axiom_PD6]
  check "PD7  phase is total in φ; FACE/BAND/SOLID exhaustive"       [axiom_PD7]
  check "PD8  the tiling is total: every cell in exactly one tile"   [axiom_PD8]
  check "PD9  ★ incrementality: one tile edits only its own terms"   [axiom_PD9]
  check "PD10 ★ the boundary is thin — BAND is a minority"           [axiom_PD10]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  A domain-wall COUNT cannot tell a wall between two"
  putStrLn "  near-identical greens from a wall between black and"
  putStrLn "  white — both cost 1. In OKLab a bond costs ΔE², so"
  putStrLn "  the energy is what the wall looks like it costs."
  putStrLn ""
  putStrLn "  PD2 shows the two energies rank tiles in DIFFERENT"
  putStrLn "  ORDERS. The colourblind form is not an approximation"
  putStrLn "  of the right one; it is a different answer."
  putStrLn ""
  putStrLn "  The energy stays additive over tiles and incremental"
  putStrLn "  under a single-tile edit, so the correct space costs"
  putStrLn "  nothing in tightness. And because it is built from"
  putStrLn "  DIFFERENCES, it is invariant under every isometry of"
  putStrLn "  OKLab: it sees structure, never absolute colour."
  putStrLn "══════════════════════════════════════════════════════════"

showQ :: Q -> String
showQ q =
  let n = round (q * 1000) :: Integer
      s = if q < 0 then "-" else ""
      m = abs n
      frac = show (m `mod` 1000)
  in s ++ show (m `div` 1000) ++ "."
       ++ replicate (3 - length frac) '0' ++ frac

check :: String -> [Bool] -> IO ()
check name results =
  let passed = and results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
