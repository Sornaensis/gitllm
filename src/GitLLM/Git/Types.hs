{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Types
  ( GitContext(..)
  , GitError(..)
  , GitResult
  , ServerState(..)
  ) where

import Data.IORef (IORef)
import Data.Text (Text)

-- | Context for executing git commands.
data GitContext = GitContext
  { gitRepoPath :: FilePath
  , gitTimeout  :: Maybe Int  -- ^ Command timeout in seconds (Nothing = 30s default)
  } deriving (Show, Eq)

-- | Mutable server state shared across requests.
-- The repo path starts as Nothing; the LLM must call git_set_repo to set it.
data ServerState = ServerState
  { stateRepoPath :: IORef (Maybe FilePath)
  , stateTimeout  :: Maybe Int
  }

-- | Errors that can occur during git operations.
data GitError
  = GitProcessError Int Text  -- ^ Exit code and stderr
  | GitParseError Text        -- ^ Failed to parse git output
  | GitValidationError Text   -- ^ Invalid parameters
  | GitTimeoutError Int        -- ^ Command exceeded timeout (seconds)
  deriving (Show, Eq)

-- | Result of a git operation.
type GitResult = Either GitError Text
