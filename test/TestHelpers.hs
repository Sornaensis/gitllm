{-# LANGUAGE OverloadedStrings #-}

-- | Shared test utilities: temp git repo setup, file creation helpers.
module TestHelpers
  ( withTempGitRepo
  , withTempServerState
  , createRepoFile
  , commitAll
  ) where

import Control.Monad (void)
import Data.IORef (newIORef)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (callProcess)

import GitLLM.Git.Types (GitContext(..), ServerState(..))
import GitLLM.Git.Runner (runGit)

-- | Create a temporary git repo with user config, run the action, then clean up.
withTempGitRepo :: (GitContext -> IO a) -> IO a
withTempGitRepo action = withSystemTempDirectory "gitllm-test" $ \dir -> do
  callProcess "git" ["init", dir]
  callProcess "git" ["-C", dir, "config", "user.email", "test@test.com"]
  callProcess "git" ["-C", dir, "config", "user.name", "Test User"]
  action (GitContext dir Nothing)

-- | Create a temporary git repo and return a ServerState with the repo path already set.
withTempServerState :: (ServerState -> GitContext -> IO a) -> IO a
withTempServerState action = withSystemTempDirectory "gitllm-test" $ \dir -> do
  callProcess "git" ["init", dir]
  callProcess "git" ["-C", dir, "config", "user.email", "test@test.com"]
  callProcess "git" ["-C", dir, "config", "user.name", "Test User"]
  ref <- newIORef (Just dir)
  let state = ServerState ref Nothing
      ctx   = GitContext dir Nothing
  action state ctx

-- | Write a file into the test repo.
createRepoFile :: GitContext -> FilePath -> String -> IO ()
createRepoFile ctx name content = writeFile (gitRepoPath ctx </> name) content

-- | Stage everything and commit with the given message.
commitAll :: GitContext -> String -> IO ()
commitAll ctx msg = do
  void $ runGit ctx ["add", "-A"]
  void $ runGit ctx ["commit", "-m", msg]
