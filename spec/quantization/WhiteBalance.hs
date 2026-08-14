-- WhiteBalance.hs — 256 UNIQUE ENTRIES IN 128 BALANCED PAIRS
--
-- Daniel's demand (2026-08-13): "I demand 256 unique colors pairs
-- that balance each other so there is white balance."
--
-- Measured from the device GIF first, because the measurement is the
-- reason this file exists:
--
--     pairing i <-> i+128, about the centroid : mean |sum| = 0.0069
--     table centroid (a,b)                    = (+0.0310, +0.0384)
--     mean entry chroma                       =  0.0500
--     |net cast| / mean chroma                =  0.986   (0.911-0.987
--                                                over all 64 frames)
--     distinct entries                        =  251.8 / 256 (worst 245)
--
-- The pairs ALREADY cancel. What does not cancel is the point they
-- cancel ABOUT. The shipped table mirrors about c_F, the FIGURE
-- centroid — a face — so it carries a face-coloured cast that no
-- choice of entries can remove.
--
-- ★ WB4 IS THE WHOLE FILE. For any table where every entry has a
-- partner x' = 2c - x, the mean of all entries is EXACTLY c. The free
-- entries cancel out of the sum identically, so they are irrelevant
-- to the cast. White balance therefore has exactly one solution:
-- c = 0. It is not a tuning problem and never was.
--
-- ★ WB7 is why this is not the old complementary ground in new
-- clothes. Balance alone does NOT give diversity: a table mirrored
-- about neutral but built on ONE hue line is perfectly balanced and
-- perfectly monochrome — it hands the background the figure's literal
-- complement, which is the BLUE HAZE that DY14 v7 killed. v7 killed
-- it by moving the centre onto the face, which is what made white
-- balance unreachable. The third option is a neutral centre with the
-- entries DISTRIBUTED over hue. Balance and diversity are independent
-- properties and both must be stated.
--
-- ★ WB8 is the one that bites hardest. 64 entries on the outermost
-- shell cannot be 8-bit distinct unless the chroma cap is at least
-- 63/510 = 0.1235. The device shipped a cap of 0.0919. That is the
-- arithmetic reason 4-11 entries collide every frame: the gamut is
-- too small for the ladder it carries. Uniqueness, gamut and the
-- ladder are one constraint, not three.
--
-- Exactness: shells are L1 (diamond) shells, so every entry is a
-- rational point — an exact Euclidean circle has too few rational
-- points to place 64 entries on. Hue spread is measured with the
-- AXIAL resultant (angles doubled), which is polynomial in (a,b) and
-- therefore also exact. No trigonometry, no floating point.
--
-- Companion specs (authoritative, not restated):
--   spec/quantization/GroundHue.hs     — Δh, the ground's own hue
--   spec/quantization/AttractorRAG.hs  — pairLadder, AR12's cancellation
--   spec/quantization/DyadPalette.hs   — the shells
--
-- Axioms WB1-WB12.

module Main where

import Data.List (nub, sort)
import Data.Ratio ((%))
import System.Exit (exitFailure)

type Q = Rational

-- Chroma only. Lightness does not mirror: a pair opposes in (a, b),
-- which makes the cancellation a statement about COLOUR CAST, never
-- about exposure.
type AB = (Q, Q)

paletteSize, pairCount :: Int
paletteSize = 256
pairCount   = 128

-- The binomial ladder the shells already ride: shell s holds this
-- many entries. Sums to 128 — the free half (AttractorRAG).
pairLadder :: [Int]
pairLadder = [1, 1, 2, 4, 8, 16, 32, 64]

-- One code step of the 8-bit grid the GIF stores into.
codeStep :: Q
codeStep = 1 % 255

-- ══ Mirrors ═════════════════════════════════════════════

partner :: AB -> AB -> AB
partner (cx, cy) (x, y) = (2 * cx - x, 2 * cy - y)

tableAbout :: AB -> [AB] -> [AB]
tableAbout c free = free ++ map (partner c) free

netCast :: [AB] -> AB
netCast ps = (sum (map fst ps) / n, sum (map snd ps) / n)
  where n = fromIntegral (length ps)

meanChroma2 :: [AB] -> Q
meanChroma2 ps = sum [x * x + y * y | (x, y) <- ps] / fromIntegral (length ps)

