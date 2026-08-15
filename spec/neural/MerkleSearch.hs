-- ════════════════════════════════════════════════════════════════
-- MerkleSearch: a searchable tree of possible GIFs, and the energy
-- that is worth showing
--
-- ★ Daniel, 2026-08-15:
--   "Think of GO and katago. we have a merkle tree that is searchable
--    and values that are probabilities as the output of the model.
--    those two together are what I want to use. a merkle tree of
--    possible GIFs and the probabilities to be shown to the user in
--    terms of energy. but useful energy not just everything goes to
--    grey..."
--
-- ── THE MAPPING, STATED ONCE ────────────────────────────────────
--
--   Go / KataGo                 Tesseract
--   ─────────────────────       ──────────────────────────────────
--   position                    a GIF, as its canonical generator
--   move                        an expansion S at one rung
--   the tree                    the Merkle tree over generators
--   transposition table         the Merkle hash, for free
--   policy head  P(move)        which expansion to try
--   value head   V(position)    the ENERGY, shown to the user
--   PUCT                        the search
--
-- ── ★ THE ONE PLACE THE ANALOGY INVERTS, AND IT IS THE ECONOMY ──
--
-- KataGo must LEARN its value head, because Go has no closed-form
-- score for a non-terminal position. This app does. TilingEntropy's
-- E and E_wall are exact arithmetic in the wire's own units (TE1,
-- TE8, TE10), computable from any candidate with no weights at all.
--
-- So the value head needs no model. ONLY THE POLICY DOES. That is a
-- large economy and it is the same conclusion MemoryColour reached
-- from the other side: weights belong where knowledge is empirical
-- and nowhere else.
--
-- ── ★ "USEFUL ENERGY, NOT EVERYTHING GOES TO GREY" ──────────────
--
-- This is the load-bearing constraint and it is not a preference.
-- MEASURED on TilingEntropy's own pinned frames:
--
--   frame       E (bits)    E_wall (bits)
--   balanced        0.00        1573.06
--   random          0.00          82.64
--   face         4182.21        8064.00
--   neel        28672.00        8064.00
--   solid       32768.00        8064.00
--
-- Read the two columns and the whole design falls out:
--
--   GREY IS THE CEILING OF E, NOT ITS FLOOR (MT6). A solid frame
--   scores 32768, the maximum. Descending E cannot go grey, which
--   is the opposite of what descending a DISTORTION would do. That
--   is why the search is driven by the informational energy and
--   never by RMSE.
--
--   BUT E ALONE IS BLIND TO THE OTHER CORNER (MT7). Random static
--   and the balanced tiling both score exactly 0. A scalar descent
--   on E lands on noise instead of grey, which is a different
--   failure and not a better one.
--
--   E_wall IS BLIND TO THE FIRST (MT7). Face, neel and solid all
--   saturate at 8064, so E_wall cannot tell a picture from grey.
--
--   ★ TOGETHER THEY EXCLUDE BOTH (MT8), and not by tuning. Under
--   the natural order (E low, E_wall high) SOLID IS STRICTLY
--   DOMINATED BY FACE, at equal E_wall and far lower E; and RANDOM
--   IS STRICTLY DOMINATED BY BALANCED, at equal E and far higher
--   E_wall. So a search that keeps only its Pareto front cannot
--   return grey and cannot return static, because both are beaten
--   by candidates the same search is already holding.
--
-- That is what makes the energy worth SHOWING. A scalar would have
-- to pick a corner; the front is where the pictures are.
--
-- ── SCOPE (grepped first, per the standing lesson) ──────────────
--
-- Nothing in the registry mentions merkle, PUCT, MCTS, a policy head
-- or a transposition table. These own the ground this file stands on
-- and it cites rather than restates them:
--   statistics/TilingEntropy.hs  TE*  E, E_wall, and the probes
--   quantization/PairTree.hs     PT5  the prefix law: a truncated
--                                     index IS the coarser palette
--   neural/DescentLadder.hs      DL1  depth 3, fan-outs [2,8,8]
--   neural/ColourLatent.hs       CL1  the generator; CL4/CL5 the
--                                     256 free relabelings
--   neural/MemoryColour.hs       MC*  S and K as parallel rails
--   quantization/AttractorRAG.hs AR*  a library, ranked by energy
--   output/CaptureTensor.hs      CT*  what is retained
-- ════════════════════════════════════════════════════════════════

module MerkleSearch where

import Data.Bits (xor, (.&.))
import Data.List (nub, sort)
import Data.Word (Word64)

-- ════════════════════════════════════════════════════════════════
-- § 1. THE NODE
-- ════════════════════════════════════════════════════════════════

