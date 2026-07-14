-- | Bayer quad symmetry laws: V4 is a group, applyV4 is a group action.
module ISP.Laws.Bayer (laws) where

import Test.QuickCheck
import ISP.Bayer

laws :: [(String, Property)]
laws =
  [ ("applyV4 E is identity",                    property prop_identity)
  , ("applyV4 (compose g h) = applyV4 g . applyV4 h",
     property prop_groupAction)
  , ("applyV4 g . applyV4 g = identity (order 2)", property prop_order2)
  , ("zipQuadWith distributes over swap",          property prop_zipSwap)
  , ("Gr and Gb are distinguishable after H flip", property prop_GrGbDistinct)
  ]

genQuad :: Gen (Quad Int)
genQuad = Quad <$> choose (0, 1000)
               <*> choose (0, 1000)
               <*> choose (0, 1000)
               <*> choose (0, 1000)

genV4 :: Gen V4
genV4 = elements v4All

compose :: V4 -> V4 -> V4
compose E  x  = x
compose x  E  = x
compose H  H  = E
compose V  V  = E
compose HV HV = E
compose H  V  = HV
compose V  H  = HV
compose H  HV = V
compose HV H  = V
compose V  HV = H
compose HV V  = H

prop_identity :: Property
prop_identity = forAll genQuad $ \q -> applyV4 E q == q

prop_groupAction :: Property
prop_groupAction = forAll genV4 $ \g ->
                   forAll genV4 $ \h ->
                   forAll genQuad $ \q ->
  applyV4 (compose g h) q == applyV4 g (applyV4 h q)

prop_order2 :: Property
prop_order2 = forAll genV4 $ \g ->
              forAll genQuad $ \q ->
  applyV4 g (applyV4 g q) == q

prop_zipSwap :: Property
prop_zipSwap = forAll genQuad $ \a ->
               forAll genQuad $ \b ->
  zipQuadWith (+) a b == zipQuadWith (+) b a

prop_GrGbDistinct :: Property
prop_GrGbDistinct = forAll genQuad $ \q ->
  qGr q /= qGb q  ==>  q /= applyV4 H q
