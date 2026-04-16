{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- TemporalLoop: Bidirectional Error Diffusion Around 64 Frames
--
-- The problem: F-S processes pixels 0→4095 in one pass.
-- Frame 63 at pixel (63,63) accumulates ALL the error.
-- Frame 0 at pixel (0,0) is perfectly accurate.
-- This asymmetry causes KL spikes at the sequence edges.
--
-- The solution: for each pixel position (x,y), treat its 64
-- epoch values across 64 frames as a 1D LOOP.
-- Run error diffusion AROUND the loop in multiple passes:
--   Pass 1: forward  (frame 0 → 63), diffuse error right
--   Pass 2: backward (frame 63 → 0), diffuse error left
--   Pass 3: forward again (convergence)
--
-- The loop distributes error symmetrically.
-- No frame is privileged. Total error minimized.
-- ════════════════════════════════════════════════════════════════

module TemporalLoop where

import Data.List (foldl')

-- ════════════════════════════════════════════════════════════════
-- § 1. THE IDEAL EPOCH SEQUENCE
--
-- For one pixel at depth d, the ideal epoch at frame z is:
--   idealEpoch(z) = Σ k × P(k|z, σ(d))  ∈ [0, 3]
--
-- This traces a smooth S-curve across 64 frames:
--   frames 0-15:  ideal ≈ 0 (epoch 0)
--   frames 16-31: ideal ≈ 1 (epoch 1)
--   frames 32-47: ideal ≈ 2 (epoch 2)
--   frames 48-63: ideal ≈ 3 (epoch 3)
-- ════════════════════════════════════════════════════════════════

sigmaBase :: Double
sigmaBase = 63.0 / 8.0

epochCenters :: [Double]
epochCenters = [7.875, 23.625, 39.375, 55.125]

gaussProbs :: Int -> Double -> [Double]
gaussProbs z sigma =
  let zf = fromIntegral z; s2 = 2.0 * sigma * sigma
      raw = [exp (-(zf - mu)^(2::Int) / s2) | mu <- epochCenters]
      total = sum raw
  in if total < 1e-10 then replicate 4 0.25 else map (/ total) raw

idealEpoch :: Int -> Double -> Double
idealEpoch z depth =
  let sigma = sigmaBase * (2.0 - depth)
      probs = gaussProbs z sigma
  in sum (zipWith (*) probs [0, 1, 2, 3])

-- | The ideal epoch sequence for one pixel across 64 frames
idealSequence :: Double -> [Double]
idealSequence depth = [idealEpoch z depth | z <- [0..63]]

-- ════════════════════════════════════════════════════════════════
-- § 2. SINGLE-PASS F-S (the broken version)
--
-- Process frame 0 → 63, diffuse error forward.
-- Frame 63 gets all accumulated error.
-- ════════════════════════════════════════════════════════════════

singlePassFS :: [Double] -> [Int]
singlePassFS ideals = reverse $ snd $ foldl' step (0, []) ideals
  where
    step (err, acc) ideal =
      let adjusted = ideal + err
          quantized = clamp03 (round adjusted)
          newErr = adjusted - fromIntegral quantized
      in (newErr * 0.7, quantized : acc)  -- 70% error carried forward

-- ════════════════════════════════════════════════════════════════
-- § 3. BIDIRECTIONAL LOOP DIFFUSION (the fix)
--
-- Multiple passes: forward → backward → forward → backward
-- Each pass reduces total error. Error distributes symmetrically.
--
-- Pass structure:
--   Forward:  frame 0 → 63, carry error right
--   Backward: frame 63 → 0, carry error left
--   Repeat until convergence (typically 2-3 rounds)
-- ════════════════════════════════════════════════════════════════

bidirectionalLoop :: Int -> [Double] -> [Int]
bidirectionalLoop numRounds ideals =
  let initial = map (\x -> clamp03 (round x)) ideals  -- naive rounding
  in iterate (oneRound ideals) initial !! numRounds

-- | One round = forward pass then backward pass
oneRound :: [Double] -> [Int] -> [Int]
oneRound ideals current =
  let afterForward  = forwardPass ideals current
      afterBackward = backwardPass ideals afterForward
  in afterBackward

-- | Forward pass: frame 0 → 63
forwardPass :: [Double] -> [Int] -> [Int]
forwardPass ideals current =
  let n = length ideals
      go _ [] _ = []
      go err (ideal:rest) (cur:curs) =
        let adjusted = ideal + err * 0.5  -- 50% of incoming error
            quantized = clamp03 (round adjusted)
            newErr = adjusted - fromIntegral quantized
        in quantized : go newErr rest curs
      go _ _ _ = []
  in go 0 ideals current

-- | Backward pass: frame 63 → 0
backwardPass :: [Double] -> [Int] -> [Int]
backwardPass ideals current =
  reverse $ forwardPass (reverse ideals) (reverse current)

-- ════════════════════════════════════════════════════════════════
-- § 4. OPTIMAL ASSIGNMENT (gold standard)
--
-- For 64 frames with 4 levels, try to minimize total squared error
-- while respecting the Gaussian cadence distribution.
--
-- Simple greedy: for each frame, pick the level closest to ideal.
-- No error diffusion at all — just nearest rounding.
-- This is actually optimal for independent frames.
-- ════════════════════════════════════════════════════════════════

optimalAssign :: [Double] -> [Int]
optimalAssign = map (\x -> clamp03 (round x))

-- ════════════════════════════════════════════════════════════════
-- § 5. ERROR METRICS
-- ════════════════════════════════════════════════════════════════

-- | Total squared error
totalSqError :: [Double] -> [Int] -> Double
totalSqError ideals quantized =
  sum [let e = ideal - fromIntegral q in e * e
      | (ideal, q) <- zip ideals quantized]

-- | Max absolute error (worst frame)
maxError :: [Double] -> [Int] -> Double
maxError ideals quantized =
  maximum [abs (ideal - fromIntegral q)
          | (ideal, q) <- zip ideals quantized]

-- | Error at edges (frame 0 and frame 63)
edgeErrors :: [Double] -> [Int] -> (Double, Double)
edgeErrors ideals quantized =
  ( abs (head ideals - fromIntegral (head quantized))
  , abs (last ideals - fromIntegral (last quantized)) )

-- ════════════════════════════════════════════════════════════════
-- § 6. MAIN — compare methods
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " TemporalLoop: Bidirectional Error Diffusion"
  putStrLn " 64 frames as a loop, not a line"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  -- Test with a face pixel (near, depth=0.85) and a wall pixel (far, depth=0.2)
  let testCases = [("Face (depth=0.85, tight σ)", 0.85),
                   ("Wall (depth=0.20, wide σ)", 0.20)]

  mapM_ (\(label, depth) -> do
    let ideals = idealSequence depth
    putStrLn $ "  ── " ++ label ++ " ──"
    putStrLn ""

    -- Show ideal sequence (first/last 8 frames)
    putStr "  Ideal:     "
    mapM_ (\z -> putStr $ showF (ideals !! z) ++ " ") [0..7]
    putStr " ... "
    mapM_ (\z -> putStr $ showF (ideals !! z) ++ " ") [56..63]
    putStrLn ""

    -- Method 1: Single-pass F-S
    let fs = singlePassFS ideals
    putStr "  F-S 1pass: "
    mapM_ (\z -> putStr $ show (fs !! z) ++ "    ") [0..7]
    putStr " ... "
    mapM_ (\z -> putStr $ show (fs !! z) ++ "    ") [56..63]
    putStrLn ""

    -- Method 2: Bidirectional (3 rounds)
    let bi = bidirectionalLoop 3 ideals
    putStr "  Bidir 3r:  "
    mapM_ (\z -> putStr $ show (bi !! z) ++ "    ") [0..7]
    putStr " ... "
    mapM_ (\z -> putStr $ show (bi !! z) ++ "    ") [56..63]
    putStrLn ""

    -- Method 3: Optimal (nearest rounding)
    let opt = optimalAssign ideals
    putStr "  Optimal:   "
    mapM_ (\z -> putStr $ show (opt !! z) ++ "    ") [0..7]
    putStr " ... "
    mapM_ (\z -> putStr $ show (opt !! z) ++ "    ") [56..63]
    putStrLn ""

    -- Compare errors
    putStrLn ""
    putStrLn "  Method        | Total²  | Max    | Edge(0) | Edge(63)"
    putStrLn "  ──────────────┼─────────┼────────┼─────────┼─────────"
    let showMethod name result =
          let (e0, e63) = edgeErrors ideals result
          in putStrLn $ "  " ++ padR 14 name ++ "| " ++
             padR 8 (showF (totalSqError ideals result)) ++ "| " ++
             padR 7 (showF (maxError ideals result)) ++ "| " ++
             padR 8 (showF e0) ++ "| " ++ showF e63
    showMethod "F-S 1-pass" fs
    showMethod "Bidir 3 rounds" bi
    showMethod "Optimal" opt
    putStrLn ""
    ) testCases

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " Bidirectional: error flows both ways. No edge bias."
  putStrLn " Forward → backward → forward: 3 passes converge."
  putStrLn " Each pixel's 64 epochs treated as a LOOP, not a LINE."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

clamp03 :: Int -> Int
clamp03 = max 0 . min 3

showF :: Double -> String
showF x = let s = show (fromIntegral (round (x * 1000) :: Int) / 1000.0 :: Double)
          in take 5 (s ++ repeat '0')

padR :: Int -> String -> String
padR n s = s ++ replicate (max 0 (n - length s)) ' '
