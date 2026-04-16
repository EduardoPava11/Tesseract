{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}

-- | Spatial Graphs of Color in a 64³ Tensor
--
--   The 64³ tensor decomposes as 1D (frame walk) × 2D (spatial plane):
--     - 64 frames along z-axis (temporal / "pixel walk")
--     - 64×64 = 4096 pixels per frame (spatial)
--     - 256 colors per frame (GIF spec)
--     - 4096 / 256 = 16 pixels per color per frame
--
--   Each color c ∈ {0..255} in frame z has a SPATIAL GRAPH:
--     G(c,z) = { (x,y) | pixel(x,y,z) = c }
--     |G(c,z)| ≈ 16
--
--   These graphs can cluster (spatially coherent regions)
--   or scatter (noise-like distribution).
--
--   Pairing two 64³ tensors A, B gives PAIRED graphs:
--     (G_A(c,z), G_B(c,z)) — how the same color's footprint
--     differs between the two tensors.

module ColorGraphs where

import Data.List (sortBy, groupBy, intercalate, foldl')
import Data.Ord (comparing, Down(..))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import System.Random (mkStdGen, randomR, StdGen)

-- ============================================================
-- § 1. Types
-- ============================================================

type Coord2D = (Int, Int)        -- (x, y) within a frame
type FrameIdx = Int              -- z ∈ [0..63]
type ColorIdx = Int              -- c ∈ [0..255]

-- | A spatial graph: the set of pixel positions for one color in one frame
type SpatialGraph = [Coord2D]

-- | A full frame: 64×64 grid of color indices
type Frame = Map Coord2D ColorIdx

-- | A full 64³ tensor: 64 frames
type Tensor64 = Map FrameIdx Frame

-- | A paired spatial graph: same color, same frame, two tensors
data PairedGraph = PairedGraph
  { pgColor    :: ColorIdx
  , pgFrame    :: FrameIdx
  , pgGraphA   :: SpatialGraph
  , pgGraphB   :: SpatialGraph
  } deriving (Show)

-- ============================================================
-- § 2. Tensor Generation
-- ============================================================

-- | Generate a tensor where each frame has exactly 256 colors,
--   each appearing exactly 16 times (4096 / 256 = 16).
--   Colors are assigned with spatial coherence controlled by
--   a clustering parameter.
generateTensor :: StdGen -> Double -> (Tensor64, StdGen)
generateTensor gen0 clustering =
  foldl' buildFrame (Map.empty, gen0) [0..63]
  where
    buildFrame (tensor, g) z =
      let (frame, g') = generateFrame g z clustering
      in (Map.insert z frame tensor, g')

generateFrame :: StdGen -> FrameIdx -> Double -> (Frame, StdGen)
generateFrame gen0 _z clustering =
  let -- Generate 4096 positions
      positions = [(x, y) | y <- [0..63], x <- [0..63]]
      -- Assign colors with spatial coherence
      -- High clustering: nearby pixels get similar colors
      -- Low clustering: random assignment
      (assignments, genFinal) = assignColors gen0 positions clustering
      frame = Map.fromList (zip positions assignments)
  in (frame, genFinal)

assignColors :: StdGen -> [Coord2D] -> Double -> ([ColorIdx], StdGen)
assignColors gen0 positions clustering =
  -- Strategy: divide the 64×64 grid into 16×16 blocks (16 blocks)
  -- then assign colors based on block + noise
  foldl' assignOne ([], gen0) positions
  where
    assignOne (acc, g) (x, y) =
      let -- Base color from spatial position (clustered assignment)
          blockX = x `div` 4   -- 0..15
          blockY = y `div` 4   -- 0..15
          baseColor = blockY * 16 + blockX  -- 0..255, spatially coherent
          -- Random color
          (randColor, g1) = randomR (0, 255) g
          -- Mix: with probability=clustering, use base; else random
          (roll, g2) = randomR (0.0 :: Double, 1.0) g1
          color = if roll < clustering then baseColor else randColor
      in (acc ++ [color], g2)

-- ============================================================
-- § 3. Spatial Graph Extraction
-- ============================================================

-- | Extract the spatial graph for color c in frame z
extractGraph :: Tensor64 -> ColorIdx -> FrameIdx -> SpatialGraph
extractGraph tensor c z =
  case Map.lookup z tensor of
    Nothing -> []
    Just frame ->
      [ pos | (pos, col) <- Map.toList frame, col == c ]

-- | Extract ALL spatial graphs for a frame (color → positions)
allGraphsInFrame :: Tensor64 -> FrameIdx -> Map ColorIdx SpatialGraph
allGraphsInFrame tensor z =
  case Map.lookup z tensor of
    Nothing -> Map.empty
    Just frame ->
      Map.foldlWithKey' (\acc pos col ->
        Map.insertWith (++) col [pos] acc
      ) Map.empty frame

-- | Extract paired graphs between two tensors
extractPairedGraph :: Tensor64 -> Tensor64 -> ColorIdx -> FrameIdx -> PairedGraph
extractPairedGraph tA tB c z = PairedGraph
  { pgColor  = c
  , pgFrame  = z
  , pgGraphA = extractGraph tA c z
  , pgGraphB = extractGraph tB c z
  }

-- ============================================================
-- § 4. Spatial Graph Metrics
-- ============================================================

-- | Centroid of a spatial graph
centroid :: SpatialGraph -> (Double, Double)
centroid [] = (0, 0)
centroid ps =
  let n = fromIntegral (length ps)
      sx = sum [fromIntegral x | (x, _) <- ps]
      sy = sum [fromIntegral y | (_, y) <- ps]
  in (sx / n, sy / n)

-- | Mean pairwise distance (measures scatter vs clustering)
--   Low value = clustered, high value = scattered
meanPairDist :: SpatialGraph -> Double
meanPairDist [] = 0
meanPairDist [_] = 0
meanPairDist ps =
  let pairs = [(a, b) | a <- ps, b <- ps, a /= b]
      dist (x1, y1) (x2, y2) =
        sqrt (fromIntegral ((x1-x2)^(2::Int) + (y1-y2)^(2::Int)))
      totalDist = sum [dist a b | (a, b) <- pairs]
      nPairs = fromIntegral (length pairs)
  in totalDist / nPairs

-- | Bounding box area (another clustering measure)
boundingBoxArea :: SpatialGraph -> Int
boundingBoxArea [] = 0
boundingBoxArea ps =
  let xs = map fst ps
      ys = map snd ps
      w = maximum xs - minimum xs + 1
      h = maximum ys - minimum ys + 1
  in w * h

-- | Overlap between two spatial graphs (shared pixel positions)
overlap :: SpatialGraph -> SpatialGraph -> Int
overlap ga gb = length [p | p <- ga, p `elem` gb]

-- | Hausdorff-like distance between paired graphs
--   (max of min-distances from each point in A to nearest in B)
hausdorff :: SpatialGraph -> SpatialGraph -> Double
hausdorff [] _ = 0
hausdorff _ [] = 0
hausdorff ga gb =
  let dist (x1,y1) (x2,y2) =
        sqrt (fromIntegral ((x1-x2)^(2::Int) + (y1-y2)^(2::Int)))
      minDistTo ps p = minimum [dist p q | q <- ps]
      dAB = maximum [minDistTo gb p | p <- ga]
      dBA = maximum [minDistTo ga p | p <- gb]
  in max dAB dBA

-- | Centroid shift between paired graphs
centroidShift :: SpatialGraph -> SpatialGraph -> Double
centroidShift ga gb =
  let (cx1, cy1) = centroid ga
      (cx2, cy2) = centroid gb
  in sqrt ((cx1-cx2)**2 + (cy1-cy2)**2)

-- ============================================================
-- § 5. The 1D + 2D Decomposition
-- ============================================================

-- | For a given color, trace its spatial graph across ALL frames.
--   This is the 1D walk through the 2D graphs:
--   z ↦ G(c, z)
--
--   The "1D" part: how does the graph CHANGE frame-to-frame?
--   The "2D" part: what does the graph LOOK LIKE in each frame?
colorTrajectory :: Tensor64 -> ColorIdx -> [(FrameIdx, SpatialGraph)]
colorTrajectory tensor c =
  [ (z, extractGraph tensor c z) | z <- [0..63] ]

-- | Measure how a color's spatial graph evolves along the 1D walk
--   Returns per-frame: (frame, pixel_count, mean_pair_dist, centroid)
trajectoryStats :: Tensor64 -> ColorIdx
                -> [(FrameIdx, Int, Double, (Double, Double))]
trajectoryStats tensor c =
  [ (z, length g, meanPairDist g, centroid g)
  | (z, g) <- colorTrajectory tensor c
  ]

-- | Frame-to-frame graph similarity along the 1D walk
--   How much does color c's footprint change between adjacent frames?
temporalCoherence :: Tensor64 -> ColorIdx -> [Double]
temporalCoherence tensor c =
  let traj = colorTrajectory tensor c
      pairs = zip traj (tail traj)
  in [ let ov = overlap g1 g2
           union = length g1 + length g2 - ov
       in if union == 0 then 1.0
          else fromIntegral ov / fromIntegral union  -- Jaccard
     | ((_, g1), (_, g2)) <- pairs
     ]

-- ============================================================
-- § 6. Paired Graph Analysis
-- ============================================================

-- | For a color c and frame z, compare the spatial graphs of
--   tensors A and B. This is the PAIRING operation.
--
--   The paired graph captures:
--     - Do the same colors cluster in the same places?
--     - Or does the same color scatter differently?
--     - What is the "spatial delta" between the two tensors?
analyzePair :: Tensor64 -> Tensor64 -> ColorIdx -> FrameIdx
            -> (Int, Int, Int, Double, Double)
            -- ^ (sizeA, sizeB, overlap, hausdorff, centroid_shift)
analyzePair tA tB c z =
  let ga = extractGraph tA c z
      gb = extractGraph tB c z
      ov = overlap ga gb
      hd = hausdorff ga gb
      cs = centroidShift ga gb
  in (length ga, length gb, ov, hd, cs)

-- ============================================================
-- § 7. ASCII Visualization
-- ============================================================

-- | Render a 64×64 frame as a small ASCII grid (downsampled to 32×32)
--   showing where a specific color appears
renderGraph :: SpatialGraph -> String
renderGraph g =
  let grid = Map.fromList [(p, True) | p <- g]
      -- Downsample: each 2×2 block → 1 char
      renderCell bx by =
        let hits = length [ () | dx <- [0,1], dy <- [0,1]
                          , Map.member (bx*2+dx, by*2+dy) grid ]
        in case hits of
             0 -> '·'
             1 -> '░'
             2 -> '▒'
             3 -> '▓'
             4 -> '█'
             _ -> '?'
  in unlines [ [ renderCell bx by | bx <- [0..31] ] | by <- [0..31] ]

-- | Side-by-side render of paired graphs (compact, 16×16)
renderPairedCompact :: SpatialGraph -> SpatialGraph -> String
renderPairedCompact ga gb =
  let gridA = Map.fromList [(p, True) | p <- ga]
      gridB = Map.fromList [(p, True) | p <- gb]
      renderCell grid bx by =
        let hits = length [ () | dx <- [0..3], dy <- [0..3]
                          , Map.member (bx*4+dx, by*4+dy) grid ]
        in if hits > 0 then '█' else '·'
      rowA by = [ renderCell gridA bx by | bx <- [0..15] ]
      rowB by = [ renderCell gridB bx by | bx <- [0..15] ]
  in unlines [ rowA by ++ "  │  " ++ rowB by | by <- [0..15] ]

-- ============================================================
-- § 8. Main: Demonstrate Everything
-- ============================================================

main :: IO ()
main = do
  putStrLn "══════════════════════════════════════════════════════"
  putStrLn " 1D + 2D Color Space: Spatial Graphs in 64³ Tensors"
  putStrLn "══════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  64×64×64 = 262,144 voxels"
  putStrLn "  256 colors/frame → 4096/256 = 16 pixels per color"
  putStrLn "  Each color has a SPATIAL GRAPH per frame"
  putStrLn "  64 frames = 1D walk through these 2D graphs"
  putStrLn ""

  -- Generate two tensors with different clustering
  let gen0 = mkStdGen 42
  let (tensorA, gen1) = generateTensor gen0 0.8   -- high clustering
  let (tensorB, _)    = generateTensor gen1 0.3   -- low clustering

  putStrLn "── Tensor A: high clustering (0.8) ──"
  putStrLn "── Tensor B: low clustering  (0.3) ──"
  putStrLn ""

  -- Pick a color and show its spatial graph
  let testColor = 85
  let testFrame = 32

  putStrLn $ "┌─ Color " ++ show testColor ++ ", Frame " ++ show testFrame ++ " ─┐"
  putStrLn ""

  let gA = extractGraph tensorA testColor testFrame
  let gB = extractGraph tensorB testColor testFrame
  putStrLn $ "  Graph A: " ++ show (length gA) ++ " pixels"
  putStrLn $ "  Graph B: " ++ show (length gB) ++ " pixels"
  putStrLn ""

  putStrLn "  Spatial footprint (A left │ B right, 16×16 blocks):"
  putStrLn $ renderPairedCompact gA gB

  -- Metrics
  putStrLn "  ── Spatial Metrics ──"
  putStrLn $ "  Mean pair dist A: " ++ showF (meanPairDist gA)
  putStrLn $ "  Mean pair dist B: " ++ showF (meanPairDist gB)
  putStrLn $ "  Bounding box A:   " ++ show (boundingBoxArea gA)
  putStrLn $ "  Bounding box B:   " ++ show (boundingBoxArea gB)
  putStrLn $ "  Centroid A:       " ++ showC (centroid gA)
  putStrLn $ "  Centroid B:       " ++ showC (centroid gB)
  putStrLn ""

  -- Paired analysis
  putStrLn "  ── Paired Graph Analysis ──"
  let (sA, sB, ov, hd, cs) = analyzePair tensorA tensorB testColor testFrame
  putStrLn $ "  Pixels in A:      " ++ show sA
  putStrLn $ "  Pixels in B:      " ++ show sB
  putStrLn $ "  Overlap:          " ++ show ov ++ " shared positions"
  putStrLn $ "  Hausdorff dist:   " ++ showF hd
  putStrLn $ "  Centroid shift:   " ++ showF cs
  putStrLn ""

  -- 1D walk: show how this color evolves across frames
  putStrLn "── 1D Walk: Color trajectory across frames ──"
  putStrLn ""
  putStrLn "  frame │ #pxA │ #pxB │ clustA │ clustB │ overlap │ centroid_shift"
  putStrLn "  ──────┼──────┼──────┼────────┼────────┼─────────┼───────────────"

  let frames = [0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 63]
  mapM_ (\z -> do
    let ga = extractGraph tensorA testColor z
    let gb = extractGraph tensorB testColor z
    let ov' = overlap ga gb
    let cs' = centroidShift ga gb
    putStrLn $ "  " ++ padL 5 (show z)
            ++ " │ " ++ padL 4 (show (length ga))
            ++ " │ " ++ padL 4 (show (length gb))
            ++ " │ " ++ padL 6 (showF2 (meanPairDist ga))
            ++ " │ " ++ padL 6 (showF2 (meanPairDist gb))
            ++ " │ " ++ padL 7 (show ov')
            ++ " │ " ++ showF cs'
    ) frames

  putStrLn ""

  -- Temporal coherence
  putStrLn "── Temporal Coherence (Jaccard similarity, adjacent frames) ──"
  let jacA = temporalCoherence tensorA testColor
  let jacB = temporalCoherence tensorB testColor
  let avgJacA = sum jacA / fromIntegral (length jacA)
  let avgJacB = sum jacB / fromIntegral (length jacB)
  putStrLn $ "  Tensor A mean Jaccard: " ++ showF avgJacA
            ++ " (high = graph stable across frames)"
  putStrLn $ "  Tensor B mean Jaccard: " ++ showF avgJacB
            ++ " (low = graph reshuffles each frame)"
  putStrLn ""

  -- Distribution of graph sizes across ALL colors in one frame
  putStrLn "── Color Histogram: pixels-per-color in frame 32 ──"
  let allA = allGraphsInFrame tensorA 32
  let allB = allGraphsInFrame tensorB 32
  let sizesA = map (\(c, g) -> (c, length g)) (Map.toList allA)
  let sizesB = map (\(c, g) -> (c, length g)) (Map.toList allB)
  let numColorsA = length sizesA
  let numColorsB = length sizesB
  let idealPPC = 16 :: Int  -- 4096/256

  putStrLn $ "  Tensor A: " ++ show numColorsA ++ " distinct colors present"
  putStrLn $ "  Tensor B: " ++ show numColorsB ++ " distinct colors present"
  putStrLn $ "  Ideal: 256 colors × " ++ show idealPPC ++ " pixels each"
  putStrLn ""

  -- Show top-10 most frequent colors and bottom-10
  let sortedA = sortBy (comparing (Down . snd)) sizesA
  putStrLn "  Tensor A — top 5 colors (most pixels) vs bottom 5:"
  mapM_ (\(c, n) ->
    putStrLn $ "    color " ++ padL 3 (show c) ++ ": "
            ++ replicate (min n 60) '█' ++ " (" ++ show n ++ "px)"
    ) (take 5 sortedA)
  putStrLn "    ..."
  mapM_ (\(c, n) ->
    putStrLn $ "    color " ++ padL 3 (show c) ++ ": "
            ++ replicate (min n 60) '█' ++ " (" ++ show n ++ "px)"
    ) (take 5 (reverse sortedA))
  putStrLn ""

  -- Summary
  putStrLn "══════════════════════════════════════════════════════"
  putStrLn " Key Insight: 1D + 2D decomposition"
  putStrLn ""
  putStrLn "   The 64³ tensor is NOT a flat array of 262K values."
  putStrLn "   It is 64 frames × (64×64 spatial), and each of the"
  putStrLn "   256 colors per frame has a SPATIAL GRAPH — a 2D"
  putStrLn "   footprint of ~16 pixels."
  putStrLn ""
  putStrLn "   1D (z-axis): the walk BETWEEN frames"
  putStrLn "     → temporal coherence: does the graph persist?"
  putStrLn "     → Jaccard similarity measures frame-to-frame stability"
  putStrLn ""
  putStrLn "   2D (x,y plane): the graph WITHIN each frame"
  putStrLn "     → clustering: are same-color pixels neighbors?"
  putStrLn "     → mean pairwise distance measures spatial spread"
  putStrLn ""
  putStrLn "   PAIRING two tensors gives PAIRED GRAPHS:"
  putStrLn "     → same color, same frame, different spatial footprint"
  putStrLn "     → Hausdorff distance: worst-case spatial disagreement"
  putStrLn "     → centroid shift: bulk motion of the color mass"
  putStrLn "     → overlap: how many pixels land in the same spot"
  putStrLn "══════════════════════════════════════════════════════"

-- Helpers
showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 100) :: Int) / 100.0 :: Double)
          in take 7 (s ++ repeat '0')

showF2 :: Double -> String
showF2 x = let s = show (fromIntegral (round (x * 10) :: Int) / 10.0 :: Double)
           in take 5 (s ++ repeat '0')

showC :: (Double, Double) -> String
showC (x, y) = "(" ++ showF x ++ ", " ++ showF y ++ ")"

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s
