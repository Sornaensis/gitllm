{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Runner
  ( runGit
  , runGitWithInput
  , textArg
  , defaultTimeout
  ) where

import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Encoding.Error as TEE
import System.Exit (ExitCode(..))
import System.Process.Typed
import System.Timeout (timeout)

import GitLLM.Git.Types

-- | Default timeout for git commands: 30 seconds.
defaultTimeout :: Int
defaultTimeout = 30

-- | Run a git command in the given repository path and return stdout as Text.
-- Enforces a configurable timeout (default 30s).
runGit :: GitContext -> [String] -> IO GitResult
runGit ctx args = do
  let pc = setWorkingDir (gitRepoPath ctx)
         $ proc "git" args
      secs = maybe defaultTimeout id (gitTimeout ctx)
  mResult <- timeout (secs * 1000000) (readProcess pc)
  case mResult of
    Nothing -> pure $ Left $ GitTimeoutError secs
    Just (exitCode, out, err) ->
      case exitCode of
        ExitSuccess   -> pure $ Right (decodeOutput out)
        ExitFailure c -> pure $ Left $ GitProcessError c (decodeOutput err)

-- | Run a git command with stdin input.
-- Enforces a configurable timeout (default 30s).
runGitWithInput :: GitContext -> [String] -> Text -> IO GitResult
runGitWithInput ctx args input = do
  let pc = setWorkingDir (gitRepoPath ctx)
         $ setStdin (byteStringInput (BL.fromStrict $ TE.encodeUtf8 input))
         $ proc "git" args
      secs = maybe defaultTimeout id (gitTimeout ctx)
  mResult <- timeout (secs * 1000000) (readProcess pc)
  case mResult of
    Nothing -> pure $ Left $ GitTimeoutError secs
    Just (exitCode, out, err) ->
      case exitCode of
        ExitSuccess   -> pure $ Right (decodeOutput out)
        ExitFailure c -> pure $ Left $ GitProcessError c (decodeOutput err)

-- | Decode process output (lazy ByteString) to Text, replacing invalid UTF-8.
decodeOutput :: BL.ByteString -> Text
decodeOutput = TE.decodeUtf8With TEE.lenientDecode . BL.toStrict

-- | Convert Text to a command argument.
textArg :: Text -> String
textArg = T.unpack
