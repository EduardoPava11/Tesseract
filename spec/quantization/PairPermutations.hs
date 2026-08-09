{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- PairPermutations: GIF89a permutations of the binomial color pairs
--
-- ★REFOCUS (Daniel, 2026-08-09): "We now focus on the model. GIF89a
-- permutations of the binomial color pairs. Go back to beauty and
-- pixelation."
--
-- The object: a 4×4 TILE over a σ-pair — each cell shows either the
-- primary or its partner. Coverage k (how many σ cells) has exactly
-- C(16,k) arrangements: the binomial coefficients ARE the pair's
-- permutation classes. Two theorems make this the model's domain:
--
--   DECOUPLING   the optically mixed color of a tile depends ONLY on
--                k (Neugebauer weight k/16) — permutations move
--                TEXTURE, never COLOR. A model over permutations is
--                structurally incapable of breaking the color laws.
--
--   LAWFULNESS   any permutation of a class-k tile still satisfies
--                the DY6 v3 tile-count law — the model's entire
--                action space is lawful by construction, so XP1
--                holds trivially and XP2's near-tie anxiety
--                vanishes (no distances are perturbed at all).
--
-- Beauty and pixelation are then scores ON arrangements: dispersion
-- (Bayer = the maximally dispersed canonical; k=8 IS the
-- checkerboard) and D4 symmetry order (the Birkhoff instinct:
-- order vs complexity of the visible 4×4 texture).
-- ════════════════════════════════════════════════════════════════

module PairPermutations where

import Data.List (foldl')

-- ════════════════════════════════════════════════════════════════
-- § 1. TILES AND COVERAGE CLASSES
-- ════════════════════════════════════════════════════════════════

tileCells :: Int
tileCells = 16

-- | A tile: 16 Booleans, row-major 4×4; True = the σ side.
type Tile = [Bool]

coverage :: Tile -> Int
coverage = length . filter id

-- | C(n, k)
choose :: Int -> Int -> Integer
choose n k = foldl' (\acc i -> acc * fromIntegral (n - i + 1) `div` fromIntegral i)
                    1 [1 .. k]

-- | All 2^16 tiles (enumerable — the whole permutation universe of
--   one pair fits in a list).
allTiles :: [Tile]
allTiles = mapM (const [False, True]) [1 .. tileCells]

-- ════════════════════════════════════════════════════════════════
-- § 2. THE CANONICAL ARRANGEMENTS (Bayer order)
-- ════════════════════════════════════════════════════════════════

-- | The standard Bayer 4×4 order, row-major (as in DyadPalette §6).
bayerOrder :: [Int]
bayerOrder = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

-- | The canonical class-k tile: the k cells with LOWEST Bayer order.
bayerTile :: Int -> Tile
bayerTile k = [ o < k | o <- bayerOrder ]

-- ════════════════════════════════════════════════════════════════
-- § 3. PERMUTATIONS AND THE D4 ACTION
-- ════════════════════════════════════════════════════════════════

applyPerm :: [Int] -> Tile -> Tile
applyPerm p t = [ t !! i | i <- p ]

-- | Deterministic Fisher–Yates via LCG.
lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

shuffleP :: Int -> [Int]
shuffleP seed = go (uniforms seed) [0 .. tileCells - 1]
  where
    go _ [] = []
    go (u : us) xs =
      let i = min (length xs - 1) (floor (u * fromIntegral (length xs)))
          (a, y : b) = splitAt i xs
      in y : go us (a ++ b)
    go [] _ = error "uniforms is infinite"

-- | The 8 symmetries of the square as index maps on row-major 4×4.
d4 :: [[Int]]
d4 = [ [ idx (f (x, y)) | y <- [0 .. 3], x <- [0 .. 3] ]
     | f <- [ \(x, y) -> (x, y)
            , \(x, y) -> (3 - y, x)
            , \(x, y) -> (3 - x, 3 - y)
            , \(x, y) -> (y, 3 - x)
            , \(x, y) -> (3 - x, y)
            , \(x, y) -> (x, 3 - y)
            , \(x, y) -> (y, x)
            , \(x, y) -> (3 - y, 3 - x) ] ]
  where idx (x, y) = y * 4 + x

-- ════════════════════════════════════════════════════════════════
-- § 4. BEAUTY AND PIXELATION SCORES
-- ════════════════════════════════════════════════════════════════

-- | Pixelation dispersion: count of toroidal 4-neighbor pairs showing
--   the SAME side. Low = dispersed (dither-like), high = clustered.
adjacency :: Tile -> Int
adjacency t = length
  [ () | y <- [0 .. 3], x <- [0 .. 3]
       , (dx, dy) <- [(1, 0), (0, 1)]
       , let a = t !! (y * 4 + x)
       , let b = t !! (((y + dy) `mod` 4) * 4 + ((x + dx) `mod` 4))
       , a == b ]

-- | Beauty order: how many D4 symmetries fix the tile (1..8) — the
--   Birkhoff instinct, order of the visible texture.
symOrder :: Tile -> Int
symOrder t = length [ () | p <- d4, applyPerm p t == t ]

-- | The tile's mixed color weight: σ-side fraction. THE color.
mixWeight :: Tile -> Double
mixWeight t = fromIntegral (coverage t) / fromIntegral tileCells

-- ════════════════════════════════════════════════════════════════
-- § 5. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (PP1) The binomial law: coverage classes partition the 2^16 tiles
--       with sizes exactly C(16, k).
axiom_PP1 :: Bool
axiom_PP1 =
     sum [ choose tileCells k | k <- [0 .. tileCells] ] == 2 ^ tileCells
  && and [ fromIntegral (length [ () | t <- allTiles, coverage t == k ])
             == choose tileCells k
         | k <- [0, 1, 2, 8, 15, 16] ]

-- (PP2) Canonical coverage: the Bayer tile of class k has coverage
--       exactly k, for every k — the DY6 v3 tile-count law's carrier.
axiom_PP2 :: Bool
axiom_PP2 = and [ coverage (bayerTile k) == k | k <- [0 .. tileCells] ]

-- (PP3) Lawfulness: EVERY permutation preserves coverage — the
--       model's action space cannot leave the class. (D4 exactly,
--       and 200 LCG-sampled arbitrary cell permutations.)
axiom_PP3 :: Bool
axiom_PP3 =
     and [ coverage (applyPerm p (bayerTile k)) == k
         | p <- d4, k <- [0 .. tileCells] ]
  && and [ coverage (applyPerm (shuffleP s) (bayerTile k)) == k
         | s <- [1 .. 200], k <- [0, 3, 8, 13] ]

-- (PP4) Decoupling: the mixed color weight depends only on the
--       class, never the arrangement — permutations move texture,
--       not color.
axiom_PP4 :: Bool
axiom_PP4 = and [ mixWeight (applyPerm (shuffleP s) (bayerTile k))
                    == mixWeight (bayerTile k)
                | s <- [1 .. 100], k <- [0 .. tileCells] ]

-- (PP5) Pixelation: Bayer is the dispersion canonical — at every
--       class it has adjacency ≤ every sampled permutation of
--       itself, and class 8 is the perfect checkerboard (adjacency
--       zero, the minimum possible).
axiom_PP5 :: Bool
axiom_PP5 =
     and [ adjacency (bayerTile k)
             <= minimum [ adjacency (applyPerm (shuffleP s) (bayerTile k))
                        | s <- [1 .. 100] ]
         | k <- [2, 4, 6, 8, 10, 12, 14] ]
  && adjacency (bayerTile 8) == 0
  && bayerTile 8 == [ even (x + y) | y <- [0 .. 3 :: Int], x <- [0 .. 3 :: Int] ]

-- (PP6) Beauty order is a D4 class function: conjugate tiles have
--       equal symOrder; the checkerboard's order is 4; bounds 1..8.
axiom_PP6 :: Bool
axiom_PP6 =
     and [ symOrder (applyPerm p t) == symOrder t
         | p <- d4, t <- [ bayerTile k | k <- [0, 3, 8, 12, 16] ] ]
  && symOrder (bayerTile 8) == 4
  && and [ let o = symOrder (applyPerm (shuffleP s) (bayerTile 7))
           in o >= 1 && o <= 8
         | s <- [1 .. 50] ]

-- (PP7) The involution rides along: complementing every cell maps
--       class k to class 16−k and preserves adjacency — σ-swap is a
--       texture-preserving color move, the tile-level image of
--       T[255−i] = comp(T[i]).
axiom_PP7 :: Bool
axiom_PP7 = and
  [ coverage flipped == tileCells - k && adjacency flipped == adjacency t
  | k <- [0 .. tileCells]
  , let t = bayerTile k
  , let flipped = map not t ]

-- ════════════════════════════════════════════════════════════════
-- § 6. MAIN
-- ════════════════════════════════════════════════════════════════

showTile :: Tile -> [String]
showTile t = [ [ if t !! (y * 4 + x) then '█' else '·' | x <- [0 .. 3] ]
             | y <- [0 .. 3] ]

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " PairPermutations: permutations of the binomial pairs"
  putStrLn " color = the class (binomial); beauty = the arrangement"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  class k │ C(16,k) │ Bayer canonical (█ = σ side)"
  putStrLn "  ────────┼─────────┼───────────────"
  mapM_ (\k -> do
          let rows = showTile (bayerTile k)
          putStrLn $ "  " ++ padL 7 (show k) ++ " │ " ++ padL 7 (show (choose 16 k))
                  ++ " │ " ++ head rows
          mapM_ (\r -> putStrLn $ "          │         │ " ++ r) (tail rows))
        [2, 8, 14]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "PP1 binomial law: classes sized C(16,k), Σ = 2^16"          [axiom_PP1]
  check "PP2 Bayer canonical hits every coverage exactly"            [axiom_PP2]
  check "PP3 lawfulness: no permutation can leave its class"         [axiom_PP3]
  check "PP4 decoupling: color = class only, texture = arrangement"  [axiom_PP4]
  check "PP5 pixelation: Bayer = dispersion canonical, k=8 checker"  [axiom_PP5]
  check "PP6 beauty order: D4 class function, bounds hold"           [axiom_PP6]
  check "PP7 σ-flip: class k → 16−k, texture preserved"              [axiom_PP7]
  putStrLn ""
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  A pair's tile has a class and an arrangement. The class"
  putStrLn "  is binomial and IS the color (mix weight k/16, fixed by"
  putStrLn "  the pull law). The arrangement is a permutation and IS"
  putStrLn "  the pixelation. The model lives entirely in arrangement"
  putStrLn "  space: it chooses HOW the pair mixes, never HOW MUCH —"
  putStrLn "  beauty is its only degree of freedom."
  putStrLn "══════════════════════════════════════════════════════════"

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let mark = if and results then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
