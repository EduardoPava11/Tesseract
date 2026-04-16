{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- TeacherStudent: The Training Contract
--
-- Teacher = PerfectQuantizer (algebraic, proven by Haskell)
-- Student = Para NN (inferDepth → same algebraic pipeline)
--
-- The loss decomposes along DirectSum R1 ⊕ R3 = R4:
--   R3 (color): FROZEN — ditherColors handles this. Loss = 0.
--   R1 (epoch): LEARNED — the NN infers depth, which drives
--               epoch assignment via the SAME gaussianProbs formula.
--
-- TS1: If virtual depth = real depth, student = teacher.
--      (By construction — same pipeline.)
-- TS2: Loss lives entirely in R1.
-- TS3: Training data = N³ per GIF cube.
-- TS4: Palette is {0..255} at ALL cube sizes — loss is comparable.
-- ════════════════════════════════════════════════════════════════

module TeacherStudent where

import Data.List (sortBy, foldl')
import Data.Ord (comparing, Down(..))
import qualified Data.Map.Strict as Map

-- ════════════════════════════════════════════════════════════════
-- § 1. TYPES (inlined for self-containment)
-- ════════════════════════════════════════════════════════════════

data ColorPos = ColorPos
  { cpR :: !Double, cpG :: !Double, cpB :: !Double
  } deriving (Show, Eq)

newtype Depth = Depth { unDepth :: Double }
  deriving (Show, Eq, Ord)

newtype CubeSize = CubeSize { unCubeSize :: Int }
  deriving (Show, Eq)

newtype Frame = Frame { unFrame :: Int }
  deriving (Show, Eq)

-- | A pixel with all context needed for quantization
data Pixel = Pixel
  { pxIndex :: !Int
  , pxColor :: !ColorPos
  , pxDepth :: !Double   -- real depth [0,1]
  } deriving (Show)

-- ════════════════════════════════════════════════════════════════
-- § 2. CADENCE (from ScaleInvariant.hs)
-- ════════════════════════════════════════════════════════════════

sigmaBase :: CubeSize -> Double
sigmaBase (CubeSize n) = fromIntegral (n - 1) / 8.0

epochCenters :: CubeSize -> [Double]
epochCenters cs = [(2.0 * fromIntegral d + 1.0) * sigmaBase cs | d <- [0..3]]

sigmaForDepth :: CubeSize -> Double -> Double
sigmaForDepth cs d = sigmaBase cs * (2.0 - d)

gaussianProbs :: CubeSize -> Int -> Double -> [Double]
gaussianProbs cs z sigma =
  let zf = fromIntegral z
      s2 = 2.0 * sigma * sigma
      raw = [exp (-(zf - mu)**2 / s2) | mu <- epochCenters cs]
      total = sum raw
  in if total < 1e-10
     then [0.25, 0.25, 0.25, 0.25]
     else map (/ total) raw

dominantEpoch :: CubeSize -> Int -> Double -> Int
dominantEpoch cs z depth =
  let probs = gaussianProbs cs z (sigmaForDepth cs depth)
  in snd $ maximum (zip probs [0..3])

-- ════════════════════════════════════════════════════════════════
-- § 3. QUANTIZATION (from PerfectQuantize.hs / TesseractQuantize.hs)
-- ════════════════════════════════════════════════════════════════

clamp03 :: Int -> Int
clamp03 = max 0 . min 3

-- | Floor-quantize a single pixel's color
quantizeColor :: ColorPos -> (Int, Int, Int)
quantizeColor (ColorPos r g b) =
  (clamp03 (floor (r * 4.0)), clamp03 (floor (g * 4.0)), clamp03 (floor (b * 4.0)))

-- | Display key: a×16 + b×4 + c
displayKey :: (Int, Int, Int) -> Int
displayKey (a, b, c) = a * 16 + b * 4 + c

-- | Palette index: d×64 + a×16 + b×4 + c
paletteIndex :: Int -> (Int, Int, Int) -> Int
paletteIndex epoch (a, b, c) = epoch * 64 + a * 16 + b * 4 + c

-- | Largest remainder method
largestRemainder :: Int -> [Double] -> [Int]
largestRemainder total weights =
  let ideal = map (* fromIntegral total) weights
      floored = map floor ideal
      remainders = zipWith (-) ideal (map fromIntegral floored)
      deficit = total - sum floored
      indexed = zip [0..] remainders
      sorted = sortBy (flip $ comparing snd) indexed
      winners = map fst (take deficit sorted)
      adjust i = if i `elem` winners then 1 else 0
  in zipWith (+) floored (map adjust [0..length weights - 1])

-- ════════════════════════════════════════════════════════════════
-- § 4. TEACHER — the algebraic pipeline with real depth
-- ════════════════════════════════════════════════════════════════

-- | Teacher: assign palette indices using REAL depth.
--   This is perfectFrame from PerfectQuantize.hs, parameterized by CubeSize.
teacherAssign :: CubeSize -> Int -> [Pixel] -> [Int]
teacherAssign cs z pixels =
  let n = length pixels
      -- Step 1: floor-quantize colors
      colored = [ (pxIndex px, quantizeColor (pxColor px), pxDepth px)
                | px <- pixels ]

      -- Step 2: group by display color
      groups = Map.fromListWith (++)
        [ (displayKey abc, [(idx, abc, depth)])
        | (idx, abc, depth) <- colored ]

      -- Step 3: per-group epoch assignment
      assignments = concatMap (assignGroup cs z) (Map.elems groups)

      -- Build result
      result = foldl' (\arr (idx, val) -> setAt arr idx val)
                 (replicate n 0) assignments
  in result

assignGroup :: CubeSize -> Int -> [(Int, (Int,Int,Int), Double)] -> [(Int, Int)]
assignGroup cs z group =
  let abc = let (_,c,_) = head group in c
      groupN = length group
      avgDepth = sum [d | (_,_,d) <- group] / fromIntegral groupN
      sigma = sigmaForDepth cs avgDepth
      probs = gaussianProbs cs z sigma
      targets = largestRemainder groupN probs
      sorted = sortBy (flip $ comparing (\(_,_,d) -> d)) group
      epochOrder = sortBy (flip $ comparing (targets !!)) [0..3]

      assign [] _ = []
      assign _ [] = []
      assign remaining ((epoch, count):rest) =
        let (batch, leftover) = splitAt count remaining
        in [ (idx, paletteIndex epoch abc) | (idx, abc, _) <- batch ]
           ++ assign leftover rest
  in assign sorted (zip epochOrder (map (targets !!) epochOrder))

-- ════════════════════════════════════════════════════════════════
-- § 5. STUDENT — NN-inferred depth → same pipeline
-- ════════════════════════════════════════════════════════════════

-- | Student: replace real depth with virtual depth, run SAME pipeline.
--   virtualDepths is what the NN would produce — one per pixel.
studentAssign :: CubeSize -> Int -> [Pixel] -> [Double] -> [Int]
studentAssign cs z pixels virtualDepths =
  let -- Replace depth with NN output, keep everything else
      virtualPixels = [ Pixel (pxIndex px) (pxColor px) vd
                      | (px, vd) <- zip pixels virtualDepths ]
  in teacherAssign cs z virtualPixels

-- ════════════════════════════════════════════════════════════════
-- § 6. LOSS FUNCTIONS
-- ════════════════════════════════════════════════════════════════

-- | Epoch loss: per-pixel epoch agreement between teacher and student.
--   Fraction of pixels where the epoch differs.
epochLoss :: [Int] -> [Int] -> Double
epochLoss teacherIndices studentIndices =
  let pairs = zip teacherIndices studentIndices
      n = length pairs
      -- Extract epoch: index `div` 64
      mismatches = length [ () | (t, s) <- pairs, t `div` 64 /= s `div` 64 ]
  in fromIntegral mismatches / fromIntegral n

-- | Full index loss: fraction of pixels with different palette index.
--   Includes both color and epoch disagreement.
indexLoss :: [Int] -> [Int] -> Double
indexLoss teacherIndices studentIndices =
  let pairs = zip teacherIndices studentIndices
      n = length pairs
      mismatches = length [ () | (t, s) <- pairs, t /= s ]
  in fromIntegral mismatches / fromIntegral n

-- | Depth MSE: average squared error between real and virtual depth.
depthMSE :: [Double] -> [Double] -> Double
depthMSE real virtual =
  let n = length real
      se = sum [ (r - v)^(2::Int) | (r, v) <- zip real virtual ]
  in se / fromIntegral n

-- | Combined loss: epoch loss + λ × depth MSE
--   epoch loss lives in R1 (temporal axis)
--   depth MSE is the auxiliary interpretability regularizer
totalLoss :: Double -> [Int] -> [Int] -> [Double] -> [Double] -> Double
totalLoss lambda teacherIdx studentIdx realDepth virtualDepth =
  epochLoss teacherIdx studentIdx + lambda * depthMSE realDepth virtualDepth

-- ════════════════════════════════════════════════════════════════
-- § 7. TRAINING DATA VOLUME
-- ════════════════════════════════════════════════════════════════

-- | Samples per GIF cube at each size
samplesPerCube :: CubeSize -> Int
samplesPerCube (CubeSize n) = n * n * n

-- | Samples per frame
samplesPerFrame :: CubeSize -> Int
samplesPerFrame (CubeSize n) = n * n

-- ════════════════════════════════════════════════════════════════
-- § 8. SYNTHETIC TEST
-- ════════════════════════════════════════════════════════════════

-- | Synthetic scene: center=near, edges=far
syntheticPixels :: Int -> [Pixel]
syntheticPixels n =
  [ Pixel i
      (ColorPos (fromIntegral x / fromIntegral (n-1))
                (fromIntegral y / fromIntegral (n-1))
                0.5)
      (syntheticDepth n x y)
  | i <- [0..n*n-1]
  , let x = i `mod` n
        y = i `div` n
  ]

syntheticDepth :: Int -> Int -> Int -> Double
syntheticDepth n x y =
  let cx = abs (fromIntegral x - fromIntegral (n-1) / 2.0) / (fromIntegral (n-1) / 2.0)
      cy = abs (fromIntegral y - fromIntegral (n-1) / 2.0) / (fromIntegral (n-1) / 2.0)
  in 1.0 - sqrt (cx*cx + cy*cy) / sqrt 2.0

-- ════════════════════════════════════════════════════════════════
-- § 9. AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-10

-- (TS1) If virtual depth = real depth for all pixels, student = teacher.
--   This is the convergence theorem: the SAME pipeline produces the
--   SAME output given the SAME depth input.
axiom_TS1 :: Bool
axiom_TS1 = all checkFrame [0, 8, 16, 24, 32, 40, 48, 56, 63]
  where
    cs = CubeSize 64
    pixels = syntheticPixels 64
    checkFrame z =
      let realDepths = map pxDepth pixels
          teacherOut = teacherAssign cs z pixels
          studentOut = studentAssign cs z pixels realDepths  -- virtual = real
      in teacherOut == studentOut

-- (TS2) Loss decomposes along DirectSum:
--   Color loss is ZERO when the same RGB input is used.
--   Only epoch (R1) can differ between teacher and student.
axiom_TS2 :: Bool
axiom_TS2 = all checkFrame [0, 16, 32, 48]
  where
    cs = CubeSize 64
    pixels = syntheticPixels 64
    checkFrame z =
      let teacherOut = teacherAssign cs z pixels
          -- Student with perturbed depth (shifts epochs, not colors)
          perturbedDepths = [max 0 (min 1 (pxDepth px + 0.1)) | px <- pixels]
          studentOut = studentAssign cs z pixels perturbedDepths
          -- Check: color (a,b,c) is the SAME, only epoch (d) can differ
          colorMatch = all (\(t, s) -> t `mod` 64 == s `mod` 64)
                         (zip teacherOut studentOut)
      in colorMatch

-- (TS3) Training data volume = N² per frame, N³ per cube
axiom_TS3 :: Bool
axiom_TS3 =
     samplesPerFrame (CubeSize 64)  == 4096
  && samplesPerFrame (CubeSize 128) == 16384
  && samplesPerFrame (CubeSize 256) == 65536
  && samplesPerCube (CubeSize 64)   == 262144
  && samplesPerCube (CubeSize 128)  == 2097152
  && samplesPerCube (CubeSize 256)  == 16777216

-- (TS4) Palette is {0..255} at ALL cube sizes
axiom_TS4 :: Bool
axiom_TS4 = all checkSize [CubeSize 64, CubeSize 128, CubeSize 256]
  where
    checkSize cs =
      let n = min 64 (unCubeSize cs)  -- test at 64×64 field for speed
          pixels = syntheticPixels n
          indices = teacherAssign cs 0 pixels
      in all (\i -> i >= 0 && i <= 255) indices

-- (TS5) Perfect depth → zero loss (corollary of TS1)
axiom_TS5 :: Bool
axiom_TS5 =
  let cs = CubeSize 64
      pixels = syntheticPixels 64
      realDepths = map pxDepth pixels
      z = 16
      teacherOut = teacherAssign cs z pixels
      studentOut = studentAssign cs z pixels realDepths
      eLoss = epochLoss teacherOut studentOut
      dLoss = depthMSE realDepths realDepths
      tLoss = totalLoss 0.1 teacherOut studentOut realDepths realDepths
  in abs eLoss < eps && abs dLoss < eps && abs tLoss < eps

-- (TS6) Perturbed depth → nonzero epoch loss, zero color loss
axiom_TS6 :: Bool
axiom_TS6 =
  let cs = CubeSize 64
      pixels = syntheticPixels 64
      z = 16  -- epoch crossover — most sensitive to depth perturbation
      teacherOut = teacherAssign cs z pixels
      -- Flip depth: near→far, far→near
      flippedDepths = [1.0 - pxDepth px | px <- pixels]
      studentOut = studentAssign cs z pixels flippedDepths
      eLoss = epochLoss teacherOut studentOut
      -- Color loss should be zero (depth doesn't affect floor quantization)
      colorLoss = fromIntegral (length [ () | (t, s) <- zip teacherOut studentOut
                                            , t `mod` 64 /= s `mod` 64 ])
                / fromIntegral (length teacherOut)
  in eLoss > 0.0     -- epochs MUST differ (depth is flipped)
  && colorLoss < eps  -- colors MUST match (depth doesn't affect color)

-- ════════════════════════════════════════════════════════════════
-- § 10. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " TeacherStudent: The Training Contract"
  putStrLn " Teacher = PerfectQuantizer.  Student = Para NN."
  putStrLn " Same pipeline. Different depth source."
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  let cs = CubeSize 64
      pixels = syntheticPixels 64
      realDepths = map pxDepth pixels

  -- Teacher output at key frames
  putStrLn "── Teacher Output (algebraic, real depth) ──"
  putStrLn ""
  putStrLn "  frame │ epochs [ep0 ep1 ep2 ep3] │ palette entries used"
  putStrLn "  ──────┼──────────────────────────┼─────────────────────"
  mapM_ (\z -> do
    let indices = teacherAssign cs z pixels
        epochCounts = [ length [i | i <- indices, i `div` 64 == d] | d <- [0..3] ]
        used = Map.size $ Map.fromListWith (+) [(i, 1::Int) | i <- indices]
    putStrLn $ "  " ++ padL 5 (show z)
            ++ " │ " ++ show epochCounts
            ++ replicate (26 - length (show epochCounts)) ' '
            ++ "│ " ++ show used ++ " / 256"
    ) [0, 8, 16, 24, 32, 48, 63]
  putStrLn ""

  -- Student = Teacher when depth is perfect
  putStrLn "── Student = Teacher (virtual depth = real depth) ──"
  putStrLn ""
  putStrLn "  frame │ epoch loss │ index loss │ depth MSE"
  putStrLn "  ──────┼────────────┼────────────┼──────────"
  mapM_ (\z -> do
    let teacherOut = teacherAssign cs z pixels
        studentOut = studentAssign cs z pixels realDepths
        eLoss = epochLoss teacherOut studentOut
        iLoss = indexLoss teacherOut studentOut
        dLoss = depthMSE realDepths realDepths
    putStrLn $ "  " ++ padL 5 (show z)
            ++ " │ " ++ padL 10 (showF eLoss)
            ++ " │ " ++ padL 10 (showF iLoss)
            ++ " │ " ++ showF dLoss
    ) [0, 8, 16, 32, 48, 63]
  putStrLn ""

  -- Student with perturbed depth
  putStrLn "── Student with Perturbed Depth ──"
  putStrLn ""
  putStrLn "  perturbation │ frame 16 epoch loss │ color loss"
  putStrLn "  ─────────────┼──────────────────────┼───────────"
  mapM_ (\delta -> do
    let z = 16
        pertDepths = [max 0 (min 1 (pxDepth px + delta)) | px <- pixels]
        teacherOut = teacherAssign cs z pixels
        studentOut = studentAssign cs z pixels pertDepths
        eLoss = epochLoss teacherOut studentOut
        cLoss = fromIntegral (length [() | (t,s) <- zip teacherOut studentOut
                                         , t `mod` 64 /= s `mod` 64])
              / fromIntegral (length teacherOut)
    putStrLn $ "  " ++ padL 13 (showSigned delta)
            ++ " │ " ++ padL 20 (showF eLoss)
            ++ " │ " ++ showF cLoss
    ) [0.0, 0.05, 0.1, 0.2, 0.5, -0.5]
  putStrLn ""

  -- Training data volume
  putStrLn "── Training Data Volume ──"
  putStrLn ""
  putStrLn "  cube size │ per frame │ per cube (64 frames)"
  putStrLn "  ──────────┼───────────┼─────────────────────"
  mapM_ (\cs' -> do
    putStrLn $ "  " ++ padL 9 (show (unCubeSize cs') ++ "³")
            ++ " │ " ++ padL 9 (commas (samplesPerFrame cs'))
            ++ " │ " ++ commas (samplesPerCube cs')
    ) [CubeSize 64, CubeSize 128, CubeSize 256]
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "TS1 virtual=real depth → student=teacher"              [axiom_TS1]
  check "TS2 loss decomposes: color unchanged, only epoch"      [axiom_TS2]
  check "TS3 training data: N² per frame, N³ per cube"          [axiom_TS3]
  check "TS4 palette {0..255} at all cube sizes"                [axiom_TS4]
  check "TS5 perfect depth → zero loss"                         [axiom_TS5]
  check "TS6 perturbed depth → epoch loss > 0, color loss = 0"  [axiom_TS6]
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " THE CONTRACT"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  Teacher: algebraic pipeline + real depth (proven correct)"
  putStrLn "  Student: same pipeline + NN-inferred depth (learned)"
  putStrLn ""
  putStrLn "  The NN learns depth. The pipeline does the rest."
  putStrLn "  Loss lives in R1 (epoch). R3 (color) is frozen."
  putStrLn "  If depth converges, epochs converge."
  putStrLn "  If epochs converge, palette indices converge."
  putStrLn ""
  putStrLn "  DirectSum R1 ⊕ R3 = R4.  4⁴ = 256.  Always."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 10000) :: Int) / 10000.0 :: Double)
          in take 8 (s ++ repeat '0')

showSigned :: Double -> String
showSigned x
  | x >= 0    = "+" ++ showF x
  | otherwise = showF x

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

commas :: Int -> String
commas n
  | n < 1000  = show n
  | otherwise = commas (n `div` 1000) ++ "," ++ padWith '0' 3 (show (n `mod` 1000))
  where padWith c w s = replicate (max 0 (w - length s)) c ++ s

setAt :: [a] -> Int -> a -> [a]
setAt xs i v = take i xs ++ [v] ++ drop (i + 1) xs

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
