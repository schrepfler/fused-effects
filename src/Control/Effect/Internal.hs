{-# LANGUAGE DefaultSignatures, DeriveFunctor, EmptyCase, FlexibleContexts, FlexibleInstances, FunctionalDependencies, PolyKinds, RankNTypes, TypeOperators, UndecidableInstances #-}
module Control.Effect.Internal
( Eff(..)
, runEff
, send
, Effect(..)
, TermAlgebra(..)
, TermMonad
, Void
, run
, (:+:)(..)
, (\/)
, Subset(..)
) where

import Control.Applicative (Alternative(..))
import Control.Effect.Fail.Internal
import Control.Effect.Lift.Internal
import Control.Effect.NonDet.Internal
import Control.Monad (liftM, ap)
import Control.Monad.Fail
import Control.Monad.IO.Class
import Prelude hiding (fail)

newtype Eff h a = Eff { unEff :: forall x . (a -> h x) -> h x }

runEff :: (a -> f x) -> Eff f a -> f x
runEff = flip unEff
{-# INLINE runEff #-}

instance Functor (Eff h) where
  fmap = liftM

instance Applicative (Eff h) where
  pure a = Eff ($ a)

  (<*>) = ap

instance Monad (Eff h) where
  return = pure

  Eff m >>= f = Eff (\ k -> m (runEff k . f))

-- | The class of effect types, which must:
--
--   1. Be functorial in their last two arguments, and
--   2. Support threading effects in higher-order positions through using the carrier’s suspended state.
class Effect sig where
  -- | Functor map. This is required to be 'fmap'.
  fmap' :: (a -> b) -> (sig m a -> sig m b)
  default fmap' :: Functor (sig m) => (a -> b) -> (sig m a -> sig m b)
  fmap' = fmap

  -- | Higher-order functor map of a natural transformation over higher-order positions within the effect.
  hfmap :: (forall x . m x -> n x) -> sig m a -> sig n a

  -- | Handle any effects in higher-order positions by threading the carrier’s state all the way through to the continuation.
  handle :: (Functor f, Monad n)
         => f ()
         -> (forall x . f (m x) -> n (f x))
         -> sig m (m a)
         -> sig n (n (f a))


class Effect sig => TermAlgebra h sig | h -> sig where
  var :: a -> h a
  con :: sig h (h a) -> h a

instance TermAlgebra h sig => TermAlgebra (Eff h) sig where
  var = pure
  con op = Eff (\ k -> con (hfmap (runEff var) (fmap' (runEff k) op)))


class (Monad m, TermAlgebra m sig) => TermMonad m sig | m -> sig

instance TermAlgebra h sig => TermMonad (Eff h) sig


-- | Construct a request for an effect to be interpreted by some handler later on.
send :: (Subset effect sig, TermAlgebra m sig) => effect m (m a) -> m a
send = con . inj


data Void m k
  deriving (Functor)

instance Effect Void where
  hfmap _ v = case v of {}
  handle _ _ v = case v of {}

-- | Run an 'Eff' exhausted of effects to produce its final result value.
run :: Eff VoidH a -> a
run = runVoidH . runEff VoidH


newtype VoidH a = VoidH { runVoidH :: a }

instance TermAlgebra VoidH Void where
  var = VoidH
  con v = case v of {}


instance Functor sig => Effect (Lift sig) where
  hfmap _ (Lift op) = Lift op

  handle state handler (Lift op) = Lift (fmap (handler . (<$ state)) op)

instance (Subset (Lift IO) sig, TermAlgebra m sig) => MonadIO (Eff m) where
  liftIO = send . Lift . fmap pure


data (f :+: g) m k
  = L (f m k)
  | R (g m k)
  deriving (Eq, Functor, Ord, Show)

infixr 4 :+:

instance (Effect l, Effect r) => Effect (l :+: r) where
  hfmap f (L l) = L (hfmap f l)
  hfmap f (R r) = R (hfmap f r)

  fmap' f (L l) = L (fmap' f l)
  fmap' f (R r) = R (fmap' f r)

  handle state handler (L l) = L (handle state handler l)
  handle state handler (R r) = R (handle state handler r)

-- | Lift algebras for either side of a sum into a single algebra on sums.
(\/) :: ( sig1           m a -> b)
     -> (          sig2  m a -> b)
     -> ((sig1 :+: sig2) m a -> b)
(alg1 \/ _   ) (L op) = alg1 op
(_    \/ alg2) (R op) = alg2 op

infixr 4 \/

instance Effect NonDet where
  hfmap _ Empty      = Empty
  hfmap _ (Choose k) = Choose k

  handle _     _       Empty      = Empty
  handle state handler (Choose k) = Choose (handler . (<$ state) . k)

instance (Subset NonDet sig, TermAlgebra m sig) => Alternative (Eff m) where
  empty = send Empty
  l <|> r = send (Choose (\ c -> if c then l else r))


instance Effect Fail where
  hfmap _ (Fail s) = Fail s

  handle _ _ (Fail s) = Fail s

instance (Subset Fail sig, TermAlgebra m sig) => MonadFail (Eff m) where
  fail = send . Fail


class (Effect sub, Effect sup) => Subset sub sup where
  inj :: sub m a -> sup m a
  prj :: sup m a -> Maybe (sub m a)

instance Effect sub => Subset sub sub where
  inj = id
  prj = Just

instance {-# OVERLAPPABLE #-} (Effect sub, Effect sup) => Subset sub (sub :+: sup) where
  inj = L . inj
  prj (L f) = Just f
  prj _     = Nothing

instance {-# OVERLAPPABLE #-} (Effect sub', Subset sub sup) => Subset sub (sub' :+: sup) where
  inj = R . inj
  prj (R g) = prj g
  prj _     = Nothing