{-# LANGUAGE FlexibleContexts, RankNTypes #-}
module Cull
( tests
, NonDet.gen0
, genN
, test
) where

import qualified Control.Carrier.Cull.Church as CullC
import Control.Effect.Choose
import Control.Effect.Cull
import Control.Effect.NonDet (NonDet)
import Gen
import qualified Monad
import qualified MonadFix
import qualified NonDet
import Test.Tasty
import Test.Tasty.Hedgehog

tests :: TestTree
tests = testGroup "Cull"
  [ testGroup "CullC" $
    [ testMonad
    , testMonadFix
    , testCull
    ] >>= ($ runL CullC.runCullA)
  ] where
  testMonad    run = Monad.test    (m NonDet.gen0 genN) a b c initial run
  testMonadFix run = MonadFix.test (m NonDet.gen0 genN) a b   initial run
  testCull     run = Cull.test     (m NonDet.gen0 genN) a b   initial run
  initial = identity <*> unit


genN :: (Has Cull sig m, Has NonDet sig m) => GenM m -> Gen a -> [Gen (m a)]
genN m a = (label "cull" cull <*> m a) : NonDet.genN m a


test
  :: (Has Cull sig m, Has NonDet sig m, Arg a, Eq a, Eq b, Show a, Show b, Vary a, Functor f)
  => GenM m
  -> Gen a
  -> Gen b
  -> Gen (f ())
  -> Run f [] m
  -> [TestTree]
test m a b i (Run runCull)
  = testProperty "cull returns at most one success" (forall (i :. a :. m a :. m a :. Nil)
    (\ i a m n -> runCull ((cull (pure a <|> m) <|> n) <$ i) === runCull ((pure a <|> n) <$ i)))
  : NonDet.test m a b i (Run runCull)
