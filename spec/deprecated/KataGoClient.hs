{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- KataGoClient: Send color-comparison Go boards to KataGo
--
-- Converts a 19×19 block's channel-pair comparison to a Go position,
-- sends it to KataGo via GTP, and parses the territory response.
--
-- Usage:
--   ./katago-client                    -- test with synthetic block
--   ./katago-client --board "BBW..."   -- send specific 361-char board
-- ════════════════════════════════════════════════════════════════

module KataGoClient where

import System.Process
import System.IO
import Data.Char (toLower)
import Data.List (intercalate)
import Data.Array
import Control.Exception (bracket)

-- ════════════════════════════════════════════════════════════════
-- § 1. TYPES (from TesseractGo.hs)
-- ════════════════════════════════════════════════════════════════

data Stone = Black | White | Empty deriving (Show, Eq, Ord)

type Board = Array (Int, Int) Stone

boardSize :: Int
boardSize = 19

-- | KataGo territory ownership result
data KataGoTerritory = KataGoTerritory
  { ktOwnership :: ![(Int, Int, Double)]  -- (x, y, ownership [-1,1])
  , ktBlackOwn  :: !Int                    -- positions owned by Black
  , ktWhiteOwn  :: !Int                    -- positions owned by White
  , ktNeutral   :: !Int                    -- contested positions
  , ktScore     :: !Double                 -- Black advantage
  } deriving (Show)

-- ════════════════════════════════════════════════════════════════
-- § 2. BOARD → GTP COMMANDS
-- ════════════════════════════════════════════════════════════════

-- | Convert (x,y) to GTP coordinate (A1-T19, skipping I)
toGTP :: (Int, Int) -> String
toGTP (x, y) =
  let col = if x >= 8 then toEnum (x + 66) else toEnum (x + 65)  -- skip 'I'
      row = y + 1
  in [col] ++ show row

-- | Generate GTP commands to set up a board position
boardToGTP :: Board -> [String]
boardToGTP board =
  [ "boardsize 19"
  , "clear_board"
  ] ++
  [ "play " ++ color ++ " " ++ toGTP (x, y)
  | y <- [0..boardSize-1]
  , x <- [0..boardSize-1]
  , let s = board ! (x, y)
  , s /= Empty
  , let color = case s of Black -> "B"; White -> "W"; _ -> ""
  ]

-- | Request territory analysis from KataGo
analysisCommand :: String
analysisCommand = "kata-analyze interval 100 maxmoves 0 ownership true"

-- ════════════════════════════════════════════════════════════════
-- § 3. RUN KATAGO (GTP subprocess)
-- ════════════════════════════════════════════════════════════════

-- | Path to KataGo binary and model
kataGoBin :: String
kataGoBin = "katago"

kataGoModel :: String
kataGoModel = "/Users/danielmosquera/.homebrew/opt/katago/share/katago/g170e-b20c256x2-s5303129600-d1228401921.bin.gz"

kataGoConfig :: String
kataGoConfig = "/Users/danielmosquera/.homebrew/opt/katago/share/katago/configs/gtp_example.cfg"

-- | Send a board to KataGo and get ownership back
evaluateBoard :: Board -> IO (Maybe String)
evaluateBoard board = do
  let commands = boardToGTP board
               ++ [analysisCommand]
               ++ ["quit"]
      input = unlines commands

  let proc = (System.Process.proc kataGoBin
        ["gtp", "-model", kataGoModel, "-config", kataGoConfig])
        { std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe }

  bracket (createProcess proc) cleanup $ \(Just hIn, Just hOut, Just hErr, ph) -> do
    hSetBuffering hIn LineBuffering
    hSetBuffering hOut LineBuffering

    -- Send all commands
    hPutStr hIn input
    hFlush hIn

    -- Read response (wait for ownership data or quit)
    output <- hGetContents hOut
    let outputLines = lines output
    return (Just (unlines (take 50 outputLines)))

  where
    cleanup (Just hIn, Just hOut, Just hErr, ph) = do
      hClose hIn
      hClose hOut
      hClose hErr
      terminateProcess ph
    cleanup _ = return ()

-- ════════════════════════════════════════════════════════════════
-- § 4. SYNTHETIC BOARD FOR TESTING
-- ════════════════════════════════════════════════════════════════

-- | Create a board from a face-like R/G comparison
--   Center: R dominates (Black) — skin
--   Edges: G dominates (White) — background
--   Ring: boundary (Empty) — dithering zone
syntheticRGBoard :: Board
syntheticRGBoard =
  array ((0,0), (18,18))
    [ ((x, y),
        let cx = fromIntegral x - 9.0 :: Double
            cy = fromIntegral y - 9.0
            dist = sqrt (cx*cx + cy*cy)
        in if dist < 5 then Black       -- face center (R > G)
           else if dist < 7 then Empty  -- boundary ring
           else White                    -- background (G > R)
      )
    | y <- [0..18], x <- [0..18] ]

-- | Print a board as ASCII
printBoard :: Board -> IO ()
printBoard board = do
  mapM_ (\y -> do
    putStr "  "
    mapM_ (\x -> putChar (case board ! (x, y) of
      Black -> '#'; White -> 'O'; Empty -> '.')) [0..18]
    putStrLn ""
    ) [0..18]

-- ════════════════════════════════════════════════════════════════
-- § 5. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " KataGoClient: Send color boards to KataGo for evaluation"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  putStrLn "  Synthetic R/G board (face-like):"
  printBoard syntheticRGBoard
  putStrLn ""

  let blackCount = length [() | s <- elems syntheticRGBoard, s == Black]
      whiteCount = length [() | s <- elems syntheticRGBoard, s == White]
      emptyCount = length [() | s <- elems syntheticRGBoard, s == Empty]
  putStrLn $ "  Black (R>G): " ++ show blackCount
  putStrLn $ "  White (G>R): " ++ show whiteCount
  putStrLn $ "  Empty (boundary): " ++ show emptyCount
  putStrLn ""

  putStrLn "  Sending to KataGo (Metal backend)..."
  result <- evaluateBoard syntheticRGBoard
  case result of
    Nothing -> putStrLn "  ERROR: KataGo failed"
    Just output -> do
      putStrLn "  KataGo response (first 50 lines):"
      mapM_ (\l -> putStrLn $ "    " ++ l) (take 30 (lines output))

  putStrLn ""
  putStrLn "════════════════════════════════════════════════════════════"
