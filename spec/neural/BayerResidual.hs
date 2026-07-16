{-# LANGUAGE ScopedTypeVariables #-}

-- ════════════════════════════════════════════════════════════════
-- BayerResidual: The Demosaic Residual Contract (v1)
--
-- Task: RGGB Bayer mosaic (1 channel, [0,1], sRGB-encoded for the
-- prototype) → RGB.
--
-- Teacher = classical bilinear demosaic B(m)   (algebraic, proven)
-- Student = clamp01( B(m) + f_θ(m) )           (tiny residual CNN)
--
-- f_θ constraints: ≤ 8,000 parameters, FP16-friendly, receptive
-- field ≤ 9×9, NO normalization layers, NO attention — it must
-- bake into one Metal kernel.
--
-- Laws:
--   BR0 composition: mosaic ∘ demosaic = id on the mosaic domain.
--   BR1 flat-field identity: constant scene → residual ≈ 0,
--       output = the color (tol 1e-2).
--   BR2 sample passthrough: at each mosaic site, the measured
--       channel of the output stays within tol of the sample.
--   BR3 bounded: output ∈ [0,1] always (hard clamp IS the operator).
--   BR4 exposure equivariance: f(a·m) ≈ a·f(m), a ∈ [0.5,1.0],
--       tol 3e-2. Exact for bias-free convs + ReLU (positively
--       homogeneous); biases / normalization / sigmoid break it.
--   BR5 mighty: held-out PSNR(student) > PSNR(bilinear) + 1.0 dB,
--       else the net is not worth shipping.
--       VERIFIED-BY-TRAINING — a shipping gate, not a spec proof.
--
-- The stand-in f_θ here is a hand-set SAME-PHASE Laplacian:
-- stride-2 neighbors share CFA phase, so BR1 holds by construction.
-- It is linear and bias-free, so BR4 holds exactly. It is NOT
-- trained — BR5 is stated, not proven.
-- ════════════════════════════════════════════════════════════════

module BayerResidual where

-- ════════════════════════════════════════════════════════════════
-- § 1. TYPES (inlined for self-containment)
-- ════════════════════════════════════════════════════════════════

-- | RGB triple in [0,1]³ (sRGB-encoded in the prototype)
data RGB = RGB
  { rgbR :: !Double, rgbG :: !Double, rgbB :: !Double
  } deriving (Show, Eq)

-- | Single-channel RGGB mosaic, n×n, row-major, values in [0,1]
type Mosaic = [Double]

-- | Full-color image, n×n, row-major
type ImageRGB = [RGB]

-- | CFA phase at a site. RGGB:
--   (even y, even x) = R    (even y, odd x) = Gr
--   (odd y,  even x) = Gb   (odd y,  odd x) = B
data CFA = CfaR | CfaGr | CfaGb | CfaB
  deriving (Show, Eq)

cfaAt :: Int -> Int -> CFA
cfaAt x y = case (y `mod` 2, x `mod` 2) of
  (0, 0) -> CfaR
  (0, _) -> CfaGr
  (_, 0) -> CfaGb
  _      -> CfaB

clamp01 :: Double -> Double
clamp01 = max 0.0 . min 1.0

clampRGB :: RGB -> RGB
clampRGB (RGB r g b) = RGB (clamp01 r) (clamp01 g) (clamp01 b)

scaleRGB :: Double -> RGB -> RGB
scaleRGB a (RGB r g b) = RGB (a * r) (a * g) (a * b)

-- | The channel physically measured at a site
measuredChannel :: CFA -> RGB -> Double
measuredChannel CfaR  = rgbR
measuredChannel CfaGr = rgbG
measuredChannel CfaGb = rgbG
measuredChannel CfaB  = rgbB

-- ════════════════════════════════════════════════════════════════
-- § 2. DETERMINISTIC LCG (no System.Random)
-- ════════════════════════════════════════════════════════════════

lcgNext :: Int -> Int
lcgNext s = (1103515245 * s + 12345) `mod` 2147483648

-- | k deterministic doubles in [0,1)
lcgDoubles :: Int -> Int -> [Double]
lcgDoubles seed k =
  take k [ fromIntegral s / 2147483648.0 | s <- tail (iterate lcgNext seed) ]

chunk3 :: [a] -> [[a]]
chunk3 (a:b:c:rest) = [a, b, c] : chunk3 rest
chunk3 _            = []

-- ════════════════════════════════════════════════════════════════
-- § 3. MOSAIC OPERATOR — RGB → RGGB samples
-- ════════════════════════════════════════════════════════════════

mosaic :: Int -> ImageRGB -> Mosaic
mosaic n img =
  [ measuredChannel (cfaAt x y) (img !! i)
  | i <- [0 .. n*n - 1]
  , let x = i `mod` n
        y = i `div` n
  ]

-- | CFA-phase-preserving mirror border: -1 ↦ 1, n ↦ n-2.
--   Parity is kept, the edge pixel is NOT repeated.
--   Clamp-to-edge would mix CFA phases and break BR0/BR1 at borders.
reflectIdx :: Int -> Int -> Int
reflectIdx n i
  | i < 0     = negate i
  | i >= n    = 2 * (n - 1) - i
  | otherwise = i

mAt :: Int -> Mosaic -> Int -> Int -> Double
mAt n m x y = m !! (reflectIdx n y * n + reflectIdx n x)

-- ════════════════════════════════════════════════════════════════
-- § 4. TEACHER — classical bilinear demosaic B(m)
-- ════════════════════════════════════════════════════════════════

-- | Bilinear demosaic. At every site the measured channel is passed
--   through EXACTLY; the two missing channels are neighbor averages
--   over same-color sites only.
bilinearDemosaic :: Int -> Mosaic -> ImageRGB
bilinearDemosaic n m =
  [ demosaicAt x y
  | i <- [0 .. n*n - 1]
  , let x = i `mod` n
        y = i `div` n
  ]
  where
    v = mAt n m
    avg xs = sum xs / fromIntegral (length xs)
    cross x y = avg [v (x-1) y, v (x+1) y, v x (y-1), v x (y+1)]
    diag  x y = avg [v (x-1) (y-1), v (x+1) (y-1), v (x-1) (y+1), v (x+1) (y+1)]
    horiz x y = avg [v (x-1) y, v (x+1) y]
    vert  x y = avg [v x (y-1), v x (y+1)]
    demosaicAt x y = case cfaAt x y of
      CfaR  -> RGB (v x y)     (cross x y) (diag x y)
      CfaGr -> RGB (horiz x y) (v x y)     (vert x y)
      CfaGb -> RGB (vert x y)  (v x y)     (horiz x y)
      CfaB  -> RGB (diag x y)  (cross x y) (v x y)

-- ════════════════════════════════════════════════════════════════
-- § 5. STAND-IN f_θ — hand-set same-phase Laplacian
-- ════════════════════════════════════════════════════════════════

-- | Hand-set per-channel gains (a trained net LEARNS these and more)
data ResidualGains = ResidualGains
  { gainR :: !Double, gainG :: !Double, gainB :: !Double
  } deriving (Show)

standInGains :: ResidualGains
standInGains = ResidualGains 0.02 0.015 0.02

-- | Same-phase Laplacian: stride-2 neighbors share the SAME CFA
--   phase, so a flat field gives EXACTLY zero (BR1 by construction).
--   Receptive field 5×5 ≤ 9×9. Linear, bias-free → BR4 exact.
samePhaseLaplacian :: Int -> Mosaic -> Int -> Int -> Double
samePhaseLaplacian n m x y =
  4 * v x y - v (x-2) y - v (x+2) y - v x (y-2) - v x (y+2)
  where v = mAt n m

residual :: ResidualGains -> Int -> Mosaic -> ImageRGB
residual (ResidualGains gr gg gb) n m =
  [ RGB (gr * l) (gg * l) (gb * l)
  | i <- [0 .. n*n - 1]
  , let x = i `mod` n
        y = i `div` n
        l = samePhaseLaplacian n m x y
  ]

-- ════════════════════════════════════════════════════════════════
-- § 6. STUDENT — out = clamp01( B(m) + f_θ(m) )
-- ════════════════════════════════════════════════════════════════

student :: ResidualGains -> Int -> Mosaic -> ImageRGB
student g n m = zipWith addClamp (bilinearDemosaic n m) (residual g n m)
  where
    addClamp (RGB r1 g1 b1) (RGB r2 g2 b2) =
      clampRGB (RGB (r1 + r2) (g1 + g2) (b1 + b2))

-- ════════════════════════════════════════════════════════════════
-- § 7. PARAMETER BUDGET — the shippable f_θ architecture
-- ════════════════════════════════════════════════════════════════

data ConvSpec = ConvSpec
  { csName :: String
  , csK    :: Int   -- kernel size k×k
  , csIn   :: Int   -- input channels
  , csOut  :: Int   -- output channels
  }

-- | Bias-free (BR4 requires it), so params = out × in × k²
convParams :: ConvSpec -> Int
convParams (ConvSpec _ k ci co) = co * ci * k * k

-- | Reference architecture for the trained f_θ:
--   Conv3×3(1→16) ; ReLU ; Conv3×3(16→16) ; ReLU ; Conv3×3(16→3)
--   Bias-free, no normalization, no attention. One Metal kernel.
referenceArch :: [ConvSpec]
referenceArch =
  [ ConvSpec "Conv1 mosaic→feat" 3  1 16
  , ConvSpec "Conv2 feat→feat"   3 16 16
  , ConvSpec "Conv3 feat→ΔRGB"   3 16  3
  ]

archParams :: [ConvSpec] -> Int
archParams = sum . map convParams

-- | Receptive field of stacked convs: 1 + Σ(k−1)
receptiveField :: [ConvSpec] -> Int
receptiveField specs = 1 + sum [ csK s - 1 | s <- specs ]

-- ════════════════════════════════════════════════════════════════
-- § 8. SYNTHETIC SCENES (deterministic via LCG)
-- ════════════════════════════════════════════════════════════════

fieldN :: Int
fieldN = 24   -- even (CFA-aligned), small enough for runghc

flatScene :: Int -> RGB -> ImageRGB
flatScene n c = replicate (n * n) c

-- | Smooth low-frequency scene in [0.2,0.8]³, LCG-seeded
smoothScene :: Int -> Int -> ImageRGB
smoothScene seed n =
  [ RGB (chan cr x y) (chan cg x y) (chan cb x y)
  | i <- [0 .. n*n - 1]
  , let x = i `mod` n
        y = i `div` n
  ]
  where
    tau = 2.0 * pi
    ds  = lcgDoubles seed 12
    mk us = case us of
      [u1, u2, u3, u4] -> (0.15 * u1, tau * u2, 0.15 * u3, tau * u4)
      _                -> (0.1, 0.0, 0.1, 0.0)
    cr = mk (take 4 ds)
    cg = mk (take 4 (drop 4 ds))
    cb = mk (take 4 (drop 8 ds))
    chan (a1, p1, a2, p2) x y =
      0.5 + a1 * sin (tau * fromIntegral x / fromIntegral n + p1)
          + a2 * cos (tau * fromIntegral y / fromIntegral n + p2)

-- | Worst-case mosaic: independent LCG noise per site
noiseMosaic :: Int -> Int -> Mosaic
noiseMosaic seed n = lcgDoubles seed (n * n)

-- ════════════════════════════════════════════════════════════════
-- § 9. PSNR — the BR5 metric
-- ════════════════════════════════════════════════════════════════

mseRGB :: ImageRGB -> ImageRGB -> Double
mseRGB a b =
  sum [ (r1-r2)^(2::Int) + (g1-g2)^(2::Int) + (b1-b2)^(2::Int)
      | (RGB r1 g1 b1, RGB r2 g2 b2) <- zip a b ]
  / (3.0 * fromIntegral (length a))

psnr :: ImageRGB -> ImageRGB -> Double
psnr gt out =
  let m = mseRGB gt out
  in if m < 1e-12 then 99.0 else 10.0 * logBase 10 (1.0 / m)

-- ════════════════════════════════════════════════════════════════
-- § 10. AXIOMS
-- ════════════════════════════════════════════════════════════════

eps :: Double
eps = 1e-10

tolBR1, tolBR2, tolBR4 :: Double
tolBR1 = 1e-2
tolBR2 = 1e-2
tolBR4 = 3e-2

maxAbsDiff :: [Double] -> [Double] -> Double
maxAbsDiff a b = maximum (zipWith (\x y -> abs (x - y)) a b)

maxRGBDiff :: ImageRGB -> ImageRGB -> Double
maxRGBDiff a b = maximum
  [ maximum [abs (r1-r2), abs (g1-g2), abs (b1-b2)]
  | (RGB r1 g1 b1, RGB r2 g2 b2) <- zip a b ]

-- (BR0) mosaic ∘ demosaic = id on the mosaic domain.
--   Bilinear passes the measured sample through exactly, so
--   re-mosaicking recovers the input mosaic bit-for-bit.
axiom_BR0 :: Bool
axiom_BR0 = all check testMosaics
  where
    n = fieldN
    testMosaics = [ noiseMosaic s n | s <- [1, 2, 3] ]
               ++ [ mosaic n (smoothScene s n) | s <- [11, 22] ]
    check m = maxAbsDiff m (mosaic n (bilinearDemosaic n m)) < eps

-- (BR1) Flat-field identity: constant scene → residual ≈ 0 and
--   student output = the color (tol 1e-2). The same-phase Laplacian
--   makes the residual EXACTLY zero on flat fields; bilinear
--   reconstructs the constant exactly (mirror border, phase-safe).
axiom_BR1 :: Bool
axiom_BR1 = all check colors
  where
    n = fieldN
    colors = [ RGB r g b | [r, g, b] <- chunk3 (lcgDoubles 7 15) ]
    check c =
      let m      = mosaic n (flatScene n c)
          res    = residual standInGains n m
          out    = student standInGains n m
          resMax = maximum [ maximum [abs r, abs g, abs b]
                           | RGB r g b <- res ]
          outErr = maxRGBDiff out (flatScene n c)
      in resMax < tolBR1 && outErr < tolBR1

-- (BR2) Sample passthrough: at each mosaic site the output channel
--   that was physically measured stays within tol of the sample.
--   Bilinear passes it through exactly; the stand-in residual is
--   small on smooth scenes (a trained net must LEARN this bound —
--   weight the measured-site loss accordingly).
axiom_BR2 :: Bool
axiom_BR2 = all check [ smoothScene s fieldN | s <- [11, 22, 33] ]
  where
    n = fieldN
    check img =
      let m   = mosaic n img
          out = student standInGains n m
          errAt i =
            let x = i `mod` n
                y = i `div` n
            in abs (measuredChannel (cfaAt x y) (out !! i) - m !! i)
      in maximum [ errAt i | i <- [0 .. n*n - 1] ] <= tolBR2

-- (BR3) Bounded: output ∈ [0,1] ALWAYS. The hard clamp is part of
--   the operator, so this holds even for adversarial noise mosaics
--   where B(m) + f_θ(m) overshoots.
axiom_BR3 :: Bool
axiom_BR3 = all check testMosaics
  where
    n = fieldN
    testMosaics = [ noiseMosaic s n | s <- [4, 5, 6] ]
               ++ [ replicate (n*n) 0.0
                  , replicate (n*n) 1.0 ]
    inGamut (RGB r g b) = all (\v -> v >= 0.0 && v <= 1.0) [r, g, b]
    check m = all inGamut (student standInGains n m)

-- (BR4) Exposure equivariance: student(a·m) ≈ a·student(m) for
--   a ∈ [0.5, 1.0], tol 3e-2. B and the bias-free linear f_θ are
--   exactly 1-homogeneous; the clamp is inactive on in-gamut scenes.
axiom_BR4 :: Bool
axiom_BR4 = and [ check s a | s <- [11, 22], a <- [0.5, 0.75, 1.0] ]
  where
    n = fieldN
    check s a =
      let m   = mosaic n (smoothScene s n)
          lhs = student standInGains n (map (* a) m)
          rhs = map (scaleRGB a) (student standInGains n m)
      in maxRGBDiff lhs rhs <= tolBR4

-- (BR6) Budget: the shippable f_θ fits the kernel constraints —
--   ≤ 8,000 parameters, receptive field ≤ 9×9. The stand-in's
--   receptive field (5×5) also fits.
axiom_BR6 :: Bool
axiom_BR6 =
     archParams referenceArch <= 8000
  && receptiveField referenceArch <= 9
  && 5 <= 9  -- stand-in same-phase Laplacian RF

-- (BR5) Mighty: held-out PSNR(student) > PSNR(bilinear) + 1.0 dB.
--   NOT an axiom of this spec — it is the SHIPPING GATE, checked
--   empirically after training. The stand-in is untrained and is
--   not expected to clear it. Stated here so the gate is canon.

-- ════════════════════════════════════════════════════════════════
-- § 11. MAIN
-- ════════════════════════════════════════════════════════════════

main :: IO ()
main = do
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " BayerResidual: The Demosaic Residual Contract (v1)"
  putStrLn " Teacher = bilinear B(m).  Student = clamp01(B(m) + f_θ(m))."
  putStrLn " The net learns only what bilinear gets wrong."
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""

  let n = fieldN

  -- CFA pattern
  putStrLn "── RGGB CFA (top-left 4×4) ──"
  putStrLn ""
  mapM_ (\y -> putStrLn $ "  " ++ unwords
          [ cfaLabel (cfaAt x y) | x <- [0..3] ]) [0..3]
  putStrLn ""

  -- Flat-field identity
  putStrLn "── BR1: Flat-Field Identity (LCG colors) ──"
  putStrLn ""
  putStrLn "  color (r,g,b)               │ max|residual| │ max|out−color|"
  putStrLn "  ────────────────────────────┼───────────────┼───────────────"
  mapM_ (\[r, g, b] -> do
    let c      = RGB r g b
        m      = mosaic n (flatScene n c)
        res    = residual standInGains n m
        out    = student standInGains n m
        resMax = maximum [ maximum [abs r', abs g', abs b']
                         | RGB r' g' b' <- res ]
        outErr = maxRGBDiff out (flatScene n c)
    putStrLn $ "  (" ++ showF r ++ ", " ++ showF g ++ ", " ++ showF b ++ ")"
            ++ " │ " ++ padL 13 (showF resMax)
            ++ " │ " ++ showF outErr
    ) (take 4 (chunk3 (lcgDoubles 7 15)))
  putStrLn ""

  -- Sample passthrough
  putStrLn "── BR2: Sample Passthrough (smooth scenes) ──"
  putStrLn ""
  putStrLn "  scene seed │ max |out_measured − sample| │ tol"
  putStrLn "  ───────────┼─────────────────────────────┼──────"
  mapM_ (\s -> do
    let img = smoothScene s n
        m   = mosaic n img
        out = student standInGains n m
        err = maximum [ abs (measuredChannel (cfaAt (i `mod` n) (i `div` n))
                               (out !! i) - m !! i)
                      | i <- [0 .. n*n - 1] ]
    putStrLn $ "  " ++ padL 10 (show s)
            ++ " │ " ++ padL 27 (showF err)
            ++ " │ " ++ showF tolBR2
    ) [11, 22, 33]
  putStrLn ""

  -- Exposure equivariance
  putStrLn "── BR4: Exposure Equivariance (seed 11) ──"
  putStrLn ""
  putStrLn "  a      │ max |student(a·m) − a·student(m)| │ tol"
  putStrLn "  ───────┼───────────────────────────────────┼──────"
  let m11 = mosaic n (smoothScene 11 n)
      base11 = student standInGains n m11
  mapM_ (\a -> do
    let lhs = student standInGains n (map (* a) m11)
        rhs = map (scaleRGB a) base11
    putStrLn $ "  " ++ padL 6 (showF a)
            ++ " │ " ++ padL 33 (showF (maxRGBDiff lhs rhs))
            ++ " │ " ++ showF tolBR4
    ) [0.5, 0.75, 1.0]
  putStrLn ""

  -- PSNR machinery (BR5 metric, stand-in is untrained)
  putStrLn "── BR5 Metric: PSNR vs ground truth (stand-in, UNTRAINED) ──"
  putStrLn ""
  putStrLn "  scene seed │ PSNR bilinear │ PSNR student │ Δ dB"
  putStrLn "  ───────────┼───────────────┼──────────────┼──────"
  mapM_ (\s -> do
    let gt   = smoothScene s n
        m    = mosaic n gt
        pB   = psnr gt (bilinearDemosaic n m)
        pS   = psnr gt (student standInGains n m)
    putStrLn $ "  " ++ padL 10 (show s)
            ++ " │ " ++ padL 13 (showF pB)
            ++ " │ " ++ padL 12 (showF pS)
            ++ " │ " ++ showSigned (pS - pB)
    ) [11, 22, 33]
  putStrLn ""
  putStrLn "  (Stand-in gains are hand-set, not trained — Δ may be ≤ 0."
  putStrLn "   The TRAINED net must clear Δ ≥ +1.0 dB held-out, or it"
  putStrLn "   does not ship.)"
  putStrLn ""

  -- Parameter budget
  putStrLn "── Parameter Budget: reference f_θ ──"
  putStrLn ""
  putStrLn "  layer             │ k×k │ in → out │ params"
  putStrLn "  ──────────────────┼─────┼──────────┼───────"
  mapM_ (\cs -> do
    putStrLn $ "  " ++ padR 17 (csName cs)
            ++ " │ " ++ show (csK cs) ++ "×" ++ show (csK cs)
            ++ " │ " ++ padL 3 (show (csIn cs))
            ++ " → " ++ padL 3 (show (csOut cs))
            ++ " │ " ++ padL 5 (show (convParams cs))
    ) referenceArch
  putStrLn   "  ──────────────────┼─────┼──────────┼───────"
  putStrLn $ "  TOTAL (bias-free) │     │          │ "
          ++ padL 5 (show (archParams referenceArch))
          ++ "   (≤ 8000)"
  putStrLn $ "  receptive field:  " ++ show (receptiveField referenceArch)
          ++ "×" ++ show (receptiveField referenceArch) ++ "  (≤ 9×9)"
  putStrLn ""

  -- Axioms
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " AXIOMS"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  check "BR0 mosaic ∘ demosaic = id on mosaic domain"           [axiom_BR0]
  check "BR1 flat field → residual ≈ 0, output = color"         [axiom_BR1]
  check "BR2 measured samples pass through (tol 1e-2)"          [axiom_BR2]
  check "BR3 output ∈ [0,1] always (hard clamp)"                [axiom_BR3]
  check "BR4 exposure equivariance a ∈ [0.5,1] (tol 3e-2)"      [axiom_BR4]
  check "BR6 budget: ≤ 8000 params, receptive field ≤ 9×9"      [axiom_BR6]
  putStrLn "  ◌ BR5 mighty: PSNR(student) ≥ PSNR(bilinear) + 1.0 dB held-out"
  putStrLn "        VERIFIED-BY-TRAINING — shipping gate, not provable here"
  putStrLn ""

  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn " THE CONTRACT"
  putStrLn "════════════════════════════════════════════════════════════"
  putStrLn ""
  putStrLn "  Bilinear is the floor. The net is a residual on top."
  putStrLn "  Flat scenes cost nothing. Measured samples are sacred."
  putStrLn "  Bias-free + ReLU ⇒ exposure equivariance for free."
  putStrLn "  Borders mirror WITHOUT repeating the edge (CFA phase!)."
  putStrLn "  If it can't beat bilinear by 1 dB, it doesn't ship."
  putStrLn "════════════════════════════════════════════════════════════"

-- ════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════

cfaLabel :: CFA -> String
cfaLabel CfaR  = "R "
cfaLabel CfaGr = "Gr"
cfaLabel CfaGb = "Gb"
cfaLabel CfaB  = "B "

-- | Fixed-point, 4 decimals — never scientific notation
showF :: Double -> String
showF x =
  let v     = abs (round (x * 10000) :: Int)
      whole = v `div` 10000
      frac  = v `mod` 10000
      pad4 s = replicate (max 0 (4 - length s)) '0' ++ s
      s = (if x < 0 then "-" else "") ++ show whole ++ "." ++ pad4 (show frac)
  in take 7 (s ++ repeat '0')

showSigned :: Double -> String
showSigned x
  | x >= 0    = "+" ++ showF x
  | otherwise = showF x

padL :: Int -> String -> String
padL n s = replicate (max 0 (n - length s)) ' ' ++ s

padR :: Int -> String -> String
padR n s = s ++ replicate (max 0 (n - length s)) ' '

check :: String -> [Bool] -> IO ()
check name results =
  let passed = all id results
      n = length results
      mark = if passed then "✓" else "✗"
  in putStrLn $ "  " ++ mark ++ " " ++ name ++ " (" ++ show n ++ " cases)"
