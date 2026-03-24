{-# LANGUAGE OverloadedStrings #-}

-- | Shared test utilities: temp git repo setup, file creation helpers.
module TestHelpers
  ( withTempGitRepo
  , createRepoFile
  , commitAll
  ) where

import Control.Monad (void)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess)

import GitLLM.Git.Types (GitContext(..))
import GitLLM.Git.Runner (runGit)

-- | Create a temporary git repo with user config, run the action, then clean up.
withTempGitRepo :: (GitContext -> IO a) -> IO a
withTempGitRepo action = withSystemTempDirectory "gitllm-test" $ \dir -> do
  callProcess "git" ["init", dir]
  callProcess "git" ["-C", dir, "config", "user.email", "test@test.com"]
  callProcess "git" ["-C", dir, "config", "user.name", "Test User"]
  action (GitContext dir Nothing)

-- | Write a file into the test repo.
createRepoFile :: GitContext -> FilePath -> String -> IO ()
createRepoFile ctx name content = writeFile (gitRepoPath ctx </> name) content

-- | Stage everything and commit with the given message.
commitAll :: GitContext -> String -> IO ()
commitAll ctx msg = do
  void $ runGit ctx ["add", "-A"]
  void $ runGit ctx ["commit", "-m", msg]
