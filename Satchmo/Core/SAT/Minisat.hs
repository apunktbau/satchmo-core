{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE LambdaCase #-}
-- |Binding to Minisat solver
module Satchmo.Core.SAT.Minisat
  (SAT, solve, solveWithTimeout, solve', module Satchmo.Core.MonadSAT)
where

import           Control.Monad (void,when)
import           Control.Monad.IO.Class (MonadIO (..))
import           System.IO (stderr,hPutStrLn)
import           Control.Concurrent.MVar (newEmptyMVar,putMVar,takeMVar)
import           Control.Concurrent (killThread,forkIO,threadDelay)
import           Control.Exception (AsyncException,catch)
import           Satchmo.Core.MonadSAT 
import qualified MiniSat as API
import           Satchmo.Core.Data (Literal (..),Clause (..),literal)
import           Satchmo.Core.Decode (Decode (..))
import           Satchmo.Core.Boolean (Boolean (..))
import           Satchmo.Core.Formula (Formula, decodeFormula)

newtype SAT a = SAT (API.Solver -> IO a)

instance Functor SAT where
  fmap f ( SAT m ) = SAT $ \ s -> fmap f ( m s )

instance Monad SAT where
  return x    = SAT $ const $ return x
  SAT m >>= f = SAT $ \ s -> do x <- m s ; let { SAT n = f x } ; n s

instance MonadIO SAT where
  liftIO = SAT . const 

instance MonadSAT SAT where
  fresh = SAT $ \ s -> do 
    API.MkLit x <- API.newLit s
    return $ literal True $ fromIntegral x

  emit clause = SAT $ \ s -> void $ API.addClause s apiClause
    where
      apiClause      = map toApiLiteral $ literals clause
      toApiLiteral l = ( if isPositive l then id else API.neg ) 
                       $ API.MkLit
                       $ fromIntegral
                       $ variable l

  note msg = SAT $ const $ putStrLn msg

  numVariables = SAT API.minisat_num_vars
  numClauses   = SAT API.minisat_num_clauses

instance Decode SAT Boolean Bool where
    decode b = case b of
        Constant c -> return c
        Boolean  literal -> do 
            let valueOf var = SAT $ \ s -> do
                    Just value <- API.modelValue s $ API.MkLit $ fromIntegral var
                    return value 
            value <- valueOf $ variable literal
            return $ if isPositive literal then value else not value

instance Decode SAT Formula Bool where
  decode = decodeFormula


solveWithTimeout :: Maybe Int       -- ^Timeout in seconds
                 -> SAT (SAT a)     -- ^Action in the 'SAT' monad
                 -> IO (Maybe a)    -- ^'Maybe' a result
solveWithTimeout mto action = do
    accu <- newEmptyMVar 
    worker <- forkIO $ solve action >>= putMVar accu
    timer <- forkIO $ case mto of
        Just to -> do 
              threadDelay ( 10^6 * to ) 
              killThread worker 
              putMVar accu Nothing
        _  -> return ()
    takeMVar accu `Control.Exception.catch` \ ( _ :: AsyncException ) -> do
        hPutStrLn stderr "caught"
        killThread worker
        killThread timer
        return Nothing

solve :: SAT (SAT a)    -- ^Action in the 'SAT' monad
      -> IO (Maybe a)   -- ^'Maybe' a result
solve (SAT m) = solve' True $ SAT $ \s -> m s >>= return . Just 

solve' :: Bool                -- ^Be verbosely
       -> SAT (Maybe (SAT a)) -- ^'Maybe' an action in the 'SAT' monad
       -> IO (Maybe a)        -- ^'Maybe' a result
solve' verbose ( SAT m ) = API.withNewSolver $ \ s -> do
  when verbose $ hPutStrLn stderr $ "Start producing CNF"
  m s >>= \case 
    Nothing -> do
      when verbose $ hPutStrLn stderr "Abort due to known result"
      return Nothing
    Just (SAT decoder) -> do
      v <- API.minisat_num_vars s
      c <- API.minisat_num_clauses s
      when verbose $ hPutStrLn stderr 
                   $ concat [ "CNF finished (" , "#variables: ", show v
                                               , ", #clauses: "  , show c 
                                               , ")"]
      when verbose $ hPutStrLn stderr $ "Starting solver"
      b <- API.solve s []
      when verbose $ hPutStrLn stderr $ "Solver finished (result: " ++ show b ++ ")"
      if b 
        then do
          when verbose $ hPutStrLn stderr $ "Starting decoder"    
          out <- decoder s
          when verbose $ hPutStrLn stderr $ "Decoder finished"    
          return $ Just out
        else return Nothing

