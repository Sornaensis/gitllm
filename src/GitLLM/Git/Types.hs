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
  } deriving (Show, Eq)

-- | Errors that can occur during git operations.
data GitError
  = GitProcessError Int Text  -- ^ Exit code and stderr
  | GitParseError Text        -- ^ Failed to parse git output
  | GitValidationError Text   -- ^ Invalid parameters
  deriving (Show, Eq)

-- | Result of a git operation.
type GitResult = Either GitError Text