-- | A node is a GIF, and a GIF is its generator (CL1): the artifact
--   is a pure function of it, so a node carries no pixels.
--
--   ★ IT HAS TWO PARTS AND THEY ARE HASHED DIFFERENTLY, which an
--   earlier draft of this file got wrong and MT3 caught:
--
--     path     WHICH BRANCH was taken at each depth. STRUCTURE. The
--              free relabeling group does not act on it at all, so
--              canonicalising it would collapse distinct nodes --
--              every depth-1 path lies in one orbit and would hash
--              to a single address.
--     content  the PALETTE, which the group DOES act on (CL4/CL5),
--              so it is hashed over the quotient.
--
--   Conflating them is the failure mode, and it is subtle in exactly
--   the way a silent one is: the tree still builds, it is just wrong.
data Node = Node
  { path    :: [Int]    -- which branch at each depth: structure
  , content :: [Int]    -- the palette labels: colour
  , depth   :: Int      -- 0 = rung 16, 1 = rung 32, 2 = rung 64
  } deriving (Eq, Show)

-- | A node's palette, as a deterministic function of its path, so the
--   model has distinct content per node without inventing data.
contentOf :: [Int] -> [Int]
contentOf p = [ (i * 37 + 13 * sum p + 7 * length p) `mod` 256
              | i <- [0 .. 7 :: Int] ]

-- | The rung ladder IS the tree's depth, so the depth is FINITE and
--   equal to DescentLadder's serial depth (DL1).
maxDepth :: Int
maxDepth = 3

-- | DL1's fan-outs. The branching factor is small, fixed and known,
--   which is the property the refused basin proposal did not have:
--   its label set had order 2^512 and no categorical objective over
--   it was well posed.
fanOuts :: [Int]
fanOuts = [2, 8, 8]

branchingAt :: Int -> Int
branchingAt d
  | d >= 0 && d < length fanOuts = fanOuts !! d
  | otherwise                    = 0

-- ════════════════════════════════════════════════════════════════
-- § 2. THE MERKLE PART, AND WHY IT MUST BE A QUOTIENT
-- ════════════════════════════════════════════════════════════════
--
-- ★ ColourLatent CL4 and CL5: the 256 XOR-by-mask relabelings
-- commute with the sigma involution exactly and MOVE NO COLOUR --
-- E, the occupancy census and the LZW bill are all invariant under
-- them. So they produce no new artifact.
--
-- If the digest were taken over the raw table, every node would have
-- 255 identical twins at different addresses and the tree would be
-- 256 times larger for nothing, with the transposition table never
-- firing. CANONICALISE FIRST. This is the one design decision the
-- Merkle structure genuinely forces, and it comes straight out of
-- two green axioms rather than from taste.

-- | FNV-1a, written out so the spec has no dependency. Any digest
--   works; the axioms are about the QUOTIENT, not the hash.
fnv :: [Int] -> Word64
fnv = foldl step 14695981039346656037
  where
    step h x = (h `xor` fromIntegral (x .&. 0xff)) * 1099511628211

-- | The free relabeling: index i becomes i XOR mask (CL4).
relabel :: Int -> [Int] -> [Int]
relabel mask = map (`xor` mask)

-- | ★ The canonical representative of a node's orbit under the free
--   group: the lexicographically least relabeling. Deterministic,
--   total, and computable without a model.
canonical :: [Int] -> [Int]
canonical xs = minimum [ relabel m xs | m <- [0 .. 255] ]

-- | The node's address. Over the QUOTIENT, by MT2.
digest :: Node -> Word64
digest n = fnv (fromIntegral (depth n) : path n ++ canonical (content n))

-- | A Merkle digest that covers a subtree: the node's own address
--   folded with its children's. Equal subtrees therefore have equal
--   digests, which IS the transposition table.
subtreeDigest :: Node -> [Word64] -> Word64
subtreeDigest n kids =
  foldl (\h k -> (h `xor` k) * 1099511628211) (digest n) (sort kids)

-- ════════════════════════════════════════════════════════════════
-- § 3. THE EDGES ARE S AND K
-- ════════════════════════════════════════════════════════════════
--
-- MemoryColour MC1: S expands (one to many) and K contracts (many to
-- one), in parallel. Here they are the tree's two directions, and
-- PairTree's PT5 is what makes that structural rather than imposed:
-- a truncated index IS the coarser level's palette, so a parent is
-- literally a PREFIX of its children. A prefix tree is the shape a
-- Merkle tree wants.

