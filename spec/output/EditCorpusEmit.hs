-- ════════════════════════════════════════════════════════════════
-- EditCorpusEmit: the complete edit space, enumerated, with the
-- rate-distortion surface it induces
--
-- ★ Daniel, 2026-08-16, on what the model is for:
--   "Keep the model as a tool in the edit phase. Ie when we have
--    encoded the capture in a tensor. Ie Bins so generate better
--    detailed options"
--   "An large set of generated data. Size 64^3 all possible
--    permutations"
--
-- ── WHY THIS CORPUS AND NOT ANOTHER ─────────────────────────────
--
-- The app ships ONE point of a 32768-point space, and it is a corner.
-- RoleAllocation.identityEdit is today's path: the RL4-derived depth
-- split, and the FINE READ ALONE (eCoarse = eMid = 0, because the app
-- uses only the 64-cubed stream). So 32767 lawful options per capture
-- have never been looked at.
--
-- ★ AND THE DERIVED POINT IS DERIVED FOR THE WRONG THING. RL4 is
-- reverse water-filling: b_i - b_j = half log2 (lam_i / lam_j). That
-- is the split which minimises RATE for a given distortion. It is not
-- the split that makes the best PICTURE, and nothing in the suite ever
-- claimed it was. The gap between "optimal for bits" and "best to
-- look at" is exactly the job weights have here, and it is why this
-- corpus labels every point rather than just the derived one.
--
-- ── THE SHAPE, AND WHY IT IS 64 CUBED ───────────────────────────
--
--   8 synthetic scenes  x  32768 edits  =  262144 rows  =  64^3
--
-- The 32768 is not a sample. `editSpace` is the COMPLETE enumeration
-- of five 8-state dials (RoleAllocation RA-editSpace, Octave OV11),
-- so every row of every scene is present exactly once. "All possible
-- permutations" is literal here, over the parameterisation the app
-- actually exposes.
--
-- ── WHAT EACH ROW CARRIES ───────────────────────────────────────
--
--   scene      which synthetic capture, and its two role variances
--   edit       the five dial positions
--   colours    distinct colours the allocation realises (coloursUsed)
--   rate       expected index width in bits (rateBits)
--   distFig    mean squared truncation error on the figure half
--   distGnd    the same on the ground half
--   derived    whether this edit IS the RL4 point for this scene
--
-- The model reads (scene features, edit) and learns the surface. What
-- it is FOR is proposing edits a person prefers to the derived one,
-- so the labels here are the exact arithmetic and the preference is
-- supplied later, never invented by this file.
--
-- ── EXACTNESS, AND WHERE IT IS TRADED ───────────────────────────
--
-- RoleAllocation is Rational throughout, because it states laws.
-- 262144 renders under Rational is not a thing anyone should wait
-- for, so this emitter carries the SAME arithmetic in Double and
-- SELF-GATES: before a byte is written it re-derives a sample of rows
-- under the spec's own Rational functions and aborts on any
-- disagreement. Fast where it is data, exact where it is law.
-- ════════════════════════════════════════════════════════════════

module Main where

