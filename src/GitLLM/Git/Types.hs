{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Types
  ( GitContext(..)
  , GitError(..)
  , GitResult
  ) where

import Data.Text (Text)

-- | Context for executing git commands.
data GitContext = GitContext
  { gitRepoPath :: FilePath
  , gitTimeout  :: Maybe Int  -- ^ Command timeout in seconds (Nothing = 30s default)
  } deriving (Show, Eq)

-- | Errors that can occur during git operations.
data GitError
  = GitProcessError Int Text  -- ^ Exit code and stderr
  | GitParseError Text        -- ^ Failed to parse git output
  | GitValidationError Text   -- ^ Invalid parameters
  | GitTimeoutError Int        -- ^ Command exceeded timeout (seconds)
  deriving (Show, Eq)

-- | Result of a git operation.
type GitResult = Either GitError Text