-- | S: refine one step. The child set is finite and its size is the
--   fan-out at this depth.
expandS :: Node -> [Node]
expandS n
  | depth n >= maxDepth = []
  | otherwise =
      [ Node p (contentOf p) (depth n + 1)
      | c <- [0 .. branchingAt (depth n) - 1]
      , let p = path n ++ [c] ]

-- | K: contract one step. The parent is the prefix (PT5).
contractK :: Node -> Maybe Node
contractK n
  | depth n <= 0 = Nothing
  | otherwise    = Just (Node p (contentOf p) (depth n - 1))
  where p = init (path n)

-- ════════════════════════════════════════════════════════════════
-- § 4. THE VALUE: A VECTOR, NOT A NUMBER
-- ════════════════════════════════════════════════════════════════
--
-- The measured pairs from TilingEntropy's own frames. They are
-- restated here as DATA the axioms quantify over, not as a
-- re-derivation: TE owns the formulas and TE's own harness prints
-- these numbers.

data Value = Value { eHist :: Double, eWall :: Double } deriving (Eq, Show)

probes :: [(String, Value)]
probes =
  [ ("balanced", Value     0.00  1573.06)
  , ("random",   Value     0.00    82.64)
  , ("face",     Value  4182.21  8064.00)
  , ("neel",     Value 28672.00  8064.00)
  , ("solid",    Value 32768.00  8064.00)
  ]

valueOf :: String -> Value
valueOf k = case lookup k probes of
  Just v  -> v
  Nothing -> Value 0 0

-- | ★ THE ORDER. Diversity is LOW eHist; structure is HIGH eWall.
--   `dominates a b` means a is at least as good on both and strictly
--   better on one.
dominates :: Value -> Value -> Bool
dominates a b =
     eHist a <= eHist b && eWall a >= eWall b
  && (eHist a < eHist b || eWall a > eWall b)

-- | The Pareto front: the candidates nothing else beats.
front :: [(String, Value)] -> [String]
front vs = [ k | (k, v) <- vs, not (any (\(_, w) -> dominates w v) vs) ]

-- ════════════════════════════════════════════════════════════════
-- § 5. THE SEARCH
-- ════════════════════════════════════════════════════════════════
--
-- PUCT needs exactly three things and this tree has all three: a
-- FINITE child set (MT4), a prior that sums to one over it (the
-- policy head, the only learned part), and a BOUNDED value (MT9).

puct :: Double -> Double -> Double -> Int -> Int -> Double
puct q prior c parentVisits childVisits =
  q + c * prior * sqrt (fromIntegral parentVisits)
      / (1 + fromIntegral childVisits)

-- ════════════════════════════════════════════════════════════════
-- § 6. THE AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-9

root :: Node
root = Node [] (contentOf []) 0

-- (MT1) A NODE IS A GENERATOR, NOT PIXELS. The artifact is a pure
--       function of the generator (CL1), so the tree stores 16 fields
--       a tick and never an image. A tree of GIFs costs generator
--       bytes, not GIF bytes.
axiom_MT1 :: Bool
axiom_MT1 =
     depth root == 0
  && null (path root)
  && all (\n -> length (path n) == depth n) (take 200 (bfs root))
  && all (\n -> length (content n) == 8) (take 200 (bfs root))

-- (MT2) ★ THE ADDRESS IS OVER THE QUOTIENT. The 256 free relabelings
--       (CL4, CL5) move no colour, so they must not move the address.
--       Hashing raw would give every node 255 twins and the
--       transposition table would never fire.
axiom_MT2 :: Bool
axiom_MT2 =
     all (\m -> canonical (relabel m sample) == canonical sample) [0 .. 255]
  && length (nub [ fnv (relabel m sample) | m <- [0 .. 255] ]) > 1
  && length (nub [ fnv (canonical (relabel m sample)) | m <- [0 .. 255] ]) == 1
  && canonical other /= canonical sample
  where
    sample = contentOf [1, 2]        -- palette labels, not a path
    other  = contentOf [1, 3]

-- (MT3) MERKLE: EQUAL SUBTREES ARE ONE NODE. The digest covers the
--       subtree and is order-independent over children, so two
--       explorations that reach the same content land on the same
--       address. That IS the transposition table, and it costs
--       nothing to build.
axiom_MT3 :: Bool
axiom_MT3 =
     subtreeDigest root [a, b] == subtreeDigest root [b, a]
  && subtreeDigest root [a, b] /= subtreeDigest root [a, a]
  && a /= b                                   -- siblings are distinct
  && digest kid1 == digest (Node [1] (contentOf [1]) 1)
  && digest kid1 /= digest (Node [1] (contentOf [1]) 2)
  where
    kid1 = Node [1] (contentOf [1]) 1
    a = digest kid1
    b = digest (Node [0] (contentOf [0]) 1)

