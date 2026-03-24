{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Branch
  ( tools, handleList, handleCreate, handleDelete, handleRename
  , handleCurrent, handleCheckout, handleSwitch
  , parseBranchLines
  ) where

import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as T
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_branch_list"
      "List all local and optionally remote branches"
      (mkSchema
        [ "all" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Include remote-tracking branches" :: Text) ]
        , "verbose" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show last commit on each branch" :: Text) ]
        , outputParam
        ]
        [])
      readOnly
  , mkToolDefA "git_branch_create"
      "Create a new branch at the specified starting point"
      (mkSchema
        [ "name" .= object [ "type" .= ("string" :: Text), "description" .= ("Name for the new branch" :: Text) ]
        , "start_point" .= object [ "type" .= ("string" :: Text), "description" .= ("Commit/branch to start from" :: Text), "default" .= ("HEAD" :: Text) ]
        ]
        ["name"])
      mutating
  , mkToolDefA "git_branch_delete"
      "Delete a branch (fails if not fully merged unless force is set)"
      (mkSchema
        [ "name" .= object [ "type" .= ("string" :: Text), "description" .= ("Branch to delete" :: Text) ]
        , "force" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Force delete even if not merged" :: Text) ]
        ]
        ["name"])
      destructive
  , mkToolDefA "git_branch_rename"
      "Rename a branch"
      (mkSchema
        [ "old_name" .= object [ "type" .= ("string" :: Text), "description" .= ("Current branch name" :: Text) ]
        , "new_name" .= object [ "type" .= ("string" :: Text), "description" .= ("New branch name" :: Text) ]
        ]
        ["old_name", "new_name"])
      mutating
  , mkToolDefA "git_branch_current"
      "Show the name of the current branch"
      (mkSchema [] [])
      readOnly
  , mkToolDefA "git_checkout"
      "Switch branches or restore working tree files. Legacy command — prefer git_switch for branches and git_restore for files"
      (mkSchema
        [ "target" .= object [ "type" .= ("string" :: Text), "description" .= ("Branch, tag, or commit to checkout" :: Text) ]
        , "create" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Create a new branch (-b flag)" :: Text) ]
        ]
        ["target"])
      mutating
  , mkToolDefA "git_switch"
      "Switch to a branch (preferred over git_checkout for branch switching)"
      (mkSchema
        [ "branch" .= object [ "type" .= ("string" :: Text), "description" .= ("Branch to switch to" :: Text) ]
        , "create" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Create the branch if it doesn't exist" :: Text) ]
        ]
        ["branch"])
      mutating
  ]

handleList :: GitContext -> Maybe Value -> IO ToolResult
handleList ctx params
  | wantsJson params = do
      let allFlag = if getBoolParam "all" params == Just True then ["-a"] else []
          fmt = "--format=%(refname:short)\t%(objectname:short)\t%(HEAD)\t%(upstream:short)\t%(subject)"
      result <- runGit ctx (["branch", fmt] ++ allFlag)
      pure $ case result of
        Right out -> jsonResult $ object ["branches" .= parseBranchLines out]
        Left (GitProcessError _ err) -> ToolResult [TextContent err] True
        Left (GitParseError err)     -> ToolResult [TextContent err] True
        Left (GitValidationError err)-> ToolResult [TextContent err] True
        Left (GitTimeoutError secs)  -> ToolResult [TextContent ("Command timed out after " <> T.pack (show secs) <> " seconds")] True
  | otherwise = do
      let allFlag = if getBoolParam "all" params == Just True then ["-a"] else []
          verbose = if getBoolParam "verbose" params == Just True then ["-v"] else []
      result <- runGit ctx (["branch"] ++ allFlag ++ verbose)
      gitResultToToolResult result

parseBranchLines :: Text -> [Value]
parseBranchLines raw =
  [ parseBranchLine l | l <- T.lines raw, not (T.null l) ]

parseBranchLine :: Text -> Value
parseBranchLine line =
  case T.splitOn "\t" line of
    [name, sha, headMark, upstream, subject] -> object
      [ "name"     .= name
      , "sha"      .= sha
      , "current"  .= (headMark == "*")
      , "upstream" .= if T.null upstream then Null else toJSON upstream
      , "subject"  .= subject
      ]
    _ -> object ["raw" .= line]

handleCreate :: GitContext -> Maybe Value -> IO ToolResult
handleCreate ctx params = case getTextParam "name" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: name"] True
  Just name -> do
    let startPt = maybe [] (\s -> [textArg s]) (getTextParam "start_point" params)
    result <- runGit ctx (["branch", textArg name] ++ startPt)
    gitResultToToolResult result

handleDelete :: GitContext -> Maybe Value -> IO ToolResult
handleDelete ctx params = case getTextParam "name" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: name"] True
  Just name -> do
    let flag = if getBoolParam "force" params == Just True then "-D" else "-d"
    result <- runGit ctx ["branch", flag, textArg name]
    gitResultToToolResult result

handleRename :: GitContext -> Maybe Value -> IO ToolResult
handleRename ctx params =
  case (getTextParam "old_name" params, getTextParam "new_name" params) of
    (Just old, Just new) -> do
      result <- runGit ctx ["branch", "-m", textArg old, textArg new]
      gitResultToToolResult result
    _ -> pure $ ToolResult [TextContent "Missing required parameters: old_name, new_name"] True

handleCurrent :: GitContext -> Maybe Value -> IO ToolResult
handleCurrent ctx _ = do
  result <- runGit ctx ["branch", "--show-current"]
  gitResultToToolResult result

handleCheckout :: GitContext -> Maybe Value -> IO ToolResult
handleCheckout ctx params = case getTextParam "target" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: target"] True
  Just target -> do
    let createFlag = if getBoolParam "create" params == Just True then ["-b"] else []
    result <- runGit ctx (["checkout"] ++ createFlag ++ [textArg target])
    gitResultToToolResult result

handleSwitch :: GitContext -> Maybe Value -> IO ToolResult
handleSwitch ctx params = case getTextParam "branch" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: branch"] True
  Just branch -> do
    let createFlag = if getBoolParam "create" params == Just True then ["-c"] else []
    result <- runGit ctx (["switch"] ++ createFlag ++ [textArg branch])
    gitResultToToolResult result
