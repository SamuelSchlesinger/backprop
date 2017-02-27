{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs            #-}
{-# LANGUAGE LambdaCase       #-}
{-# LANGUAGE RankNTypes       #-}

module Numeric.Backprop.Op
  ( Op(..)
  , runOp, gradOp, gradOpWith, gradOpWith'
  , op0
  , op1, op2, op3, opN
  , op1', op2', op3', opN'
  , Replicate
  ) where

import           Data.Bifunctor
import           Data.Reflection                (Reifies)
import           Data.Type.Combinator
import           Data.Type.Nat
import           Data.Type.Product
import           Data.Type.Util
import           Data.Type.Vector
import           Numeric.AD
import           Numeric.AD.Internal.Reverse    (Reverse, Tape)
import           Numeric.AD.Mode.Forward hiding (grad')
import           Numeric.Backprop.Internal
import           Type.Class.Known

runOp :: Op as a -> Tuple as -> a
runOp o = fst . runOp' o

gradOpWith' :: Op as a -> Tuple as -> Maybe a -> Tuple as
gradOpWith' o = snd . runOp' o

gradOpWith :: Op as a -> Tuple as -> a -> Tuple as
gradOpWith o i = gradOpWith' o i . Just

gradOp :: Op as a -> Tuple as -> Tuple as
gradOp o i = gradOpWith' o i Nothing

op0 :: a -> Op '[] a
op0 x = Op $ \case
    Ø -> (x, const Ø)

op1' :: (a -> (b, Maybe b -> a)) -> Op '[a] b
op1' f = Op $ \case
    I x :< Ø ->
      let (y, dx) = f x
      in  (y, only_ . dx)

op2' :: (a -> b -> (c, Maybe c -> (a, b))) -> Op '[a,b] c
op2' f = Op $ \case
    I x :< I y :< Ø ->
      let (z, dxdy) = f x y
      in  (z, (\(dx,dy) -> dx ::< dy ::< Ø) . dxdy)

op3' :: (a -> b -> c -> (d, Maybe d -> (a, b, c))) -> Op '[a,b,c] d
op3' f = Op $ \case
    I x :< I y :< I z :< Ø ->
      let (q, dxdydz) = f x y z
      in  (q, (\(dx, dy, dz) -> dx ::< dy ::< dz ::< Ø) . dxdydz)

opN' :: (Num a, Known Nat n)
     => (Vec n a -> (b, Maybe b -> Vec n a))
     -> Op (Replicate n a) b
opN' f = Op $ (second . fmap) vecToProd . f . prodToVec' known

op1 :: Num a
    => (forall s. AD s (Forward a) -> AD s (Forward a))
    -> Op '[a] a
op1 f = op1' $ \x ->
    let (z, dx) = diff' f x
    in  (z, maybe dx (* dx))

op2 :: Num a
    => (forall s. Reifies s Tape => Reverse s a -> Reverse s a -> Reverse s a)
    -> Op '[a,a] a
op2 f = opN $ \case I x :* I y :* ØV -> f x y

op3 :: Num a
    => (forall s. Reifies s Tape => Reverse s a -> Reverse s a -> Reverse s a -> Reverse s a)
    -> Op '[a,a,a] a
op3 f = opN $ \case I x :* I y :* I z :* ØV -> f x y z

opN :: (Num a, Known Nat n)
    => (forall s. Reifies s Tape => Vec n (Reverse s a) -> Reverse s a)
    -> Op (Replicate n a) a
opN f = opN' $ \xs ->
    let (y, dxs) = grad' f xs
    in  (y, maybe dxs (\q -> (q *) <$> dxs))
