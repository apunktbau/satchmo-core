module Satchmo.Core.Boolean
  (Boolean (..), isConstant, boolean, module Satchmo.Core.Primitive)
where

import           Prelude hiding (not,and)
import qualified Prelude as P
import           Control.Monad (when)
import           Data.List (partition)
import           Satchmo.Core.Data (Literal,clause)
import qualified Satchmo.Core.Data as D
import           Satchmo.Core.MonadSAT (MonadSAT,fresh,emit)
import           Satchmo.Core.Primitive 

data Boolean = Boolean  { encode ::  Literal }
             | Constant { value  :: !Bool }

instance Show Boolean where
  show (Boolean b) | D.isPositive b = show $ D.variable b
  show (Boolean b)                  = "!" ++ (show $ D.variable b)
  show (Constant b)                 = show b

isConstant :: Boolean -> Bool
isConstant (Constant {}) = True
isConstant _             = False

instance Primitive Boolean where

  constant = Constant

  primitive = fresh >>= return . Boolean 

  assert booleans = 
    let (constants,rest) = partition isConstant booleans
        constantValue    = P.or $ map value constants
    in
      when (P.not constantValue) $ emit $ clause $ map encode rest

  not boolean = case boolean of
    Boolean literal   -> Boolean  $ D.not literal
    Constant constant -> Constant $ P.not constant

  and booleans = case booleans of
    []  -> return $ constant True
    [x] -> return x
    xs  -> do y <- boolean                                  
              sequence_ $ do x <- xs                        -- y -> xs
                             return $ assertOr [not y, x]
              assertOr $ y : map not xs                     -- y <- xs
              return y

-- |@boolean = primitive@ but with non-ambiguous type
boolean :: MonadSAT m => m Boolean
boolean = primitive