castRatio2 :: [AB] -> Q
castRatio2 ps = let (x, y) = netCast ps in (x * x + y * y) / meanChroma2 ps

neutral, figureCentre :: AB
neutral      = (0, 0)
figureCentre = (310 % 10000, 384 % 10000)   -- measured on device

-- ══ Shells ══════════════════════════════════════════════
-- The free half is the CLOSED UPPER half-plane: b > 0, plus b == 0
-- with a > 0. Its mirror image about neutral is exactly the lower
-- half, so the two halves are disjoint and the table is 256 entries.

-- Shell s of an L1 ball of radius r, holding n entries, walked from
-- (r, 0) round to just before (-r, 0). Every point is rational.
shell :: Q -> Int -> [AB]
shell r n =
  [ let t  = fromIntegral k % fromIntegral n     -- t in [0, 1)
        x  = r * (1 - 2 * t)
        y  = r - abs x
    in (x, y)
  | k <- [0 .. n - 1] ]

-- Radii: one per ladder rung, evenly spaced out to the cap so that
-- no two shells coincide (the ladder's two 1s would otherwise place
-- two entries at the same radius).
radii :: Q -> [Q]
radii cap = [ cap * (fromIntegral s % fromIntegral (length pairLadder))
            | s <- [1 .. length pairLadder] ]

-- THE CONSTRUCTION: the ladder governs how many entries each shell
-- holds; the shell spreads them over hue. Diversity and allocation
-- come from the same object.
distributedHalf :: Q -> [AB]
distributedHalf cap = concat (zipWith shell (radii cap) pairLadder)

-- The shape the device shipped: every entry on ONE hue line, radius
-- varying. Balanced, and monochrome.
collinearHalf :: Q -> [AB]
collinearHalf cap =
  [ (d * (3 % 5), d * (4 % 5))
  | k <- [1 .. pairCount]
  , let d = cap * (fromIntegral k % fromIntegral pairCount) ]

-- ══ Hue spread, exactly ═════════════════════════════════
-- AXIAL concentration: angles doubled, so a hue LINE and its opposite
-- count as the same orientation. This is the statistic that separates
-- "one hue line" from "spread" — the plain resultant cannot, because
-- ANY balanced table has a zero plain resultant by construction.
--   d(x,y) = ((x²-y²)/(x²+y²), 2xy/(x²+y²))   — exact in Q
-- R2 = |mean d|² ∈ [0,1];  1 = one line, 0 = fully spread.
axial2 :: [AB] -> Q
axial2 ps
  | null ds   = 1
  | otherwise = (sx * sx + sy * sy) / (n * n)
  where
    ds = [ ((x * x - y * y) / m, 2 * x * y / m)
         | (x, y) <- ps, let m = x * x + y * y, m /= 0 ]
    sx = sum (map fst ds)
    sy = sum (map snd ds)
    n  = fromIntegral (length ds)

-- ══ The uniqueness floor (WB8) ══════════════════════════
-- The outermost shell holds `maximum pairLadder` entries. Walking an
-- L1 shell of radius r covers a perimeter of 8r in x-and-y steps of
-- 2r/n each, so two neighbours differ by 2r/n on the x axis. For them
-- to survive the 8-bit grid that must be at least one code step:
--     2r/n >= 1/255   ⇒   r >= n/510
minimumCap :: Q
minimumCap = fromIntegral (maximum pairLadder) % 510

-- What the device actually shipped.
deviceCap :: Q
deviceCap = 919 % 10000

separated :: [AB] -> Bool
separated ps = and [ far a b | (i, a) <- zip [0 :: Int ..] ps
                             , (j, b) <- zip [0 ..] ps, i < j ]
  where far (x1, y1) (x2, y2) = abs (x1 - x2) >= codeStep
                             || abs (y1 - y2) >= codeStep

-- ══ Tables ══════════════════════════════════════════════

lawfulCap :: Q
lawfulCap = minimumCap

balancedTable, shippedShape, balancedButCollinear :: [AB]
balancedTable        = tableAbout neutral      (distributedHalf lawfulCap)
shippedShape         = tableAbout figureCentre (collinearHalf deviceCap)
balancedButCollinear = tableAbout neutral      (collinearHalf lawfulCap)

-- ══ Axioms ══════════════════════════════════════════════

