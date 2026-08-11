{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- SKCorpusEmit: emit the gene-JEPA training corpus
--
-- Wired 2026-08-11 after ANE recon (commit 6bb7962): the gene
-- machinery arrives as the LEARNED PASSER of the ANE loop's latent
-- slot — small weights folded into the fused graph as constants
-- (the ONES_ROW/ONEHOT/CELL2 pattern in nn/ane-loop/build_model.py),
-- trained Mac-side on SYNTHETIC corpora only (no-capture decree).
-- This emitter produces that corpus, following the nn/<model>/
-- layout: output lands in nn/sk-gene/corpus/.
--
-- Files:
--   pairs.jsonl      27,419 typed reduction pairs, one per line:
--                    {geneId, gene, step, sym, axis, depth,
--                     opSizes, pre, post, preSize, postSize,
--                     fate, haltTime?, nfId?}
--   nf-classes.tsv   nfId ↦ normal form + class size (2,692 rows;
--                    ids by first appearance in enumeration order)
--   manifest.json    pinned stats + conventions + provenance
--
-- Terms are emitted as strings over {s, k, [, ]} — the trainer
-- embeds them; NO palette indices anywhere (the ANE path returns
-- colors, the SIMT path carries indices — recon caveat 4 — so the
-- corpus stays index-free and both ports key on it identically).
--
-- Self-gating: every pinned statistic from SKGeneSemantics.hs
-- (AX2–AX5) is re-verified before a single byte is written; any
-- mismatch aborts the emit. The corpus can never drift silently.
-- ════════════════════════════════════════════════════════════════

module Main where

import qualified Data.Map.Strict as M
import System.Directory (createDirectoryIfMissing)
import Control.Monad (unless)

-- ── Calculus core (mirrors spec/neural/SKGeneSemantics.hs) ──────

data C = S | K | App C C deriving (Eq, Ord)

instance Show C where
  show S = "s"
  show K = "k"
  show (App f x) = show f ++ "[" ++ show x ++ "]"

size :: C -> Int
size S = 1
size K = 1
size (App f x) = size f + size x

trees :: Int -> [C]
trees 1 = [S, K]
trees n = [ App f x | i <- [1 .. n - 1], f <- trees i, x <- trees (n - i) ]

data Redex = RK Int C C | RS Int C C C deriving (Eq, Show)

stepR :: C -> Maybe (Redex, C)
stepR = go 0
  where
    go d (App (App K x) y)         = Just (RK d x y, x)
    go d (App (App (App S x) y) z) = Just (RS d x y z, App (App x z) (App y z))
    go d (App f a) = case go (d + 1) f of
      Just (r, f') -> Just (r, App f' a)
      Nothing      -> fmap (App f) <$> go (d + 1) a
    go _ _ = Nothing

unroll, sizeCap :: Int
unroll  = 16
sizeCap = 50000

traj :: C -> ([(Redex, C, C)], C, Bool)
traj = go 0 []
  where
    go n acc t
      | n >= unroll || size t > sizeCap = (reverse acc, t, False)
      | otherwise = case stepR t of
          Nothing      -> (reverse acc, t, True)
          Just (r, t') -> go (n + 1) ((r, t, t') : acc) t'

-- ── Corpus assembly ─────────────────────────────────────────────

pool :: [C]
pool = trees 7

corpus :: [(Int, C, [(Redex, C, C)], C, Bool)]
corpus = [ (i, g, es, nf, h)
         | (i, g) <- zip [0..] pool
         , let (es, nf, h) = traj g ]

-- nfId by first appearance in canonical enumeration order
nfIds :: M.Map String Int
nfIds = fst $ foldl step0 (M.empty, 0)
              [ show nf | (_, _, _, nf, True) <- corpus ]
  where
    step0 (m, next) k
      | k `M.member` m = (m, next)
      | otherwise      = (M.insert k next m, next + 1)

nfSizes :: M.Map String Int
nfSizes = M.fromListWith (+) [ (show nf, 1) | (_, _, _, nf, True) <- corpus ]

-- ── JSON (by hand; terms only contain s k [ ], always safe) ─────

jStr :: String -> String
jStr s = "\"" ++ s ++ "\""

jField :: String -> String -> String
jField k v = jStr k ++ ":" ++ v

jObj :: [String] -> String
jObj fs = "{" ++ intercalate "," fs ++ "}"

jArr :: [String] -> String
jArr xs = "[" ++ intercalate "," xs ++ "]"

intercalate :: String -> [String] -> String
intercalate _ []     = ""
intercalate _ [x]    = x
intercalate sep (x:xs) = x ++ sep ++ intercalate sep xs

axisName :: Int -> String
axisName d = ["x", "y", "t"] !! (d `mod` 3)

pairLine :: Int -> C -> Bool -> Int -> Int -> (Int, (Redex, C, C)) -> String
pairLine gid g halted haltT nfId (i, (r, pre, post)) = jObj $
  [ jField "geneId"   (show gid)
  , jField "gene"     (jStr (show g))
  , jField "step"     (show i)
  , jField "sym"      (jStr sym)
  , jField "axis"     (jStr (axisName d))
  , jField "depth"    (show d)
  , jField "opSizes"  (jArr (map show ops))
  , jField "pre"      (jStr (show pre))
  , jField "post"     (jStr (show post))
  , jField "preSize"  (show (size pre))
  , jField "postSize" (show (size post))
  , jField "fate"     (jStr (if halted then "halt" else "diverge"))
  ] ++ (if halted
          then [ jField "haltTime" (show haltT)
               , jField "nfId"     (show nfId) ]
          else [])
  where
    (sym, d, ops) = case r of
      RK dd x y   -> ("K", dd, [size x, size y])
      RS dd x y z -> ("S", dd, [size x, size y, size z])

