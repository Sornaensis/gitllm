{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Submodule (tools, handleList, handleAdd, handleUpdate, handleSync) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_submodule_list"
      "List all submodules and their current status"
      (mkSchema [] [])
      readOnly
  , mkToolDefA "git_submodule_add"
      "Add a new submodule to the repository"
      (mkSchema
        [ "url" .= object [ "type" .= ("string" :: Text), "description" .= ("URL of the submodule repository" :: Text) ]
        , "path" .= object [ "type" .= ("string" :: Text), "description" .= ("Local path for the submodule" :: Text) ]
        , "branch" .= object [ "type" .= ("string" :: Text), "description" .= ("Branch to track" :: Text) ]
        ]
        ["url"])
      mutating
  , mkToolDefA "git_submodule_update"
      "Update submodules to the commit recorded in the superproject"
      (mkSchema
        [ "init" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Initialize uninitialized submodules" :: Text) ]
        , "recursive" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Update nested submodules recursively" :: Text) ]
        , "remote" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Fetch the latest from remote instead of recorded commit" :: Text) ]
        ]
        [])
      mutating
  , mkToolDefA "git_submodule_sync"
      "Synchronize submodule URL configuration"
      (mkSchema
        [ "recursive" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Sync nested submodules" :: Text) ] ]
        [])
      mutating
  ]

handleList :: GitContext -> Maybe Value -> IO ToolResult
handleList ctx _ = do
  result <- runGit ctx ["submodule", "status"]
  gitResultToToolResult result

handleAdd :: GitContext -> Maybe Value -> IO ToolResult
handleAdd ctx params = case getTextParam "url" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: url"] True
  Just url -> do
    let pathArg   = maybe [] (\p -> [textArg p]) (getTextParam "path" params)
        branchArg = maybe [] (\b -> ["-b", textArg b]) (getTextParam "branch" params)
    result <- runGit ctx (["submodule", "add"] ++ branchArg ++ [textArg url] ++ pathArg)
    gitResultToToolResult result

handleUpdate :: GitContext -> Maybe Value -> IO ToolResult
handleUpdate ctx params = do
  let initFlag      = if getBoolParam "init" params == Just True then ["--init"] else []
      recursiveFlag = if getBoolParam "recursive" params == Just True then ["--recursive"] else []
      remoteFlag    = if getBoolParam "remote" params == Just True then ["--remote"] else []
  result <- runGit ctx (["submodule", "update"] ++ initFlag ++ recursiveFlag ++ remoteFlag)
  gitResultToToolResult result

handleSync :: GitContext -> Maybe Value -> IO ToolResult
handleSync ctx params = do
  let recursiveFlag = if getBoolParam "recursive" params == Just True then ["--recursive"] else []
  result <- runGit ctx (["submodule", "sync"] ++ recursiveFlag)
  gitResultToToolResult result