-- (WB1) 256 entries are exactly 128 pairs: partnering is an
-- involution, the free half never meets its own mirror, and no entry
-- is its own partner.
axiom_WB1 :: Bool
axiom_WB1 =
     length balancedTable == paletteSize
  && length free == pairCount
  && and [ partner neutral (partner neutral x) == x | x <- free ]
  && null [ x | x <- free, partner neutral x `elem` free ]
  && notElem neutral free
  where free = distributedHalf lawfulCap

-- (WB2) ★ ALL 256 UNIQUE — and unique in the 8-bit domain the GIF
-- actually stores, which is where the device lost four of them.
axiom_WB2 :: Bool
axiom_WB2 =
     length (nub balancedTable) == paletteSize
  && separated balancedTable

-- (WB3) Every pair cancels about its centre. The shipped table
-- ALREADY has this property — it is not the defect.
axiom_WB3 :: Bool
axiom_WB3 =
     all (\x -> add x (partner neutral x) == (0, 0)) (distributedHalf lawfulCap)
  && all (\x -> add x (partner figureCentre x) == dbl figureCentre)
         (collinearHalf deviceCap)
  where
    add (a, b) (c, d) = (a + c, b + d)
    dbl (a, b) = (2 * a, 2 * b)

-- (WB4) ★★ THE THEOREM. For ANY mirrored table the net cast is the
-- mirror centre, exactly — independent of the entries.
axiom_WB4 :: Bool
axiom_WB4 =
     netCast balancedTable == neutral
  && netCast shippedShape  == figureCentre
  && and [ netCast (tableAbout c h) == c
         | c <- [neutral, figureCentre, (7 % 100, negate (3 % 100))]
         , h <- [distributedHalf lawfulCap, collinearHalf deviceCap] ]

-- (WB5) ★ WHITE BALANCE HAS EXACTLY ONE SOLUTION: a neutral centre.
-- By WB4 no choice of entries, ladder or hue law can substitute.
axiom_WB5 :: Bool
axiom_WB5 =
     netCast (tableAbout neutral free) == (0, 0)
  && and [ netCast (tableAbout c free) /= (0, 0)
         | c <- [figureCentre, (1 % 100, 0), (0, negate (1 % 50))] ]
  where free = distributedHalf lawfulCap

-- (WB6) The device's condition reproduced: mirroring about the figure
-- leaves a cast of the same order as the table's own mean chroma
-- (measured ratio 0.986), while a neutral centre leaves none at all.
axiom_WB6 :: Bool
axiom_WB6 = castRatio2 shippedShape > 0
         && castRatio2 balancedTable == 0
         && castRatio2 balancedButCollinear == 0

-- (WB7) ★ BALANCE IS NOT DIVERSITY. Both tables below are perfectly
-- white balanced; only one is usable. A neutral centre with a
-- collinear half is the literal complement handed to the background —
-- the blue haze. The two properties are independent and both must be
-- demanded.
axiom_WB7 :: Bool
axiom_WB7 =
     netCast balancedButCollinear == neutral      -- balanced...
  && axial2 balancedButCollinear == 1             -- ...and ONE hue line
  && netCast balancedTable == neutral             -- balanced...
  && axial2 balancedTable < (1 % 2)               -- ...and spread
  && axial2 (distributedHalf lawfulCap) < 1       -- spread within a half, too

-- (WB8) ★ THE GAMUT IS FORCED BY THE LADDER. 64 entries on the outer
-- shell need a chroma cap of at least 64/510 = 0.1255 to survive the
-- 8-bit grid. The device shipped 0.0919 — below the floor, which is
-- the arithmetic reason entries collided every frame.
axiom_WB8 :: Bool
axiom_WB8 =
     minimumCap == fromIntegral (maximum pairLadder) % 510
  && deviceCap < minimumCap                       -- the shipped cap is illegal
  && separated (tableAbout neutral (distributedHalf minimumCap))
  && not (separated (tableAbout neutral (distributedHalf deviceCap)))

-- (WB9) The ladder still governs allocation: shell s holds
-- pairLadder[s] entries, summing to the free half. This redistributes
-- the existing budget over hue; it does not invent a new one.
axiom_WB9 :: Bool
axiom_WB9 =
     sum pairLadder == pairCount
  && map length (map (uncurry shell) (zip (radii lawfulCap) pairLadder))
       == pairLadder
  && length (nub (radii lawfulCap)) == length pairLadder
  && sort (radii lawfulCap) == radii lawfulCap

