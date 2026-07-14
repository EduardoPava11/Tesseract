-- | Color-doubling by splitting each bucket along its first principal axis.
--
-- For each bucket, compute the mean and the 3x3 covariance matrix in Oklab,
-- run power iteration to find the top eigenvector, and emit two centroids:
-- mean +/- sigma * PC1 where sigma is the sqrt of the top eigenvalue.
module ISP.ColorDouble.PCA
  ( PCASplit (..)
  ) where

import qualified Data.Vector as V
import ISP.ColorDouble
import ISP.Oklab

-- | No tunables at construction time. Power iteration uses 20 steps.
data PCASplit = PCASplit
  deriving (Eq, Show)

instance ColorDouble PCASplit where
  double PCASplit pal ref =
    let buckets = bucketIndices pal ref
        pairs   = V.imap (splitBucket pal) buckets
        newPal  = palettePair pairs
        newIdx  = assignNearest newPal ref
    in (newPal, newIdx)

splitBucket :: OklabPalette -> Int -> V.Vector Oklab -> (Oklab, Oklab)
splitBucket pal k pts
  | V.length pts < 2 =
      let c = pal V.! k in (shiftL c (-0.02), shiftL c 0.02)
  | otherwise =
      let m                 = meanOklab pts
          (cxx, cyy, czz,
           cxy, cxz, cyz)   = covariance m pts
          (vx, vy, vz, lam) = topEigen (cxx, cyy, czz, cxy, cxz, cyz)
          sigma             = sqrt (max 0 lam)
          dx                = sigma * vx
          dy                = sigma * vy
          dz                = sigma * vz
          Oklab mL mA mB    = m
      in ( Oklab (mL - dx) (mA - dy) (mB - dz)
         , Oklab (mL + dx) (mA + dy) (mB + dz))

shiftL :: Oklab -> Double -> Oklab
shiftL (Oklab l a b) d = Oklab (l + d) a b

meanOklab :: V.Vector Oklab -> Oklab
meanOklab v =
  let n = fromIntegral (V.length v)
      (sL, sA, sB) = V.foldl' (\(l,a,b) (Oklab l' a' b') -> (l+l', a+a', b+b'))
                               (0, 0, 0) v
  in Oklab (sL / n) (sA / n) (sB / n)

-- | Symmetric 3x3 covariance about the mean, returned as its 6 unique entries
-- (cxx, cyy, czz, cxy, cxz, cyz).
covariance
  :: Oklab
  -> V.Vector Oklab
  -> (Double, Double, Double, Double, Double, Double)
covariance (Oklab mL mA mB) pts =
  let n = fromIntegral (V.length pts)
      (xx, yy, zz, xy, xz, yz) =
        V.foldl' acc (0, 0, 0, 0, 0, 0) pts
      acc (a1, a2, a3, a4, a5, a6) (Oklab l a b) =
        let dl = l - mL
            da = a - mA
            db = b - mB
        in ( a1 + dl*dl
           , a2 + da*da
           , a3 + db*db
           , a4 + dl*da
           , a5 + dl*db
           , a6 + da*db)
  in (xx/n, yy/n, zz/n, xy/n, xz/n, yz/n)

-- | Power iteration on a symmetric 3x3 matrix; returns (vx, vy, vz, lambda).
-- The matrix is passed as its 6 unique entries.
topEigen
  :: (Double, Double, Double, Double, Double, Double)
  -> (Double, Double, Double, Double)
topEigen (a11, a22, a33, a12, a13, a23) =
  let mul (x, y, z) =
        ( a11*x + a12*y + a13*z
        , a12*x + a22*y + a23*z
        , a13*x + a23*y + a33*z)
      normalize (x, y, z) =
        let n = sqrt (x*x + y*y + z*z)
        in if n < 1e-12 then (1, 0, 0) else (x/n, y/n, z/n)
      step v = normalize (mul v)
      vFinal = iterate step (1/sqrt 3, 1/sqrt 3, 1/sqrt 3) !! 20
      (vx, vy, vz) = vFinal
      (wx, wy, wz) = mul vFinal
      lam = vx*wx + vy*wy + vz*wz
  in (vx, vy, vz, lam)
