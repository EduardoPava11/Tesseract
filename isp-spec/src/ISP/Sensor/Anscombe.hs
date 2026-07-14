-- | Variance-stabilizing transforms for Poisson and Poisson+Gaussian data.
-- See Makitalo & Foi, "Optimal inversion of the Anscombe transformation".
module ISP.Sensor.Anscombe
  ( anscombe
  , anscombeInv
  , anscombeG
  , anscombeGInv
  ) where

-- Standard Anscombe: for X ~ Poisson(lambda), Var(2*sqrt(X + 3/8)) ~= 1.
anscombe :: Double -> Double
anscombe x = 2 * sqrt (max 0 x + 3 / 8)

-- Asymptotically-unbiased inverse (Makitalo-Foi).
anscombeInv :: Double -> Double
anscombeInv z
  | z <= 0 = 0
  | otherwise =
      let z2 = z / 2
          c  = sqrt (3 / 2)
      in z2 * z2
           + (c / (4 * z))
           - (11 / (8 * z * z))
           + (5 * c / (8 * z ** 3))
           - (1 / 8)

-- Generalized Anscombe for Poisson + Gaussian:
--   z = (2/alpha) * sqrt(alpha*x + 3/8 * alpha^2 + beta)
-- where alpha = noise slope (e per DN), beta = read-noise variance.
anscombeG :: Double -> Double -> Double -> Double
anscombeG alpha beta x =
  (2 / alpha)
    * sqrt (alpha * max 0 x + 3 / 8 * alpha * alpha + beta)

anscombeGInv :: Double -> Double -> Double -> Double
anscombeGInv alpha beta z =
  let u = alpha * z / 2
  in (u * u - 3 / 8 * alpha * alpha - beta) / alpha