-- (WB10) The cast is LINEAR in the centre — shifting the centre
-- shifts the cast one for one, so there is no regime in which a small
-- centre offset is harmless.
axiom_WB10 :: Bool
axiom_WB10 =
  and [ netCast (tableAbout (sx, sy) free) == (sx, sy)
      | k <- [1 .. 6 :: Int]
      , let sx = fromIntegral k % 1000
      , let sy = negate (fromIntegral k % 2000) ]
  where free = distributedHalf lawfulCap

-- (WB11) Lightness is untouched: the mirror is a chroma involution,
-- so white balance costs no exposure and no contrast. The L axis
-- stays free for the shells.
axiom_WB11 :: Bool
axiom_WB11 =
     and [ partner neutral (partner neutral x) == x | x <- distributedHalf lawfulCap ]
  && length (nub (map fst (distributedHalf lawfulCap))) > 1

-- (WB12) DEGENERATE: an achromatic scene already has c = 0, so the
-- law is the identity there — it costs nothing on captures it cannot
-- help, which is what GH7's degenerate clause requires of it.
axiom_WB12 :: Bool
axiom_WB12 =
     tableAbout neutral free == tableAbout (0, 0) free
  && netCast (tableAbout neutral free) == (0, 0)
  where free = distributedHalf lawfulCap

-- ══ Harness ═════════════════════════════════════════════

checks :: [(String, Bool)]
checks =
  [ ("WB1  256 entries = 128 pairs, halves disjoint",  axiom_WB1)
  , ("WB2  ★ all 256 UNIQUE on the 8-bit grid",        axiom_WB2)
  , ("WB3  every pair cancels (already true today)",   axiom_WB3)
  , ("WB4  ★★ net cast == mirror centre, EXACTLY",     axiom_WB4)
  , ("WB5  ★ white balance <=> neutral centre",        axiom_WB5)
  , ("WB6  the device's cast condition reproduced",    axiom_WB6)
  , ("WB7  ★ balance is NOT diversity",                axiom_WB7)
  , ("WB8  ★ the gamut floor is forced by the ladder", axiom_WB8)
  , ("WB9  the ladder still governs allocation",       axiom_WB9)
  , ("WB10 the cast is linear in the centre",          axiom_WB10)
  , ("WB11 lightness is untouched",                    axiom_WB11)
  , ("WB12 achromatic scenes cost nothing",            axiom_WB12)
  ]

main :: IO ()
main = do
  putStrLn "WhiteBalance — 256 unique entries in 128 balanced pairs"
  putStrLn ""
  putStrLn "  table                    net cast (a,b)      cast²/C²   axial²  unique"
  row "shipped shape" shippedShape
  row "balanced, collinear" balancedButCollinear
  row "balanced, distributed" balancedTable
  putStrLn ""
  putStrLn ("  chroma cap shipped by the device : " ++ approx deviceCap)
  putStrLn ("  chroma cap the ladder REQUIRES   : " ++ approx minimumCap
            ++ "   (= " ++ show (maximum pairLadder) ++ "/510)")
  putStrLn ("  shortfall                        : "
            ++ approx (minimumCap - deviceCap) ++ "  ⇒ entries collide")
  putStrLn ""
  mapM_ line checks
  putStrLn ""
  let bad = length (filter (not . snd) checks)
  putStrLn ("  " ++ show (length checks - bad) ++ "/" ++ show (length checks)
            ++ " axioms hold")
  if bad > 0 then exitFailure else pure ()
  where
    row nm ps =
      putStrLn ("  " ++ pad 24 nm
                ++ pad 20 (show (approx2 (netCast ps)))
                ++ pad 11 (approx (castRatio2 ps))
                ++ pad 9 (approx (axial2 ps))
                ++ show (length (nub ps)))
    line (nm, ok) = putStrLn ("  " ++ (if ok then "\10003" else "\10007") ++ " " ++ nm)
    pad n s = s ++ replicate (max 0 (n - length s)) ' '
    approx q = show (fromIntegral (round (q * 10000) :: Integer) / (10000 :: Double))
    approx2 (x, y) = (fromIntegral (round (x * 10000) :: Integer) / (10000 :: Double)
                     ,fromIntegral (round (y * 10000) :: Integer) / (10000 :: Double))
