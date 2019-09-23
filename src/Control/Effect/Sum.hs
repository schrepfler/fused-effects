{-# LANGUAGE ConstraintKinds, DeriveGeneric, DeriveTraversable, FlexibleContexts, FlexibleInstances, KindSignatures, MultiParamTypeClasses, TypeOperators, UndecidableInstances #-}
module Control.Effect.Sum
( (:+:)(..)
, Member
, Inject(..)
, Project(..)
) where

import Control.Effect.Class
import GHC.Generics (Generic1)

data (f :+: g) (m :: * -> *) k
  = L (f m k)
  | R (g m k)
  deriving (Eq, Foldable, Functor, Generic1, Ord, Show, Traversable)

infixr 4 :+:

instance (HFunctor f, HFunctor g) => HFunctor (f :+: g)
instance (Effect f, Effect g)     => Effect   (f :+: g)


type Member sub sup = (Inject sub sup, Project sub sup)


class Inject (sub :: (* -> *) -> (* -> *)) sup where
  inj :: sub m a -> sup m a

instance Inject t t where
  inj = id

instance {-# OVERLAPPABLE #-}
         Inject t (l1 :+: l2 :+: r)
      => Inject t ((l1 :+: l2) :+: r) where
  inj = reassoc . inj where
    reassoc (L l)     = L (L l)
    reassoc (R (L l)) = L (R l)
    reassoc (R (R r)) = R r

instance {-# OVERLAPPABLE #-}
         Inject l (l :+: r) where
  inj = L . inj

instance {-# OVERLAPPABLE #-}
         Inject l r
      => Inject l (l' :+: r) where
  inj = R . inj


class Project (sub :: (* -> *) -> (* -> *)) sup where
  prj :: sup m a -> Maybe (sub m a)

instance Project sub sub where
  prj = Just

instance {-# OVERLAPPABLE #-} Project sub (sub :+: sup) where
  prj (L f) = Just f
  prj _     = Nothing

instance {-# OVERLAPPABLE #-} Project sub sup => Project sub (sub' :+: sup) where
  prj (R g) = prj g
  prj _     = Nothing