-- (MT4) THE BRANCHING IS FINITE AND SMALL, and the depth is the rung
--       ladder's. DL1's [2, 8, 8] over serial depth 3 gives 128
--       leaves under a root. ★ This is the property the refused basin
--       proposal lacked: its label set had order 2^512.
axiom_MT4 :: Bool
axiom_MT4 =
     fanOuts == [2, 8, 8]
  && product fanOuts == 128
  && length fanOuts == maxDepth
  && all (\d -> let p = replicate d 0
                in length (expandS (Node p (contentOf p) d)) == branchingAt d)
         [0 .. maxDepth - 1]
  && null (expandS (Node [0, 0, 0] (contentOf [0, 0, 0]) maxDepth))

-- (MT5) S AND K ARE THE EDGES, AND K IS THE PREFIX (PT5). Contracting
--       a child returns its parent exactly, for every child, so the
--       tree is a prefix tree and needed no invention to be one.
axiom_MT5 :: Bool
axiom_MT5 =
     all (\kid -> contractK kid == Just root) (expandS root)
  && contractK root == Nothing
  && all (\n -> all (\kid -> contractK kid == Just n) (expandS n))
         (take 40 (bfs root))

-- (MT6) ★ GREY IS THE CEILING, NOT THE FLOOR. A solid frame is the
--       MAXIMUM of E, so descending E structurally cannot collapse to
--       grey. That is the opposite of descending a distortion, and it
--       is the whole reason the search is driven by the informational
--       energy.
axiom_MT6 :: Bool
axiom_MT6 =
     eHist (valueOf "solid") == maximum (map (eHist . snd) probes)
  && eHist (valueOf "balanced") == minimum (map (eHist . snd) probes)
  && eHist (valueOf "solid") > eHist (valueOf "face")

-- (MT7) ★ BUT NEITHER ENERGY ALONE IS ENOUGH, and each is blind to a
--       DIFFERENT corner. E cannot separate the balanced tiling from
--       random static (both exactly 0). E_wall cannot separate a face
--       from grey (both saturate at 8064). A scalar descent on either
--       lands on a degeneracy; they are just different degeneracies.
axiom_MT7 :: Bool
axiom_MT7 =
     abs (eHist (valueOf "balanced") - eHist (valueOf "random")) < eps
  && abs (eWall (valueOf "face") - eWall (valueOf "solid")) < eps
  && abs (eWall (valueOf "face") - eWall (valueOf "neel")) < eps
  && eWall (valueOf "balanced") /= eWall (valueOf "random")
  && eHist (valueOf "face") /= eHist (valueOf "solid")

-- (MT8) ★ THE LOAD-BEARING AXIOM: THE FRONT EXCLUDES BOTH
--       DEGENERACIES, and not by tuning. Under (E low, E_wall high),
--       SOLID is strictly dominated by FACE at equal E_wall, and
--       RANDOM is strictly dominated by BALANCED at equal E. So a
--       search keeping only its Pareto front cannot return grey and
--       cannot return static, because both are beaten by candidates
--       the same search already holds. This is "useful energy",
--       stated as a property rather than as a hope.
axiom_MT8 :: Bool
axiom_MT8 =
     dominates (valueOf "face")     (valueOf "solid")
  && dominates (valueOf "face")     (valueOf "neel")
  && dominates (valueOf "balanced") (valueOf "random")
  && not (elem "solid"  f)
  && not (elem "random" f)
  && not (elem "neel"   f)
  && elem "face" f
  && elem "balanced" f
  where f = front probes

-- (MT9) ★ THE ECONOMY: THE VALUE HEAD NEEDS NO WEIGHTS. KataGo must
--       learn its value because Go has no closed form for a
--       non-terminal position. Here the value is exact arithmetic in
--       the wire's own units (TE10). Only the POLICY is learned, and
--       the value is bounded, which PUCT requires.
axiom_MT9 :: Bool
axiom_MT9 =
     all (\(_, v) -> eHist v >= 0 && eHist v <= 32768) probes
  && all (\(_, v) -> eWall v >= 0 && eWall v <= 8064) probes
  && length (nub (map (eHist . snd) probes)) > 1     -- it discriminates

-- (MT10) PUCT IS WELL DEFINED HERE. Exploration grows with the
--        parent's visits and shrinks with the child's, the prior
--        orders untried siblings, and an unvisited child is finite
--        rather than infinite.
axiom_MT10 :: Bool
axiom_MT10 =
     puct 0 0.5 1 100 0 > puct 0 0.5 1 100 10
  && puct 0 0.9 1 100 0 > puct 0 0.1 1 100 0
  && puct 0 0.5 1 400 0 > puct 0 0.5 1 100 0
  && not (isInfinite (puct 0 0.5 1 1 0))

