{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Hooks (tools, handleList) where

import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (listDirectory, doesFileExist)
import System.FilePath ((</>))
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Tools.Helpers


tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_hooks_list"
      "List available git hooks and which ones are installed"
      (mkSchema [] [])
      readOnly
  ]

handleList :: GitContext -> Maybe Value -> IO ToolResult
handleList ctx _ = do
  let hooksDir = gitRepoPath ctx </> ".git" </> "hooks"
  exists <- doesFileExist (hooksDir </> ".." </> "HEAD")
  if not exists
    then pure $ ToolResult [TextContent "Not a git repository"] True
    else do
      files <- listDirectory hooksDir
      let hookFiles = filter (not . isSample) files
          sampleFiles = filter isSample files
          output = T.unlines $
            ["Installed hooks:"] ++
            (if null hookFiles then ["  (none)"] else map (\f -> "  " <> T.pack f) hookFiles) ++
            ["", "Available samples:"] ++
            map (\f -> "  " <> T.pack f) sampleFiles
      pure $ ToolResult [TextContent output] False
  where
    isSample name = ".sample" `T.isSuffixOf` T.pack name
