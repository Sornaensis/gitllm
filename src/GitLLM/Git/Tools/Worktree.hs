{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Worktree (tools, handleList, handleAdd, handleRemove) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_worktree_list"
      "List all linked working trees"
      (mkSchema [] [])
      readOnly
  , mkToolDefA "git_worktree_add"
      "Create a new working tree linked to this repository"
      (mkSchema
        [ "path" .= object [ "type" .= ("string" :: Text), "description" .= ("Path for the new working tree" :: Text) ]
        , "branch" .= object [ "type" .= ("string" :: Text), "description" .= ("Branch to checkout in the worktree" :: Text) ]
        , "new_branch" .= object [ "type" .= ("string" :: Text), "description" .= ("Create a new branch for the worktree" :: Text) ]
        ]
        ["path"])
      mutating
  , mkToolDefA "git_worktree_remove"
      "Remove a linked working tree"
      (mkSchema
        [ "path" .= object [ "type" .= ("string" :: Text), "description" .= ("Path of the working tree to remove" :: Text) ]
        , "force" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Force removal even with modifications" :: Text) ]
        ]
        ["path"])
      destructive
  ]

handleList :: GitContext -> Maybe Value -> IO ToolResult
handleList ctx _ = do
  result <- runGit ctx ["worktree", "list"]
  gitResultToToolResult result

handleAdd :: GitContext -> Maybe Value -> IO ToolResult
handleAdd ctx params = case getTextParam "path" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: path"] True
  Just path -> do
    let branchArgs = case getTextParam "new_branch" params of
          Just nb -> ["-b", textArg nb]
          Nothing -> maybe [] (\b -> [textArg b]) (getTextParam "branch" params)
    result <- runGit ctx (["worktree", "add", textArg path] ++ branchArgs)
    gitResultToToolResult result

handleRemove :: GitContext -> Maybe Value -> IO ToolResult
handleRemove ctx params = case getTextParam "path" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: path"] True
  Just path -> do
    let forceFlag = if getBoolParam "force" params == Just True then ["--force"] else []
    result <- runGit ctx (["worktree", "remove"] ++ forceFlag ++ [textArg path])
    gitResultToToolResult result
