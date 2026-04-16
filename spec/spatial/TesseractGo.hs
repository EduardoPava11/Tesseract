{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- TesseractGo: 19×19 Color Blocks as Go Positions
--
-- THESIS:
--   1D Time ⊕ 3D sRGB = 4D Tesseract
--   3D sRGB decomposes into 3 pairwise comparisons:
--     R/G, G/B, B/R
--   Each comparison over a 19×19 block = a Go position.
--   Go territory analysis reveals SPATIAL COLOR STRUCTURE
--   that histograms alone cannot see.
--
-- The 19×19 block is both:
--   - A camera downsample unit (361 source pixels → 1 output pixel)
--   - A Go board (361 intersections with territory/influence)
--
-- Three boards per block capture all pairwise channel relationships.
-- KataGo-style evaluation gives: territory, influence, boundaries.
-- These inform WHICH pixels to dither and HOW.
-- ════════════════════════════════════════════════════════════════

module TesseractGo where

import Data.List (foldl', group, sort, sortBy)
import Data.Ord (comparing, Down(..))
import qualified Data.Map.Strict as Map
import Data.Array

-- ════════════════════════════════════════════════════════════════
-- § 1. THE GO BOARD (algebraic types)
-- ════════════════════════════════════════════════════════════════

-- | A stone on the board: which channel dominates at this position
data Stone = Black    -- channel A dominates (A > B + threshold)
           | White    -- channel B dominates (B > A + threshold)
           | Empty    -- balanced (|A - B| < threshold) = BOUNDARY
           deriving (Show, Eq, Ord)

-- | A 19×19 Go position from one channel pair comparison
type Board = Array (Int, Int) Stone

boardSize :: Int
boardSize = 19

-- | The three channel-pair boards from one 19×19 block
data ColorBoards = ColorBoards
  { rgBoard :: !Board   -- Red vs Green
  , gbBoard :: !Board   -- Green vs Blue
  , brBoard :: !Board   -- Blue vs Red
  } deriving (Show)

-- | Threshold for "balanced" — below this, the pixel is at the boundary
boundaryThreshold :: Double
boundaryThreshold = 0.08  -- ~20 in 8-bit

-- ════════════════════════════════════════════════════════════════
-- § 2. BLOCK → THREE GO BOARDS
-- ════════════════════════════════════════════════════════════════

-- | Convert a 19×19 block of RGB pixels to three Go boards.
--   Each pixel becomes an intersection on each board.
blockToBoards :: [(Double, Double, Double)] -> ColorBoards
blockToBoards pixels =
  let positions = [ ((x, y), pixels !! (y * boardSize + x))
                  | y <- [0..boardSize-1], x <- [0..boardSize-1] ]

      toStone :: Double -> Double -> Stone
      toStone a b
        | a - b > boundaryThreshold = Black
        | b - a > boundaryThreshold = White
        | otherwise                 = Empty  -- boundary pixel

      makeBoard :: ((Double,Double,Double) -> Double)
                -> ((Double,Double,Double) -> Double)
                -> Board
      makeBoard chanA chanB =
        array ((0,0), (boardSize-1, boardSize-1))
          [ (pos, toStone (chanA rgb) (chanB rgb))
          | (pos, rgb) <- positions ]

  in ColorBoards
    { rgBoard = makeBoard (\(r,_,_) -> r) (\(_,g,_) -> g)  -- R vs G
    , gbBoard = makeBoard (\(_,g,_) -> g) (\(_,_,b) -> b)  -- G vs B
    , brBoard = makeBoard (\(_,_,b) -> b) (\(r,_,_) -> r)  -- B vs R
    }

-- ════════════════════════════════════════════════════════════════
-- § 3. TERRITORY ANALYSIS (Go concepts → color structure)
-- ════════════════════════════════════════════════════════════════

-- | Territory count: how many intersections each side controls
data Territory = Territory
  { tBlack :: !Int     -- channel A territory (A-dominant pixels)
  , tWhite :: !Int     -- channel B territory (B-dominant pixels)
  , tEmpty :: !Int     -- boundary pixels (neither dominates)
  , tScore :: !Double  -- Black - White as fraction of total (>0 = A dominates)
  } deriving (Show)

countTerritory :: Board -> Territory
countTerritory board =
  let stones = elems board
      b = length (filter (== Black) stones)
      w = length (filter (== White) stones)
      e = length (filter (== Empty) stones)
      total = fromIntegral (b + w + e) :: Double
  in Territory b w e ((fromIntegral b - fromIntegral w) / max 1 total)

-- | Liberties: boundary pixels adjacent to a stone of given color.
--   In Go: liberties = empty intersections adjacent to a group.
--   In color: liberties = boundary pixels next to a channel's territory.
--   MORE LIBERTIES = more dithering potential.
countLiberties :: Board -> Stone -> Int
countLiberties board color =
  length [ pos
         | pos <- range (bounds board)
         , board ! pos == Empty
         , any (\n -> inBounds n && board ! n == color) (neighbors pos) ]
  where
    inBounds (x, y) = x >= 0 && x < boardSize && y >= 0 && y < boardSize
    neighbors (x, y) = [(x-1,y), (x+1,y), (x,y-1), (x,y+1)]

-- | Connected groups: clusters of same-color stones.
--   In Go: a group shares liberties and lives/dies together.
--   In color: a connected region of the same quantization level.
--   LARGE GROUPS = stable visual features. SMALL GROUPS = noise.
countGroups :: Board -> Stone -> Int
countGroups board color =
  let positions = [pos | pos <- range (bounds board), board ! pos == color]
  in length (connectedComponents positions)

connectedComponents :: [(Int, Int)] -> [[(Int, Int)]]
connectedComponents [] = []
connectedComponents (p:ps) =
  let posSet = Map.fromList [(pos, True) | pos <- p:ps]
      (component, remaining) = flood [p] posSet []
  in component : connectedComponents [pos | pos <- ps, not (pos `elem` component)]
  where
    flood [] visited acc = (acc, visited)
    flood (pos:queue) visited acc
      | Map.notMember pos visited = flood queue visited acc
      | otherwise =
          let visited' = Map.delete pos visited
              nbrs = [(x-1,y), (x+1,y), (x,y-1), (x,y+1)]
                where (x, y) = pos
              validNbrs = filter (`Map.member` visited') nbrs
          in flood (validNbrs ++ queue) visited' (pos : acc)

-- ════════════════════════════════════════════════════════════════
-- § 4. GO EVALUATION → QUANTIZATION ADVICE
--
-- The Go evaluation tells us what the histogram cannot:
--
-- TERRITORY → histogram counts (how many pixels per channel level)
-- INFLUENCE → error diffusion pattern (how to spread color)
-- LIBERTIES → dithering budget (how many pixels can be nudged)
-- GROUPS → connected features (what to preserve vs what's noise)
-- SCORE → histogram balance (how skewed the channel is)
--
-- A "complex game" (balanced, many groups, many liberties)
-- = a block with rich color structure → good dithering source
--
-- A "won game" (one side dominates, few liberties)
-- = a monochromatic block → little diversity to extract
-- ════════════════════════════════════════════════════════════════

-- | Full evaluation of one block's color structure
data BlockEval = BlockEval
  { beRG :: !BoardEval    -- Red vs Green game
  , beGB :: !BoardEval    -- Green vs Blue game
  , beBR :: !BoardEval    -- Blue vs Red game
  , beComplexity :: !Double  -- average game complexity (0=trivial, 1=complex)
  , beDitherBudget :: !Int   -- total liberties across all 3 boards
  } deriving (Show)

data BoardEval = BoardEval
  { territory   :: !Territory
  , libertyB    :: !Int       -- Black (channel A) liberties
  , libertyW    :: !Int       -- White (channel B) liberties
  , groupsB     :: !Int       -- Black connected groups
  , groupsW     :: !Int       -- White connected groups
  , complexity  :: !Double    -- (liberties + boundaries) / total
  } deriving (Show)

evaluateBoard :: Board -> BoardEval
evaluateBoard board =
  let terr = countTerritory board
      libB = countLiberties board Black
      libW = countLiberties board White
      grpB = countGroups board Black
      grpW = countGroups board White
      total = fromIntegral (boardSize * boardSize) :: Double
      cmplx = fromIntegral (libB + libW + tEmpty terr) / total
  in BoardEval terr libB libW grpB grpW cmplx

evaluateBlock :: ColorBoards -> BlockEval
evaluateBlock (ColorBoards rg gb br) =
  let eRG = evaluateBoard rg
      eGB = evaluateBoard gb
      eBR = evaluateBoard br
      avgComplexity = (complexity eRG + complexity eGB + complexity eBR) / 3.0
      totalLiberties = libertyB eRG + libertyW eRG
                     + libertyB eGB + libertyW eGB
                     + libertyB eBR + libertyW eBR
  in BlockEval eRG eGB eBR avgComplexity totalLiberties

-- ════════════════════════════════════════════════════════════════
-- § 5. FROM GO TO TESSERACT: The mapping
--
-- Go concept          → Tesseract concept
-- ─────────────────────────────────────────
-- 19×19 board         → 19×19 pixel block (camera downsample unit)
-- Stone (B/W/E)       → Channel comparison (A>B, B>A, boundary)
-- Territory           → Per-channel histogram bin counts
-- Liberties           → Dithering candidates (boundary pixels)
-- Connected group     → Visual feature (connected color region)
-- Group life/death    → Feature significance (preserve vs absorb)
-- Influence           → Error diffusion pattern
-- Game score          → Channel balance (histogram skew)
-- Complex position    → Rich color structure (diverse block)
-- Won game            → Monochromatic block (little diversity)
-- Atari (1 liberty)   → Pixel barely in one bin (easy to dither)
-- Two eyes            → Stable feature (don't dither)
--
-- Three boards (R/G, G/B, B/R) = complete pairwise decomposition
-- of the 3D sRGB cube into 2D slices.
--
-- KataGo NN could evaluate these positions, but simpler territory
-- analysis already gives us what we need for quantization.
-- ════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- § 6. PRACTICAL APPLICATION
--
-- For each 19×19 block in the camera image:
-- 1. Compute three Go boards (R/G, G/B, B/R)
-- 2. Evaluate: territory, liberties, groups, complexity
-- 3. Use evaluation to guide the output pixel:
--    - High complexity → pick a boundary pixel for diversity
--    - Low complexity → pick the dominant color (monochromatic)
--    - Many liberties → good dithering candidate
--    - Few liberties → stable, don't dither
--
-- The Go evaluation replaces (or supplements) the histogram:
--    Histogram: "this block has 200 R>G pixels and 161 G>R pixels"
--    Go eval:   "R has 3 connected groups with 15 liberties,
--                G has 2 groups with 8 liberties,
--                the boundary is a diagonal line through the block"
--
-- The spatial information (WHERE the boundary is, HOW the groups
-- connect) is exactly what error diffusion needs.
-- ════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
-- § 7. MAIN — self-test with synthetic block
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " TesseractGo: 19×19 Color Blocks as Go Positions"
  putStrLn " 3D sRGB → 3 pairwise boards → territory analysis"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Synthetic 19×19 block: face-like (red-dominant center, varied edges)
  let block = [ let x = fromIntegral (i `mod` boardSize) / 18.0
                    y = fromIntegral (i `div` boardSize) / 18.0
                    -- Center: warm skin tone (R high, G/B low)
                    -- Edges: varied (hair, background)
                    cx = abs (x - 0.5); cy = abs (y - 0.5)
                    dist = sqrt (cx*cx + cy*cy)
                    r = 0.75 - dist * 0.4 + sin (x * 7) * 0.05
                    g = 0.35 - dist * 0.2 + cos (y * 5) * 0.08
                    b = 0.20 + dist * 0.3 + sin (x * 3 + y * 4) * 0.06
                in (max 0 (min 1 r), max 0 (min 1 g), max 0 (min 1 b))
              | i <- [0 .. boardSize * boardSize - 1] ]

  let boards = blockToBoards block
      eval = evaluateBlock boards

  putStrLn "  ── R/G Board (Red vs Green) ──"
  printBoard (rgBoard boards)
  let erg = beRG eval
  putStrLn $ "  Territory: Black(R)=" ++ show (tBlack (territory erg))
          ++ " White(G)=" ++ show (tWhite (territory erg))
          ++ " Empty=" ++ show (tEmpty (territory erg))
  putStrLn $ "  Score: " ++ showF (tScore (territory erg)) ++ " (>0 = R dominates)"
  putStrLn $ "  Liberties: R=" ++ show (libertyB erg) ++ " G=" ++ show (libertyW erg)
  putStrLn $ "  Groups: R=" ++ show (groupsB erg) ++ " G=" ++ show (groupsW erg)
  putStrLn $ "  Complexity: " ++ showF (complexity erg)
  putStrLn ""

  putStrLn "  ── G/B Board (Green vs Blue) ──"
  printBoard (gbBoard boards)
  let egb = beGB eval
  putStrLn $ "  Territory: Black(G)=" ++ show (tBlack (territory egb))
          ++ " White(B)=" ++ show (tWhite (territory egb))
          ++ " Empty=" ++ show (tEmpty (territory egb))
  putStrLn $ "  Liberties: G=" ++ show (libertyB egb) ++ " B=" ++ show (libertyW egb)
  putStrLn $ "  Complexity: " ++ showF (complexity egb)
  putStrLn ""

  putStrLn "  ── B/R Board (Blue vs Red) ──"
  printBoard (brBoard boards)
  let ebr = beBR eval
  putStrLn $ "  Territory: Black(B)=" ++ show (tBlack (territory ebr))
          ++ " White(R)=" ++ show (tWhite (territory ebr))
          ++ " Empty=" ++ show (tEmpty (territory ebr))
  putStrLn $ "  Liberties: B=" ++ show (libertyB ebr) ++ " R=" ++ show (libertyW ebr)
  putStrLn $ "  Complexity: " ++ showF (complexity ebr)
  putStrLn ""

  putStrLn "  ── Block Summary ──"
  putStrLn $ "  Overall complexity: " ++ showF (beComplexity eval)
  putStrLn $ "  Total dither budget: " ++ show (beDitherBudget eval) ++ " liberties"
  putStrLn ""

  -- What this means for quantization:
  let ditherAdvice
        | beComplexity eval > 0.4 = "RICH: Many boundaries → strong dithering opportunity"
        | beComplexity eval > 0.2 = "MODERATE: Some structure → selective dithering"
        | otherwise               = "MONOCHROMATIC: Dominated by one color → little to dither"
  putStrLn $ "  Quantization advice: " ++ ditherAdvice
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Go concept          → Tesseract concept"
  putStrLn " Territory           → histogram bin counts"
  putStrLn " Liberties           → dithering candidates"
  putStrLn " Connected groups    → visual features"
  putStrLn " Game complexity     → color diversity potential"
  putStrLn " Score               → channel balance"
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

printBoard :: Board -> IO ()
printBoard board = do
  putStr "    "
  mapM_ (\y -> do
    putStr "  "
    mapM_ (\x -> putStr [stoneChar (board ! (x, y))]) [0..boardSize-1]
    putStrLn ""
    putStr "  "
    ) [0..boardSize-1]
  putStrLn ""

stoneChar :: Stone -> Char
stoneChar Black = '●'  -- channel A dominates
stoneChar White = '○'  -- channel B dominates
stoneChar Empty = '·'  -- boundary

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 1000) :: Int) / 1000.0 :: Double)
          in take 6 (s ++ repeat '0')
