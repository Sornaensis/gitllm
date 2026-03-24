{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Staging (tools, handleAdd, handleAddAll, handleRestore, handleRestoreStaged) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_add"
      "Stage specific files for the next commit"
      (mkSchema
        [ "paths" .= object [ "type" .= ("array" :: Text), "items" .= object ["type" .= ("string" :: Text)], "description" .= ("File paths to stage" :: Text) ] ]
        ["paths"])
      mutating
  , mkToolDefA "git_add_all"
      "Stage all changes (new, modified, deleted) in the working tree"
      (mkSchema [] [])
      mutating
  , mkToolDefA "git_restore"
      "Discard changes in working tree for specified files"
      (mkSchema
        [ "paths" .= object [ "type" .= ("array" :: Text), "items" .= object ["type" .= ("string" :: Text)], "description" .= ("File paths to restore" :: Text) ] ]
        ["paths"])
      mutating
  , mkToolDefA "git_restore_staged"
      "Unstage files (move from index back to working tree)"
      (mkSchema
        [ "paths" .= object [ "type" .= ("array" :: Text), "items" .= object ["type" .= ("string" :: Text)], "description" .= ("File paths to unstage" :: Text) ] ]
        ["paths"])
      mutating
  ]

handleAdd :: GitContext -> Maybe Value -> IO ToolResult
handleAdd ctx params = case getTextListParam "paths" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: paths"] True
  Just paths -> do
    result <- runGit ctx (["add", "--"] ++ map textArg paths)
    gitResultToToolResult result

handleAddAll :: GitContext -> Maybe Value -> IO ToolResult
handleAddAll ctx _ = do
  result <- runGit ctx ["add", "-A"]
  gitResultToToolResult result

handleRestore :: GitContext -> Maybe Value -> IO ToolResult
handleRestore ctx params = case getTextListParam "paths" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: paths"] True
  Just paths -> do
    result <- runGit ctx (["restore", "--"] ++ map textArg paths)
    gitResultToToolResult result

handleRestoreStaged :: GitContext -> Maybe Value -> IO ToolResult
handleRestoreStaged ctx params = case getTextListParam "paths" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: paths"] True
  Just paths -> do
    result <- runGit ctx (["restore", "--staged", "--"] ++ map textArg paths)
    gitResultToToolResult result