-- ── Pinned expectations (must match SKGeneSemantics AX2–AX5) ────

expectedHist :: [((String, String), Int)]
expectedHist =
  [ (("K","x"), 7441), (("K","y"), 6892), (("K","t"), 4649)
  , (("S","x"), 3988), (("S","y"), 2995), (("S","t"), 1454) ]

main :: IO ()
main = do
  let events  = [ (gid, g, es, nf, h) | (gid, g, es, nf, h) <- corpus ]
      allEvs  = [ (sym, axisName d)
                | (_, _, es, _, _) <- events
                , (r, _, _) <- es
                , let (sym, d) = case r of RK dd _ _   -> ("K", dd)
                                           RS dd _ _ _ -> ("S", dd) ]
      hist    = M.fromListWith (+) [ (e, 1::Int) | e <- allEvs ]
      halters = length [ () | (_, _, _, _, True) <- events ]
      pairsN  = length allEvs
      nfN     = M.size nfIds
      largest = maximum (M.elems nfSizes)
      haltMax = maximum [ size t | (_, _, es, _, True) <- events
                        , (_, _, t) <- es ]
      divMax  = maximum [ size t | (_, _, es, _, False) <- events
                        , (_, _, t) <- es ]

  -- self-gate before writing anything
  unless (length pool == 16896)             $ err "pool ≠ 16,896"
  unless (pairsN == 27419)                  $ err "pairs ≠ 27,419"
  unless (hist == M.fromList expectedHist)  $ err "action histogram drift"
  unless (halters == 16894)                 $ err "halters ≠ 16,894"
  unless (nfN == 2692)                      $ err "NF classes ≠ 2,692"
  unless (largest == 1148)                  $ err "largest NF class ≠ 1,148"
  unless (haltMax == 41 && divMax == 187)   $ err "capacity drift"

  let outDir = "../nn/sk-gene/corpus"
  createDirectoryIfMissing True outDir

  -- pairs.jsonl
  let lns = [ pairLine gid g h haltT nfId (i, ev)
            | (gid, g, es, nf, h) <- events
            , let haltT = length es
                  nfId  = M.findWithDefault (-1) (show nf) nfIds
            , (i, ev) <- zip [0..] es ]
  writeFile (outDir ++ "/pairs.jsonl") (unlines lns)

  -- nf-classes.tsv
  let nfRows = [ show nid ++ "\t" ++ nf ++ "\t" ++ show (nfSizes M.! nf)
               | (nf, nid) <- M.toList nfIds ]
      sorted = map snd $ M.toAscList $
                 M.fromList [ (read (takeWhile (/= '\t') r) :: Int, r)
                            | r <- nfRows ]
  writeFile (outDir ++ "/nf-classes.tsv") (unlines sorted)

  -- manifest.json
  let manifest = jObj
        [ jField "provenance" (jObj
            [ jField "spec"    (jStr "spec/neural/SKGeneSemantics.hs")
            , jField "gates"   (jStr "AX1-AX8 green")
            , jField "design"  (jStr "docs/sk-gene-calculus-2026-08-11.md")
            , jField "date"    (jStr "2026-08-11")
            , jField "aneRecon" (jStr "commit 6bb7962: latent-slot passer, weights folded as graph constants")
            ])
        , jField "conventions" (jObj
            [ jField "axisClock" (jStr "axis = redex App-depth mod 3; 0=x 1=y 2=t (third axis is time)")
            , jField "reduction" (jStr "leftmost-outermost; S f g u -> (f u)(g u); K f g -> f")
            , jField "terms"     (jStr "strings over s k [ ]; no palette indices (ANE colors / SIMT indices port split)")
            ])
        , jField "unroll"   (show unroll)
        , jField "sizeCap"  (show sizeCap)
        , jField "poolSize" (show (length pool))
        , jField "pairs"    (show pairsN)
        , jField "halters"  (show halters)
        , jField "divergers" (jArr
            [ jStr (show g) | (_, g, _, _, False) <- events ])
        , jField "nfClasses" (show nfN)
        , jField "largestNfClass" (show largest)
        , jField "capacity" (jObj
            [ jField "haltMax" (show haltMax)
            , jField "divergerAtUnroll" (show divMax) ])
        , jField "actionHistogram" (jObj
            [ jField (s ++ "_" ++ a) (show n)
            | ((s, a), n) <- expectedHist ])
        ]
  writeFile (outDir ++ "/manifest.json") (manifest ++ "\n")

  putStrLn "════ SKCorpusEmit ════"
  putStrLn $ "  pairs.jsonl      " ++ show pairsN ++ " pairs"
  putStrLn $ "  nf-classes.tsv   " ++ show nfN ++ " classes (largest "
           ++ show largest ++ ")"
  putStrLn $ "  manifest.json    pinned stats + conventions"
  putStrLn $ "  → " ++ outDir
  putStrLn "  ✓ all pinned statistics re-verified before emit"
  where
    err m = error ("SKCorpusEmit: " ++ m ++ " — corpus NOT written")
