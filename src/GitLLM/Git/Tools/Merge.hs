{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Merge (tools, handle, handleAbort, handleStatus, handleMergeBase) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_merge"
      "Merge a branch into the current branch"
      (mkSchema
        [ "branch" .= object [ "type" .= ("string" :: Text), "description" .= ("Branch to merge" :: Text) ]
        , "no_ff"  .= object [ "type" .= ("boolean" :: Text), "description" .= ("Create a merge commit even for fast-forward" :: Text) ]
        , "squash" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Squash the merge into a single commit" :: Text) ]
        , "message" .= object [ "type" .= ("string" :: Text), "description" .= ("Merge commit message" :: Text) ]
        ]
        ["branch"])
      mutating
  , mkToolDefA "git_merge_abort"
      "Abort an in-progress merge and restore the pre-merge state"
      (mkSchema [] [])
      mutating
  , mkToolDefA "git_merge_status"
      "Check if there are unmerged files (merge conflicts)"
      (mkSchema [] [])
      readOnly
  , mkToolDefA "git_merge_base"
      "Find the best common ancestor (merge base) between two commits or branches"
      (mkSchema
        [ "ref1" .= object [ "type" .= ("string" :: Text), "description" .= ("First ref (branch, commit, tag)" :: Text) ]
        , "ref2" .= object [ "type" .= ("string" :: Text), "description" .= ("Second ref (branch, commit, tag)" :: Text) ]
        ]
        ["ref1", "ref2"])
      readOnly
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params = case getTextParam "branch" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: branch"] True
  Just branch -> do
    let noffFlag   = if getBoolParam "no_ff" params == Just True then ["--no-ff"] else []
        squashFlag = if getBoolParam "squash" params == Just True then ["--squash"] else []
        msgFlag    = maybe [] (\m -> ["-m", textArg m]) (getTextParam "message" params)
    result <- runGit ctx (["merge"] ++ noffFlag ++ squashFlag ++ msgFlag ++ [textArg branch])
    gitResultToToolResult result

handleAbort :: GitContext -> Maybe Value -> IO ToolResult
handleAbort ctx _ = do
  result <- runGit ctx ["merge", "--abort"]
  gitResultToToolResult result

handleStatus :: GitContext -> Maybe Value -> IO ToolResult
handleStatus ctx _ = do
  result <- runGit ctx ["diff", "--name-only", "--diff-filter=U"]
  gitResultToToolResult result

handleMergeBase :: GitContext -> Maybe Value -> IO ToolResult
handleMergeBase ctx params =
  case (getTextParam "ref1" params, getTextParam "ref2" params) of
    (Just r1, Just r2) -> do
      result <- runGit ctx ["merge-base", textArg r1, textArg r2]
      gitResultToToolResult result
    _ -> pure $ ToolResult [TextContent "Missing required parameters: ref1, ref2"] True
