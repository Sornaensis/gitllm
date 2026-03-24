{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Runner
  ( runGit
  , runGitWithInput
  , textArg
  ) where

import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Encoding.Error as TEE
import System.Exit (ExitCode(..))
import System.Process.Typed

import GitLLM.Git.Types

-- | Run a git command in the given repository path and return stdout as Text.
runGit :: GitContext -> [String] -> IO GitResult
runGit ctx args = do
  let pc = setWorkingDir (gitRepoPath ctx)
         $ proc "git" args
  (exitCode, out, err) <- readProcess pc
  case exitCode of
    ExitSuccess   -> pure $ Right (decodeOutput out)
    ExitFailure c -> pure $ Left $ GitProcessError c (decodeOutput err)

-- | Run a git command with stdin input.
runGitWithInput :: GitContext -> [String] -> Text -> IO GitResult
runGitWithInput ctx args input = do
  let pc = setWorkingDir (gitRepoPath ctx)
         $ setStdin (byteStringInput (BL.fromStrict $ TE.encodeUtf8 input))
         $ proc "git" args
  (exitCode, out, err) <- readProcess pc
  case exitCode of
    ExitSuccess   -> pure $ Right (decodeOutput out)
    ExitFailure c -> pure $ Left $ GitProcessError c (decodeOutput err)

-- | Decode process output (lazy ByteString) to Text, replacing invalid UTF-8.
decodeOutput :: BL.ByteString -> Text
decodeOutput = TE.decodeUtf8With TEE.lenientDecode . BL.toStrict

-- | Convert Text to a command argument.
textArg :: Text -> String
textArg = T.unpack
