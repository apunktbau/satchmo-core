{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- |@MonadSAT@ instance that prints the generated formula instead of solving it
module Satchmo.Core.SAT.StdOut
  (SAT, onStdOut, module Satchmo.Core.MonadSAT)
where

import Control.Monad.State
import Data.Word (Word)
import Satchmo.Core.MonadSAT 
import Satchmo.Core.Data (Literal (..),Clause (..),literal)

data SATState = SATState { nextVariable :: Word
                         , nextClause   :: Word
                         }

newtype SAT a = SAT { runSAT :: StateT SATState IO a }
  deriving (Monad, MonadState SATState, MonadIO)

instance MonadSAT SAT where
  fresh = do
    i <- gets nextVariable
    modify ( \s -> s { nextVariable = nextVariable s + 1 } )
    return $ literal True i

  emit clause = do
    modify ( \s -> s { nextClause = nextClause s + 1 } )
    liftIO $ putStrLn $ unwords (map emitLiteral (literals clause) ++ ["0"])
    where
      emitLiteral literal | isPositive literal =        show $ variable literal
      emitLiteral literal | otherwise          = '-' : (show $ variable literal)

  note = liftIO . putStrLn

-- |Prints reversed DIMACS formula on stdout
onStdOut :: SAT a -> IO a
onStdOut sat = do 
  (result,state) <- runStateT (runSAT sat) (SATState 0 0)
  putStrLn $ unwords ["p cnf", show $ nextVariable state, show $ nextClause state]
  return result
