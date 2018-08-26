{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ExplicitNamespaces #-}

module Main where

import Prelude hiding (lookup)
import qualified Data.ByteString.Lazy as BS
import qualified Data.ByteString as BSS
import qualified Data.Maybe as M
import qualified Data.List as L
import qualified Data.Text.Lazy as T
import qualified Data.Text.Lazy.IO as T
import qualified Data.Text.Lazy.Encoding as T
import Codec.Compression.GZip (compress, decompress)
import Options.Generic (Generic, ParseRecord, Unwrapped, Wrapped, unwrapRecord, (:::), type (<?>)(..))
import Control.Monad (join, liftM)
import qualified Data.Map as Map
import System.IO (withFile, hPutStr, IOMode(..))
import Codec.Compression.PPM (fromSequences, Model, classifySequence, scoreSequence)
import Codec.Compression.PPM.Utils (lineToInstance)
import Data.Serialize (encodeLazy, decodeLazy)
import Data.Serialize.Text

data Parameters w = Train { train :: w ::: String <?> "Train file"
                          , dev :: w ::: String <?> "Development file (mutually exclusive with --n, which takes precendence)"
                          , n :: w ::: Int <?> "Maximum context size (mutually exclusive with --dev, this option takes precedence)"
                          , modelFile :: w ::: String <?> "Model file (output or input, depending on whether training or testing, respectively)"
                          }
                  | Apply { modelFile :: w ::: String <?> "Model file (output or input, depending on whether training or testing, respectively)"
                          , n :: w ::: Int <?> "Maximum context size (mutually exclusive with --dev, this option takes precedence)"                          
                          , test :: w ::: String <?> "Test file"
                          , scoresFile :: w ::: String <?> "Output file for scores"
                          }
  deriving (Generic)                              
                                                            
instance ParseRecord (Parameters Wrapped)
deriving instance Show (Parameters Unwrapped)

evaluateModel :: Model T.Text Char -> Int -> [(T.Text, [Char])] -> Double
evaluateModel m n xs = accuracy
  where
    gold = map fst xs
    guess = map (classifySequence m n) (map snd xs)
    correct = length $ [x | (x, y) <- zip gold guess, x == y]
    accuracy = (fromIntegral correct) / (fromIntegral $ length gold)


main :: IO ()
main = do
  ps <- unwrapRecord "Do PPM-related stuff: all inputs should be tab-separated lines of the form  ID<TAB>LABEL<TAB>TEXT  Specify a subcommand with '--help' to see its options."  
  case ps of
    Train {..} -> do
      trainInstances <- map lineToInstance <$> (liftM T.lines . liftM T.strip . T.readFile) train
      let model = fromSequences n trainInstances
      devInstances <- map lineToInstance <$> (liftM T.lines . liftM T.strip . T.readFile) dev
      print $ evaluateModel model n devInstances
      withFile modelFile WriteMode (\ h -> BS.hPutStr h (encodeLazy model))
    Apply {..} -> do
      testInstances <- map lineToInstance <$> (liftM T.lines . liftM T.strip . T.readFile) test
      loader <- decodeLazy <$> BS.readFile modelFile :: IO (Either String (Model T.Text Char))      
      case loader of
        Right model -> print $ evaluateModel model n testInstances
        Left error -> print error
      
