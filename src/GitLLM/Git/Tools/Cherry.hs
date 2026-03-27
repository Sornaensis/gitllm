{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Cherry (tools, handle, handleAbort, handleRevert) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_cherry_pick"
      "Apply the changes from one or more existing commits"
      (mkSchema
        [ "commits" .= object [ "type" .= ("array" :: Text), "items" .= object ["type" .= ("string" :: Text)], "description" .= ("Commit SHAs to cherry-pick" :: Text) ]
        , "no_commit" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Apply changes without creating commits" :: Text) ]
        ]
        ["commits"])
      mutating
  , mkToolDefA "git_cherry_pick_abort"
      "Abort an in-progress cherry-pick"
      (mkSchema [] [])
      mutating
  , mkToolDefA "git_revert"
      "Revert one or more existing commits, creating new commits that undo the changes"
      (mkSchema
        [ "commits" .= object [ "type" .= ("array" :: Text), "items" .= object ["type" .= ("string" :: Text)], "description" .= ("Commit SHAs to revert" :: Text) ]
        , "no_commit" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Apply reverts to working tree without creating commits" :: Text) ]
        ]
        ["commits"])
      mutating
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params = case getTextListParam "commits" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: commits"] True
  Just commits -> do
    let noCommitFlag = if getBoolParam "no_commit" params == Just True then ["-n"] else []
    result <- runGit ctx (["cherry-pick"] ++ noCommitFlag ++ map textArg commits)
    gitResultToToolResult result

handleAbort :: GitContext -> Maybe Value -> IO ToolResult
handleAbort ctx _ = do
  result <- runGit ctx ["cherry-pick", "--abort"]
  gitResultToToolResult result

handleRevert :: GitContext -> Maybe Value -> IO ToolResult
handleRevert ctx params = case getTextListParam "commits" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: commits"] True
  Just commits -> do
    let noCommitFlag = if getBoolParam "no_commit" params == Just True then ["--no-commit"] else []
    result <- runGit ctx (["revert"] ++ noCommitFlag ++ map textArg commits)
    gitResultToToolResult result