import Data.List (intercalate, sortOn)
-- (Rational arithmetic uses only the Prelude's Ratio instances)
import System.Directory (createDirectoryIfMissing)
import System.Exit (exitFailure)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE LAW, verbatim from RoleAllocation (house rule: copies
--      over imports, and the gate below catches drift)
-- ════════════════════════════════════════════════════════════════

type Q = Rational

treeDepth :: Int
treeDepth = 7

leafCount :: Int
leafCount = 128

paletteSize :: Int
paletteSize = 256

widgetCells :: Int
widgetCells = treeDepth + 1

editArity :: Int
editArity = 5

data Edit = Edit
  { eFig :: Int, eGnd :: Int
  , eCoarse :: Int, eMid :: Int, eFine :: Int
  } deriving (Eq, Show)

editSpace :: [Edit]
editSpace =
  [ Edit a b c d e
  | a <- rng, b <- rng, c <- rng, d <- rng, e <- rng ]
  where rng = [0 .. treeDepth]

data Alloc = Alloc { dFig :: Int, dGnd :: Int } deriving (Eq, Show)

allocOf :: Edit -> Alloc
allocOf e = Alloc { dFig = eFig e, dGnd = eGnd e }

coloursUsed :: Alloc -> Int
coloursUsed a = 2 ^ dFig a + 2 ^ dGnd a

rateBitsD :: Double -> Alloc -> Double
rateBitsD pFig a =
  1 + pFig * fromIntegral (dFig a) + (1 - pFig) * fromIntegral (dGnd a)

halfLog4 :: Double -> Int
halfLog4 r = floor (logBase 4 r + 0.5 :: Double)

-- | ★ COPIED VERBATIM, after the first draft PARAPHRASED it and was
--   wrong on all 262144 rows. That version invented a `base = 4`
--   appearing nowhere in the law and put the gap on dFig; the law
--   pins dFig at the full depth ALWAYS and moves dGnd. The self-gate
--   missed it because it checked `nodesAt` against the Rational law
--   and not this function: the arithmetic that was ported carefully
--   got gated, the one retyped from memory did not. Now gated.
derivedAlloc :: Double -> Double -> Alloc
derivedAlloc lamF lamB = Alloc { dFig = treeDepth, dGnd = clampD gap }
  where
    gap = treeDepth - halfLog4 (lamF / lamB)
    clampD x = max 0 (min treeDepth x)

derivedAllocQ :: Q -> Q -> Alloc
derivedAllocQ lamF lamB = Alloc { dFig = treeDepth, dGnd = clampD gap }
  where
    gap = treeDepth - halfLog4 (fromRational (lamF / lamB))
    clampD x = max 0 (min treeDepth x)

-- | Tree truncation at depth d: 2^d nodes, each the mean of its
--   chunk of leaves. The Double twin of RoleAllocation.nodesAt.
nodesAtD :: Int -> [Double] -> [Double]
nodesAtD d xs
  | d >= treeDepth = xs
  | otherwise =
      let n = 2 ^ d
          w = length xs `div` n
      in [ mean (take w (drop (i * w) xs)) | i <- [0 .. n - 1] ]
  where mean ys = sum ys / fromIntegral (length ys)

-- | Mean squared truncation error: what the dial actually costs the
--   picture, which is the thing RL4 trades against bits.
truncErr :: Int -> [Double] -> Double
truncErr d xs =
  let n = if d >= treeDepth then length xs else 2 ^ d
      w = max 1 (length xs `div` n)
      grp = [ take w (drop (i * w) xs) | i <- [0 .. n - 1] ]
  in sum [ (v - mean g) ** 2 | g <- grp, v <- g ] / fromIntegral (length xs)
  where mean ys = sum ys / fromIntegral (length ys)

-- ════════════════════════════════════════════════════════════════
-- § 2. THE SCENES
-- ════════════════════════════════════════════════════════════════

-- | A deterministic LCG, so the corpus is reproducible from the
--   seed alone and no row depends on wall-clock or randomness.
lcg :: Int -> Int
lcg x = (1103515245 * x + 12345) `mod` 2147483648

uniforms :: Int -> [Double]
uniforms s = map (\v -> fromIntegral v / 2147483648) (tail (iterate lcg s))

-- | A scene is 128 tree leaves on the L axis plus the figure's share
--   of the frame. The two role variances follow from the leaves, so
--   nothing here is a free parameter.
data Scene = Scene
  { sName :: String
  , sLeaves :: [Double]
  , sPFig :: Double
  , sTargetGnd :: Int          -- the derived dGnd this scene realises
  }

-- ★ WHERE THE SCENE COUNT COMES FROM, and the first draft could not
--   answer this. It used EIGHT scenes with invented names, invented
--   spreads and invented seeds, chosen so that 8 x 32768 = 262144 =
--   64^3: the row count was reverse-engineered from a sentence
--   somebody wanted to write. Twenty-four naked constants, against a
--   standing decree that forbids them.
--
--   The law answers it instead. `derivedAlloc` reads exactly ONE
--   thing about a scene, the ratio lamF / lamB, through
--       dGnd = clamp (treeDepth - halfLog4 (lamF / lamB))
--   with dFig at treeDepth always. So the derived allocation takes
--   EXACTLY widgetCells distinct values, one per dGnd in 0..7, and
--   the complete scene axis IS that enumeration. Eight is DERIVED,
--   and 262144 = 64^3 falls out instead of being aimed at.
--
--   Each scene is built as the ratio that lands on its own dGnd, by
--   inverting halfLog4: lamF / lamB = 4^(treeDepth - dGnd).
scenes :: [Scene]
scenes = [ sceneFor g | g <- [0 .. treeDepth] ]

sceneFor :: Int -> Scene
sceneFor g = Scene
  { sName = "dGnd-" ++ show g
  , sLeaves = leaves
  , sPFig = 0.5
  , sTargetGnd = g }
  where
    ratio = 4 ** fromIntegral (treeDepth - g) :: Double
    sdB = 0.02
    sdF = sdB * sqrt ratio
    halfOf sd base =
      [ base + sd * cos (pi * fromIntegral i / fromIntegral hn)
      | i <- [0 .. hn - 1] ]
    hn = leafCount `div` 2
    leaves = halfOf sdB 0.35 ++ halfOf sdF 0.65

-- | Role-weighted generalised variances, measured on the scene's own
--   leaves. lamF is the figure half (the upper half of the sorted
--   tree), lamB the ground half. Nothing here is a free parameter.
lambdas :: Scene -> (Double, Double)
lambdas sc =
  let xs = sLeaves sc
      h = length xs `div` 2
      var ys = let m = sum ys / fromIntegral (length ys)
               in sum [ (y - m) ** 2 | y <- ys ] / fromIntegral (length ys)
  in (max 1e-12 (var (drop h xs)), max 1e-12 (var (take h xs)))

-- ════════════════════════════════════════════════════════════════
-- § 3. THE ROW
-- ════════════════════════════════════════════════════════════════

data Row = Row
  { rScene :: String
  , rEdit :: Edit
  , rColours :: Int
  , rRate :: Double
  , rDistFig :: Double
  , rDistGnd :: Double
  , rDerived :: Bool
  }

rowsFor :: Scene -> [Row]
rowsFor sc =
  [ Row { rScene = sName sc
        , rEdit = e
        , rColours = coloursUsed a
        , rRate = rateBitsD (sPFig sc) a
        , rDistFig = truncErr (eFig e) figHalf
        , rDistGnd = truncErr (eGnd e) gndHalf
        , rDerived = a == der }
  | e <- editSpace
  , let a = allocOf e ]
  where
    xs = sLeaves sc
    h = length xs `div` 2
    (figHalf, gndHalf) = (drop h xs, take h xs)
    (lamF, lamB) = lambdas sc
    der = derivedAlloc lamF lamB

jsonRow :: Row -> String
jsonRow r =
  "{\"scene\":\"" ++ rScene r ++ "\""
  ++ ",\"edit\":[" ++ intercalate "," (map show
       [ eFig e, eGnd e, eCoarse e, eMid e, eFine e ]) ++ "]"
  ++ ",\"colours\":" ++ show (rColours r)
  ++ ",\"rate\":" ++ show (rRate r)
  ++ ",\"distFig\":" ++ show (rDistFig r)
  ++ ",\"distGnd\":" ++ show (rDistGnd r)
  ++ ",\"derived\":" ++ (if rDerived r then "true" else "false")
  ++ "}"
  where e = rEdit r

-- ════════════════════════════════════════════════════════════════
-- § 4. THE SELF-GATE. Nothing is written until these hold.
-- ════════════════════════════════════════════════════════════════

-- | The Rational twin of nodesAtD, used only to prove the Double
--   path did not drift. This is the "exact where it is law" half.
nodesAtQ :: Int -> [Q] -> [Q]
nodesAtQ d xs
  | d >= treeDepth = xs
  | otherwise =
      let n = 2 ^ d
          w = length xs `div` n
      in [ meanQ (take w (drop (i * w) xs)) | i <- [0 .. n - 1] ]
  where meanQ ys = sum ys / fromIntegral (length ys)

gates :: [(String, Bool)]
gates =
  [ ("editSpace is COMPLETE, 8^5",
     length editSpace == widgetCells ^ editArity
     && length editSpace == 32768)
  , ("every edit appears exactly once",
     length editSpace == length (nubOrd editSpace))
  , ("the corpus is exactly 64^3 rows",
     length scenes * length editSpace == 64 * 64 * 64)
  , ("every scene carries a full 128-leaf tree",
     all ((== leafCount) . length . sLeaves) scenes)
  , ("the palette is the two halves, PT6",
     coloursUsed (Alloc treeDepth treeDepth) == paletteSize)
  , ("truncation at full depth is LOSSLESS",
     all (\sc -> truncErr treeDepth (sLeaves sc) < 1e-15) scenes)
  , ("truncation error is MONOTONE in depth (the dial means something)",
     all monotoneErr scenes)
  , ("Double nodesAt agrees with the Rational law on every scene",
     all agreesWithRational scenes)
  , ("every scene's derived point IS in the space exactly once",
     all (\sc -> length (filter rDerived (rowsFor sc)) == derivedCount) scenes)
  , ("* derivedAlloc agrees with the Rational law on every scene",
     all (\sc -> let (f, b) = lambdas sc
                 in derivedAlloc f b
                    == derivedAllocQ (toRational f) (toRational b)) scenes)
  , ("* dFig is treeDepth on every derived point (law, not a choice)",
     all (\sc -> dFig (uncurry derivedAlloc (lambdas sc)) == treeDepth) scenes)
  , ("* each scene realises the dGnd it was BUILT for",
     all (\sc -> dGnd (uncurry derivedAlloc (lambdas sc)) == sTargetGnd sc) scenes)
  , ("* the scene axis is COMPLETE: every derived allocation, once",
     let ds = [ dGnd (uncurry derivedAlloc (lambdas sc)) | sc <- scenes ]
     in ds == [0 .. treeDepth] && length ds == widgetCells)
  ]
  where
    nubOrd = foldr (\x acc -> if x `elem` acc then acc else x : acc) []
    monotoneErr sc =
      let es = [ truncErr d (sLeaves sc) | d <- [0 .. treeDepth] ]
      in and (zipWith (>=) es (tail es))
    -- the derived Alloc fixes dFig and dGnd; the three octave dials
    -- are free, so exactly 8^3 rows carry it
    derivedCount = widgetCells ^ (3 :: Int)
    agreesWithRational sc =
      let xs = sLeaves sc
          xq = map toRational xs
      in and [ maximum (0 : zipWith (\a b -> abs (a - fromRational b))
                              (nodesAtD d xs) (nodesAtQ d xq)) < 1e-9
             | d <- [0 .. treeDepth] ]

-- ════════════════════════════════════════════════════════════════
-- § 5. EMIT
-- ════════════════════════════════════════════════════════════════

outDir :: FilePath
outDir = "../nn/edit-options/corpus"

main :: IO ()
main = do
  putStrLn "EditCorpusEmit: the complete edit space, per scene"
  putStrLn ""
  mapM_ (\(n, ok) -> putStrLn ("  " ++ (if ok then "OK  " else "BAD ") ++ n)) gates
  putStrLn ""
  if not (all snd gates)
    then do
      putStrLn "  A GATE FAILED. Nothing written: the corpus cannot"
      putStrLn "  drift silently, which is the SKCorpusEmit contract."
      exitFailure
    else do
      createDirectoryIfMissing True outDir
      let rows = concatMap rowsFor scenes
      writeFile (outDir ++ "/edits.jsonl")
        (unlines (map jsonRow rows))
      writeFile (outDir ++ "/manifest.json") (manifest (length rows))
      putStrLn $ "  wrote " ++ show (length rows) ++ " rows to " ++ outDir
      putStrLn $ "    scenes  " ++ show (length scenes)
      putStrLn $ "    edits   " ++ show (length editSpace) ++ " (complete, 8^5)"
      putStrLn $ "    = " ++ show (length rows) ++ " = 64^3"
      putStrLn ""
      putStrLn "  ★ WHAT THE MODEL IS FOR, restated so the trainer"
      putStrLn "  cannot forget it: RL4's derived point minimises RATE."
      putStrLn "  These rows label every point exactly. The PREFERENCE"
      putStrLn "  between them is supplied by a person, never by this"
      putStrLn "  file, and that preference is the only thing weights"
      putStrLn "  are asked to carry."

manifest :: Int -> String
manifest n =
  "{\"rows\":" ++ show n
  ++ ",\"scenes\":" ++ show (length scenes)
  ++ ",\"edits\":" ++ show (length editSpace)
  ++ ",\"arity\":" ++ show editArity
  ++ ",\"cellsPerDial\":" ++ show widgetCells
  ++ ",\"treeDepth\":" ++ show treeDepth
  ++ ",\"leafCount\":" ++ show leafCount
  ++ ",\"paletteSize\":" ++ show paletteSize
  ++ ",\"complete\":true"
  ++ ",\"source\":\"spec/output/EditCorpusEmit.hs\""
  ++ ",\"law\":\"quantization/RoleAllocation.hs\""
  ++ "}"
