{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RecordWildCards #-}

-- | The Hell shell.

module Hell
  (module Hell.Types
  ,module Data.Default
  ,startHell)
  where

import Hell.Types

import Control.Exception
import Control.Monad
import Control.Monad.Fix
import Data.Default
import Data.Dynamic
import Data.List
import System.Console.Haskeline
import System.Console.Haskeline.IO
import System.Directory
import System.Posix.User

import GHC
import GHC.Paths
import GhcMonad

-- | Go to hell.
startHell :: Config -> IO ()
startHell Config{..} =
  runGhc
    (Just libdir)
    (do dflags <- getSessionDynFlags
        void (setSessionDynFlags dflags)
        setImports configImports
        hd <- io (initializeInput defaultSettings)
        home <- io getHomeDirectory
        username <- io getEffectiveUserName
        unless (null configWelcome)
               (io (queryInput hd (outputStrLn configWelcome)))
        fix (\loop ->
               do pwd <- io getCurrentDirectory
                  prompt <- configPrompt username (stripHome home pwd)
                  mline <- io (queryInput hd (getInputLine prompt))
                  case mline of
                    Nothing -> loop
                    Just line ->
                      do result <- runStatement line
                         unless (null result)
                                (io (queryInput hd (outputStrLn result)))
                         loop))

-- | Strip and replace /home/chris/blah with ~/blah.
stripHome :: FilePath -> FilePath -> FilePath
stripHome home path
  | isPrefixOf home path = "~/" ++ dropWhile (=='/') (drop (length home) path)
  | otherwise            = path

-- | Import the given modules.
setImports :: [String] -> Ghc ()
setImports =
  mapM (fmap IIDecl . parseImportDecl) >=> setContext

-- | Run the given statement.
runStatement :: String -> Ghc String
runStatement stmt' = do
  result <- gcatch (fmap Right (dynCompileExpr stmt))
                   (\(e::SomeException) -> return (Left e))
  case result of
    Left{} -> runExpression stmt'
    Right compiled ->
      gcatch (fmap ignoreUnit (io (fromDyn compiled (return "Bad compile."))))
             (\(e::SomeException) -> return (show e))

  where stmt = "(" ++ stmt' ++ ") >>= return . show :: IO String"
        ignoreUnit "()" = ""
        ignoreUnit x = x

-- | Compile the given expression and evaluate it.
runExpression :: String -> Ghc String
runExpression stmt' = do
  result <- gcatch (fmap Right (dynCompileExpr stmt))
                   (\(e::SomeException) -> return (Left e))
  case result of
    Left err -> return (show err)
    Right compiled ->
      gcatch (io (fromDyn compiled (return "Bad compile.")))
             (\(e::SomeException) -> return (show e))

  where stmt = "return (show (" ++ stmt' ++ ")) :: IO String"

-- | Short-hand utility.
io :: IO a -> Ghc a
io = liftIO
