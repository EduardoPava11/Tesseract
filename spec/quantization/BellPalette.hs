{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- BellPalette: The Bell-Allocated 256-Color Palette
--
-- 256 colors are not spread evenly over luminance. They are
-- allocated by a bell over 16 luminance strata:
--
--   bell = [1,1,2,4,8,16,32,64,64,32,16,8,4,2,1,1]   Σ = 256
--
-- Stratum k owns the luminance band [k/16, (k+1)/16) — the top
-- band is closed at 1 so pure white has a home. The two outermost
-- strata hold exactly ONE centroid each, and those centroids are
-- pinned: index 0 = pure black, index 255 = pure white, EXACT.
-- The mid-tones, where the eye lives, get 64 centroids apiece.
--
-- The reference constructor takes (color, luminance) samples and
-- fills each stratum by deterministic Lloyd iteration (stride-
-- seeded k-means); starved strata are padded with in-band grays.
-- It is TOTAL: any sample set (including none) yields a lawful
-- palette.
--
-- The bijection rung: a 16×16 image has 256 pixels — exactly one
-- per palette entry. At that rung the palette IS the image.
-- ════════════════════════════════════════════════════════════════

module BellPalette where

import Data.List (sort, sortOn, foldl')

-- ════════════════════════════════════════════════════════════════
-- § 1. THE BELL
-- ════════════════════════════════════════════════════════════════

bell :: [Int]
bell = [1,1,2,4,8,16,32,64,64,32,16,8,4,2,1,1]

nStrata :: Int
nStrata = 16

-- | offsets !! k = first palette index of stratum k (17 entries,
--   last = 256). The bell layout partitions [0..255].
offsets :: [Int]
offsets = scanl (+) 0 bell

-- | Stratum that owns palette index i (from the bell layout).
indexStratum :: Int -> Int
indexStratum i = length (takeWhile (<= i) (tail offsets))

-- ════════════════════════════════════════════════════════════════
-- § 2. COLORS, LUMINANCE, STRATA
-- ════════════════════════════════════════════════════════════════

type RGB     = (Double, Double, Double)   -- each channel ∈ [0,1]
type Palette = [RGB]                      -- exactly 256, stratum-ordered

-- | Rec.709 luma. Coefficients sum to 1, so a gray (g,g,g) has
--   luminance exactly g — the synthetic-fill invariant below.
lumaOf :: RGB -> Double
lumaOf (r,g,b) = 0.2126*r + 0.7152*g + 0.0722*b

-- | Band classifier: stratum k owns [k/16, (k+1)/16); the top
--   band is closed at 1 (min 15 catches luminance = 1 exactly).
stratumOf :: Double -> Int
stratumOf l = min (nStrata - 1) (max 0 (floor (l * fromIntegral nStrata)))

black, white :: RGB
black = (0, 0, 0)
white = (1, 1, 1)

-- ════════════════════════════════════════════════════════════════
-- § 3. THE REFERENCE CONSTRUCTOR
--
-- Per stratum k with target n = bell !! k and in-band samples S:
--   · k = 0        → [black]   (the anchor IS the stratum)
--   · k = 15       → [white]   (the anchor IS the stratum)
--   · |S| ≥ n      → Lloyd iteration: seed by stride through the
--                    luma-sorted samples, 8 assign/mean rounds,
--                    empty clusters keep their old centroid.
--   · |S| < n      → samples + in-band synthetic grays as padding.
--
-- BP3 holds by CONVEXITY: a cluster mean of in-band samples has
-- in-band luminance (luma is linear); synthetic grays are placed
-- strictly inside the band. Within each stratum the centroids are
-- canonically ordered by (luma, r, g, b) — fully deterministic.
-- ════════════════════════════════════════════════════════════════

lloydIters :: Int
lloydIters = 8

buildPalette :: [RGB] -> Palette
buildPalette samples = concat [centroidsFor k | k <- [0 .. nStrata - 1]]
  where
    inStratum k = [c | c <- samples, stratumOf (lumaOf c) == k]
    centroidsFor k
      | k == 0           = [black]
      | k == nStrata - 1 = [white]
      | otherwise        = canonical (allocate k (bell !! k) (inStratum k))
    canonical = sortOn (\c@(r,g,b) -> (lumaOf c, r, g, b))

-- | n grays strictly inside stratum k's band, evenly spaced.
synthetic :: Int -> Int -> [RGB]
synthetic k n =
  [ gray ((fromIntegral k + (fromIntegral i + 0.5) / fromIntegral n) / 16)
  | i <- [0 .. n - 1] ]
  where gray l = (l, l, l)

allocate :: Int -> Int -> [RGB] -> [RGB]
allocate k n ss
  | length ss >= n = lloyd n ss
  | otherwise      = ss ++ synthetic k (n - length ss)

dist2 :: RGB -> RGB -> Double
dist2 (a,b,c) (d,e,f) = (a-d)^(2::Int) + (b-e)^(2::Int) + (c-f)^(2::Int)

meanRGB :: [RGB] -> RGB
meanRGB cs =
  let n = fromIntegral (length cs)
      (sr, sg, sb) = foldl' (\(x,y,z) (r,g,b) -> (x+r, y+g, z+b)) (0,0,0) cs
  in (sr / n, sg / n, sb / n)

-- | Deterministic Lloyd: seed = every (|S|/n)-th luma-sorted sample.
--   Assignment tie rule: LOWEST centroid index wins.
lloyd :: Int -> [RGB] -> [RGB]
lloyd n ss = iterate step seed0 !! lloydIters
  where
    sorted = sortOn lumaOf ss
    len    = length sorted
    seed0  = [sorted !! ((i * len) `div` n) | i <- [0 .. n - 1]]
    step cs =
      let assign s   = snd (minimum [(dist2 s ctr, j) | (j, ctr) <- zip [0 :: Int ..] cs])
          clusters   = [[s | s <- ss, assign s == j] | j <- [0 .. n - 1]]
      in zipWith (\old cl -> if null cl then old else meanRGB cl) cs clusters

-- ════════════════════════════════════════════════════════════════
-- § 4. THE BIJECTION RUNG (16×16 = 256: palette IS image)
-- ════════════════════════════════════════════════════════════════

-- | Deterministic Fisher–Yates over the palette indices.
shuffle :: Int -> [Int] -> [Int]
shuffle seed xs0 = go (uniforms seed) xs0
  where
    go _ []       = []
    go (u:us) ys  = let i        = floor (u * fromIntegral (length ys))
                        (a, y:b) = splitAt i ys
                    in y : go us (a ++ b)
    go [] _       = error "uniforms is infinite"

-- | A 16×16 image whose pixels are a permutation of [0..255]:
--   every palette entry used exactly once.
bijectionImage :: Int -> [[Int]]
bijectionImage seed = chunk 16 (shuffle seed [0 .. 255])

chunk :: Int -> [a] -> [[a]]
chunk _ [] = []
chunk n xs = take n xs : chunk n (drop n xs)

-- ════════════════════════════════════════════════════════════════
-- § 5. DETERMINISTIC PSEUDO-RANDOM SAMPLES (no System.Random)
-- ════════════════════════════════════════════════════════════════

lcg :: Int -> Int
lcg s = (1103515245 * s + 12345) `mod` 2147483648

-- | Infinite uniform [0,1) stream from a seed.
uniforms :: Int -> [Double]
uniforms seed = map ((/ 2147483648.0) . fromIntegral) (tail (iterate lcg seed))

randColors :: Int -> Int -> [RGB]
randColors seed n = take n (go (uniforms seed))
  where
    go (a:b:c:us) = (a, b, c) : go us
    go _          = []

-- | Constructor test inputs: empty, starved, collapsed, anchor-heavy,
--   and 12 random sets. The constructor must be lawful on ALL of them.
sampleSets :: [[RGB]]
sampleSets =
  [ []                                -- no data at all: fully synthetic
  , randColors 77 5                   -- starved: 5 samples for 254 slots
  , replicate 40 (0.5, 0.5, 0.5)      -- collapsed: one mid gray, 40 times
  , replicate 40 black                -- everything in the anchor stratum
  ] ++ [randColors s 512 | s <- [1 .. 12]]

allPalettes :: [Palette]
allPalettes = map buildPalette sampleSets

bijectionSeeds :: [Int]
bijectionSeeds = [1 .. 10]

-- ════════════════════════════════════════════════════════════════
-- § 6. AXIOMS
-- ════════════════════════════════════════════════════════════════

-- (BP1) Anchors: index 0 = pure black, index 255 = pure white, EXACT
--       (structural equality, no epsilon).
axiom_BP1 :: Bool
axiom_BP1 = all (\p -> head p == black && last p == white) allPalettes

-- (BP2) Conservation: per-stratum counts equal the bell; total = 256.
axiom_BP2 :: Bool
axiom_BP2 = sum bell == 256 && all lawful allPalettes
  where
    lawful p = length p == 256 && counts p == bell
    counts p = [length [() | c <- p, stratumOf (lumaOf c) == k] | k <- [0 .. 15]]

-- (BP3) Stratum residency: the centroid AT index i has luminance in
--       the band of the stratum that OWNS index i (positional law).
axiom_BP3 :: Bool
axiom_BP3 = all residency allPalettes
  where
    residency p = and [stratumOf (lumaOf c) == indexStratum i
                      | (i, c) <- zip [0 ..] p]

-- (BP4) Bijection rung: the 16×16 image is 256 pixels forming a
--       permutation of [0..255] — each palette entry exactly once.
axiom_BP4 :: Bool
axiom_BP4 = all ok bijectionSeeds
  where
    ok seed =
      let img = bijectionImage seed
      in length img == 16
      && all ((== 16) . length) img
      && sort (concat img) == [0 .. 255]

-- (BP5) Interior sum: strata 1..14 hold exactly 254 centroids
--       (256 minus the two anchors) — in the bell and in every palette.
axiom_BP5 :: Bool
axiom_BP5 = sum (take 14 (drop 1 bell)) == 254 && all interior allPalettes
  where
    interior p =
      length [c | c <- p, let k = stratumOf (lumaOf c), k >= 1 && k <= 14] == 254

-- ════════════════════════════════════════════════════════════════
-- § 7. VISUALIZATION
-- ════════════════════════════════════════════════════════════════

showBell :: IO ()
showBell = mapM_ row [0 .. 15]
  where
    row k =
      let n  = bell !! k
          lo = offsets !! k
      in putStrLn $ "  " ++ padL 2 (show k)
                 ++ " │" ++ replicate (max 1 (n `div` 2)) '█'
                 ++ " " ++ show n
                 ++ "   [" ++ show lo ++ ".." ++ show (lo + n - 1) ++ "]"

hexDigit :: Int -> Char
hexDigit k = "0123456789ABCDEF" !! k

-- | The bijection image, each pixel shown as its OWNER stratum.
showImage :: [[Int]] -> IO ()
showImage = mapM_ (putStrLn . ("  " ++) . map (hexDigit . indexStratum))

-- ════════════════════════════════════════════════════════════════
-- § 8. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " BellPalette: The Bell-Allocated 256-Color Palette"
  putStrLn " 16 luminance strata × bell counts = 256. Anchors pinned."
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "── The Bell (stratum │ centroids │ palette index range) ──"
  putStrLn ""
  showBell
  putStrLn ""
  putStrLn $ "  Σ bell = " ++ show (sum bell)
  putStrLn ""

  putStrLn "── Reference Construction (512 random samples, seed 1) ──"
  putStrLn ""
  let pal = buildPalette (randColors 1 512)
      slice k = take (bell !! k) (drop (offsets !! k) pal)
      lumas k = map lumaOf (slice k)
  putStrLn "  stratum │ band            │ n  │ centroid luma range"
  putStrLn "  ────────┼─────────────────┼────┼────────────────────"
  mapM_ (\k -> putStrLn $
          "  " ++ padL 7 (show k)
       ++ " │ [" ++ showF (fromIntegral k / 16) ++ ", "
       ++ showF (fromIntegral (k + 1) / 16) ++ ") │ "
       ++ padL 2 (show (bell !! k))
       ++ " │ " ++ showF (minimum (lumas k)) ++ " .. " ++ showF (maximum (lumas k)))
        [0, 1, 7, 8, 14, 15]
  putStrLn ""
  putStrLn $ "  index   0 = " ++ showRGB (head pal) ++ "  (pure black, exact)"
  putStrLn $ "  index 255 = " ++ showRGB (last pal) ++ "  (pure white, exact)"
  putStrLn ""

  putStrLn "── The Bijection Rung: 16×16 = 256, palette IS image ──"
  putStrLn "   (each pixel printed as its stratum, 0..F)"
  putStrLn ""
  showImage (bijectionImage 1)
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  check "BP1 anchors: index 0 = black, index 255 = white, EXACT" [axiom_BP1]
  check "BP2 conservation: stratum counts = bell, total = 256"   [axiom_BP2]
  check "BP3 residency: centroid luma inside its index's band"   [axiom_BP3]
  check "BP4 bijection rung: 16×16 permutation of [0..255]"      [axiom_BP4]
  check "BP5 interior: strata 1..14 hold exactly 254 centroids"  [axiom_BP5]
  putStrLn ""

  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " THE PRINCIPLE"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  bell = [1,1,2,4,8,16,32,64,64,32,16,8,4,2,1,1]  Σ = 256"
  putStrLn ""
  putStrLn "  Black and white are ANCHORS, not centroids to be learned:"
  putStrLn "  the outermost strata hold exactly one color each, pinned."
  putStrLn "  The 254 interior centroids live where the samples live,"
  putStrLn "  bell-many per band, never leaving their stratum."
  putStrLn ""
  putStrLn "  16×16 = 256: at the base rung every palette entry paints"
  putStrLn "  exactly one pixel. The palette IS the image."
  putStrLn ""
  putStrLn "  The constructor is TOTAL: no samples, starved strata,"
  putStrLn "  collapsed strata — all yield a lawful 256-color palette."
  putStrLn "══════════════════════════════════════════════════════════"

-- Helpers (no-scientific-notation formatter: integer math, 3 dp)
showF :: Double -> String
showF x =
  let n    = round (abs x * 1000) :: Int
      sign = if x < 0 then "-" else ""
      frac = show (n `mod` 1000)
      pad3 = replicate (3 - length frac) '0' ++ frac
  in sign ++ show (n `div` 1000) ++ "." ++ pad3

showRGB :: RGB -> String
showRGB (r,g,b) = "(" ++ showF r ++ ", " ++ showF g ++ ", " ++ showF b ++ ")"

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name
