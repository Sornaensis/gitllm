{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Status (tools, handle, handleShort) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_status"
      "Show the working tree status. Returns staged, unstaged, and untracked files"
      (mkSchema [] [])
      readOnly
  , mkToolDefA "git_status_short"
      "Show concise working tree status in short format. Returns XY path lines"
      (mkSchema [] [])
      readOnly
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx _ = do
  result <- runGit ctx ["status"]
  pure $ case result of
    Right out -> ToolResult [TextContent out] False
    Left (GitProcessError _ err) -> ToolResult [TextContent err] True
    Left (GitParseError err) -> ToolResult [TextContent err] True
    Left (GitValidationError err) -> ToolResult [TextContent err] True

handleShort :: GitContext -> Maybe Value -> IO ToolResult
handleShort ctx _ = do
  result <- runGit ctx ["status", "--short", "--branch"]
  pure $ case result of
    Right out -> ToolResult [TextContent out] False
    Left (GitProcessError _ err) -> ToolResult [TextContent err] True
    Left (GitParseError err) -> ToolResult [TextContent err] True
    Left (GitValidationError err) -> ToolResult [TextContent err] True
