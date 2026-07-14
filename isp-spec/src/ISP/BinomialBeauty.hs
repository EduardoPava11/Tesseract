-- | Target distributions for the "binomial / bell-curve = beauty" aesthetic.
--
-- Pinned citation: /The Math That Explains Why Bell Curves Are Everywhere/,
-- Quanta Magazine, 2026-03-16. The aesthetic thesis: accumulation + averaging
-- produce a universal bell. Our 16x16x64 fingerprint's color-count histogram
-- should approximate a discrete bell, not a uniform distribution.
--
-- The 'BinomialModel' typeclass admits multiple candidate targets. Three ship
-- here; more can be added later. The 'DyadicBell' instance is the shape the
-- user described: @[1,1,2,4,8,16,32,32,16,8,4,2,1,1]@ for peak-exponent 5.
module ISP.BinomialBeauty
  ( BinomialModel (..)
  , FullCube (..)
  , FingerprintBinomial (..)
  , DyadicBell (..)
  , dyadicShape
  , normalize
  , binomialPMF
  ) where

import qualified Data.Vector as V

-- | A normalized distribution over frequency bins.
--
-- Laws (see ISP.Laws.BinomialBeauty):
--
--   * @V.length (modelPMF m) == modelBins m@
--   * @abs (V.sum (modelPMF m) - 1) < 1e-9@
--   * @modelExpected m == sum [ fromIntegral k * (modelPMF m V.! k) | k <- [0 .. modelBins m - 1] ]@
class BinomialModel m where
  modelBins     :: m -> Int
  modelPMF      :: m -> V.Vector Double
  modelExpected :: m -> Double
  modelSD       :: m -> Double

-- | Full-cube binomial: /B(4096, 1/256)/. Matches @BinomialCube.hs@.
data FullCube = FullCube
  deriving (Eq, Show)

-- | Fingerprint-scale binomial: /B(256, 1/64)/ — E=4, SD≈1.94.
-- This is the "statistical null hypothesis" for our 16×16×64 fingerprint
-- when colors are drawn uniformly at random.
data FingerprintBinomial = FingerprintBinomial
  deriving (Eq, Show)

-- | Dyadic palindromic bell, parameterized by peak exponent.
-- @DyadicBell 5@ gives @[1,1,2,4,8,16,32,32,16,8,4,2,1,1]@ (sum 128).
-- @DyadicBell 6@ gives @[1,1,2,4,8,16,32,64,64,32,16,8,4,2,1,1]@ (sum 256).
newtype DyadicBell = DyadicBell { peakExp :: Int }
  deriving (Eq, Show)

instance BinomialModel FullCube where
  modelBins _     = 4096 + 1
  modelPMF _      = binomialPMF 4096 (1 / 256)
  modelExpected _ = 16.0
  modelSD _       = sqrt (4096 * (1 / 256) * (1 - 1 / 256))

instance BinomialModel FingerprintBinomial where
  modelBins _     = 256 + 1
  modelPMF _      = binomialPMF 256 (1 / 64)
  modelExpected _ = 4.0
  modelSD _       = sqrt (256 * (1 / 64) * (1 - 1 / 64))

instance BinomialModel DyadicBell where
  modelBins (DyadicBell n)    = 2 * (n + 1 + 1)        -- e.g. n=5 -> 14 bins
  modelPMF  (DyadicBell n)    = normalize (V.map fromIntegral (dyadicShape n))
  modelExpected db            =
    let pmf = modelPMF db
    in V.sum (V.imap (\k p -> fromIntegral k * p) pmf)
  modelSD db                  =
    let pmf = modelPMF db
        mu  = modelExpected db
        var = V.sum (V.imap
                (\k p -> let d = fromIntegral k - mu in p * d * d) pmf)
    in sqrt var

-- | The integer shape @[1,1,2,4,..,2^n,2^n,..,4,2,1,1]@.
-- Length = @2 * (n + 2)@; sum = @2 * (2 + 2 + 4 + 8 + .. + 2^n)@ = @4 * (2^(n+1) - 1)@.
-- For n=5: length 14, sum 2*(1+1+2+4+8+16+32) = 2*64 = 128.
dyadicShape :: Int -> V.Vector Int
dyadicShape n
  | n < 0     = V.empty
  | otherwise =
      let ramp = 1 : 1 : [ 2 ^ k | k <- [1 .. n] ]
      in V.fromList (ramp ++ reverse ramp)

-- | Normalize a non-negative vector to a PMF. If the sum is zero, return a
-- uniform distribution over the same length.
normalize :: V.Vector Double -> V.Vector Double
normalize v =
  let s = V.sum v
  in if s <= 0
       then V.replicate (V.length v) (1 / fromIntegral (max 1 (V.length v)))
       else V.map (/ s) v

-- | Binomial PMF @P(k; n, p) = C(n,k) p^k (1-p)^(n-k)@ for /k = 0..n/.
-- Computed in log-space for numerical stability. The result is then
-- renormalized so it sums to exactly 1 (closes small rounding errors).
binomialPMF :: Int -> Double -> V.Vector Double
binomialPMF n p
  | n < 0 || p <= 0 || p >= 1 = V.singleton 1
  | otherwise =
      let q       = 1 - p
          logP    = log p
          logQ    = log q
          -- logFact[k] = log(k!) for k in 0..n
          logFact = V.scanl'
                      (\acc k -> acc + log (fromIntegral (k :: Int)))
                      0
                      (V.enumFromN 1 n)
          lg k    = logFact V.! n - logFact V.! k - logFact V.! (n - k)
                  + fromIntegral k * logP + fromIntegral (n - k) * logQ
          raw     = V.generate (n + 1) (exp . lg)
          s       = V.sum raw
      in if s > 0 then V.map (/ s) raw else raw