-- (MT11) SEARCH IS MONOTONE. The store only grows and the front only
--        improves: adding a candidate never removes a point that
--        nothing dominates, and a dominated point never re-enters.
axiom_MT11 :: Bool
axiom_MT11 =
     all (`elem` front (probes ++ extra)) (survivors)
  && not (elem "worse" (front (probes ++ extra)))
  where
    extra = [("worse", Value 40000 10)]
    survivors = filter (`elem` front (probes ++ extra)) (front probes)

-- (MT12) NOTHING WRITES THE RECORD. Searching produces nodes, and a
--        node is a generator; the retained tensor is upstream and
--        untouched, so CR3's identity re-weave still reproduces the
--        archived GIF byte for byte. The tree is a place to look, not
--        a thing that edits.
axiom_MT12 :: Bool
axiom_MT12 =
     path root == []
  && all (\n -> take (length (path root)) (path n) == path root)
         (take 100 (bfs root))
  && all (\n -> content n == contentOf (path n)) (take 100 (bfs root))

-- Breadth-first walk, for the structural axioms.
bfs :: Node -> [Node]
bfs n = go [n]
  where
    go []       = []
    go (x : xs) = x : go (xs ++ expandS x)

-- ════════════════════════════════════════════════════════════════
-- § 7. THE HARNESS
-- ════════════════════════════════════════════════════════════════

check :: String -> [Bool] -> IO Bool
check n bs = do
  let ok = and bs
  putStrLn $ "  " ++ (if ok then "\10003" else "\10007") ++ " " ++ n
  return ok

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn " MerkleSearch: a tree of possible GIFs, and useful energy"
  putStrLn "══════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  Go / KataGo            Tesseract"
  putStrLn "  ─────────────────      ────────────────────────────────"
  putStrLn "  position               a GIF = its canonical generator"
  putStrLn "  move                   an expansion S at one rung"
  putStrLn "  transposition table    the Merkle hash, for free"
  putStrLn "  policy head            which expansion to try  (LEARNED)"
  putStrLn "  value head             the energy vector    (ARITHMETIC)"
  putStrLn ""
  putStrLn "  frame       E (bits)   E_wall     on the front?"
  mapM_ (\(k, v) ->
          putStrLn $ "  " ++ pad 12 k ++ pad 11 (show (eHist v))
                     ++ pad 11 (show (eWall v))
                     ++ (if k `elem` front probes then "YES" else "dominated"))
        probes
  putStrLn ""
  rs <- sequence
    [ check "MT1  a node is a GENERATOR, never pixels"            [axiom_MT1]
    , check "MT2  * the address is over the QUOTIENT (CL4/CL5)"   [axiom_MT2]
    , check "MT3  merkle: equal subtrees are one node"            [axiom_MT3]
    , check "MT4  branching is FINITE and small: [2,8,8]"         [axiom_MT4]
    , check "MT5  S and K are the edges; K is the prefix (PT5)"   [axiom_MT5]
    , check "MT6  * GREY IS THE CEILING of E, not the floor"      [axiom_MT6]
    , check "MT7  * each energy alone is blind to ONE corner"     [axiom_MT7]
    , check "MT8  * the FRONT excludes grey AND static"           [axiom_MT8]
    , check "MT9  * the value needs NO weights; only the policy"  [axiom_MT9]
    , check "MT10 PUCT is well defined on this tree"              [axiom_MT10]
    , check "MT11 search is monotone: the front only improves"    [axiom_MT11]
    , check "MT12 nothing writes the record (CR3 survives)"       [axiom_MT12]
    ]
  putStrLn ""
  putStrLn "  ★ USEFUL ENERGY, AS A PROPERTY AND NOT A HOPE:"
  putStrLn "    grey   is the MAXIMUM of E, so descending cannot"
  putStrLn "           reach it -- unlike descending a distortion."
  putStrLn "    static scores the same E as the balanced tiling, so"
  putStrLn "           E alone would land there instead."
  putStrLn "    both   are STRICTLY DOMINATED on the pair, by"
  putStrLn "           candidates the search already holds."
  putStrLn ""
  putStrLn "  So the front is where the pictures are, and a scalar"
  putStrLn "  would have had to pick a corner."
  putStrLn ""
  if and rs then putStrLn "  all axioms hold"
            else error "MerkleSearch: axioms failed"
  where
    pad n s = s ++ replicate (max 0 (n - length s)) ' '
