{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Remote (tools, handleList, handleAdd, handleRemove, handleFetch, handlePull, handlePush, handleGetUrl, handleSetUrl, parseRemoteLines) where

import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as T
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_remote_list"
      "List configured remote repositories with their URLs"
      (mkSchema [outputParam] [])
      readOnly
  , mkToolDefA "git_remote_add"
      "Add a new remote repository"
      (mkSchema
        [ "name" .= object [ "type" .= ("string" :: Text), "description" .= ("Remote name" :: Text) ]
        , "url"  .= object [ "type" .= ("string" :: Text), "description" .= ("Remote URL" :: Text) ]
        ]
        ["name", "url"])
      mutating
  , mkToolDefA "git_remote_remove"
      "Remove a remote repository"
      (mkSchema
        [ "name" .= object [ "type" .= ("string" :: Text), "description" .= ("Remote name to remove" :: Text) ] ]
        ["name"])
      destructive
  , mkToolDefA "git_fetch"
      "Download objects and refs from a remote repository"
      (mkSchema
        [ "remote" .= object [ "type" .= ("string" :: Text), "description" .= ("Remote to fetch from" :: Text), "default" .= ("origin" :: Text) ]
        , "prune"  .= object [ "type" .= ("boolean" :: Text), "description" .= ("Prune remote-tracking branches no longer on remote" :: Text) ]
        , "all"    .= object [ "type" .= ("boolean" :: Text), "description" .= ("Fetch all remotes" :: Text) ]
        ]
        [])
      mutating
  , mkToolDefA "git_pull"
      "Fetch and integrate changes from a remote branch"
      (mkSchema
        [ "remote" .= object [ "type" .= ("string" :: Text), "description" .= ("Remote name" :: Text), "default" .= ("origin" :: Text) ]
        , "branch" .= object [ "type" .= ("string" :: Text), "description" .= ("Branch to pull" :: Text) ]
        , "rebase" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Rebase instead of merge" :: Text) ]
        ]
        [])
      mutating
  , mkToolDefA "git_push"
      "Push local commits to a remote repository"
      (mkSchema
        [ "remote"       .= object [ "type" .= ("string" :: Text), "description" .= ("Remote name" :: Text), "default" .= ("origin" :: Text) ]
        , "branch"       .= object [ "type" .= ("string" :: Text), "description" .= ("Branch to push" :: Text) ]
        , "set_upstream" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Set upstream tracking" :: Text) ]
        , "force"        .= object [ "type" .= ("boolean" :: Text), "description" .= ("Force push (overwrites remote history — use force_with_lease instead when possible)" :: Text) ]
        , "force_with_lease" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Force push only if remote ref matches local expectation (safer than force)" :: Text) ]
        , "tags"         .= object [ "type" .= ("boolean" :: Text), "description" .= ("Push tags" :: Text) ]
        ]
        [])
      destructive
  , mkToolDefA "git_remote_get_url"
      "Get the URL of a remote"
      (mkSchema
        [ "name" .= object [ "type" .= ("string" :: Text), "description" .= ("Remote name" :: Text) ]
        , "push" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Query the push URL instead of fetch URL" :: Text) ]
        ]
        ["name"])
      readOnly
  , mkToolDefA "git_remote_set_url"
      "Change the URL of an existing remote"
      (mkSchema
        [ "name" .= object [ "type" .= ("string" :: Text), "description" .= ("Remote name" :: Text) ]
        , "url"  .= object [ "type" .= ("string" :: Text), "description" .= ("New URL for the remote" :: Text) ]
        , "push" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Set the push URL instead of fetch URL" :: Text) ]
        ]
        ["name", "url"])
      mutating
  ]

handleList :: GitContext -> Maybe Value -> IO ToolResult
handleList ctx params
  | wantsJson params = do
      result <- runGit ctx ["remote", "-v"]
      pure $ case result of
        Right out -> jsonResult $ object ["remotes" .= parseRemoteLines out]
        Left (GitProcessError _ err) -> ToolResult [TextContent err] True
        Left (GitParseError err)     -> ToolResult [TextContent err] True
        Left (GitValidationError err)-> ToolResult [TextContent err] True
        Left (GitTimeoutError secs)  -> ToolResult [TextContent ("Command timed out after " <> T.pack (show secs) <> " seconds")] True
  | otherwise = do
      result <- runGit ctx ["remote", "-v"]
      gitResultToToolResult result

parseRemoteLines :: Text -> [Value]
parseRemoteLines raw =
  -- git remote -v outputs: name\turl (type)
  -- Deduplicate by keeping only (fetch) entries
  [ parseRemoteLine l | l <- T.lines raw, not (T.null l), T.isSuffixOf "(fetch)" l ]

parseRemoteLine :: Text -> Value
parseRemoteLine line =
  case T.words line of
    (name:url:_) -> object
      [ "name" .= name
      , "url"  .= url
      ]
    _ -> object ["raw" .= line]

handleAdd :: GitContext -> Maybe Value -> IO ToolResult
handleAdd ctx params =
  case (getTextParam "name" params, getTextParam "url" params) of
    (Just name, Just url) -> do
      result <- runGit ctx ["remote", "add", textArg name, textArg url]
      gitResultToToolResult result
    _ -> pure $ ToolResult [TextContent "Missing required parameters: name, url"] True

handleRemove :: GitContext -> Maybe Value -> IO ToolResult
handleRemove ctx params = case getTextParam "name" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: name"] True
  Just name -> do
    result <- runGit ctx ["remote", "remove", textArg name]
    gitResultToToolResult result

handleFetch :: GitContext -> Maybe Value -> IO ToolResult
handleFetch ctx params = do
  let allFlag   = if getBoolParam "all" params == Just True then ["--all"] else []
      pruneFlag = if getBoolParam "prune" params == Just True then ["--prune"] else []
      remote    = maybe [] (\r -> [textArg r]) (getTextParam "remote" params)
  result <- runGit ctx (["fetch"] ++ allFlag ++ pruneFlag ++ remote)
  gitResultToToolResult result

handlePull :: GitContext -> Maybe Value -> IO ToolResult
handlePull ctx params = do
  let rebaseFlag = if getBoolParam "rebase" params == Just True then ["--rebase"] else []
      remote     = maybe [] (\r -> [textArg r]) (getTextParam "remote" params)
      branch     = maybe [] (\b -> [textArg b]) (getTextParam "branch" params)
  result <- runGit ctx (["pull"] ++ rebaseFlag ++ remote ++ branch)
  gitResultToToolResult result

handlePush :: GitContext -> Maybe Value -> IO ToolResult
handlePush ctx params = do
  let upstreamFlag = if getBoolParam "set_upstream" params == Just True then ["-u"] else []
      forceFlag    = if getBoolParam "force_with_lease" params == Just True then ["--force-with-lease"]
                     else if getBoolParam "force" params == Just True then ["--force"] else []
      tagsFlag     = if getBoolParam "tags" params == Just True then ["--tags"] else []
      remote       = maybe [] (\r -> [textArg r]) (getTextParam "remote" params)
      branch       = maybe [] (\b -> [textArg b]) (getTextParam "branch" params)
  result <- runGit ctx (["push"] ++ upstreamFlag ++ forceFlag ++ tagsFlag ++ remote ++ branch)
  gitResultToToolResult result

handleGetUrl :: GitContext -> Maybe Value -> IO ToolResult
handleGetUrl ctx params = case getTextParam "name" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: name"] True
  Just name -> do
    let pushFlag = if getBoolParam "push" params == Just True then ["--push"] else []
    result <- runGit ctx (["remote", "get-url"] ++ pushFlag ++ [textArg name])
    gitResultToToolResult result

handleSetUrl :: GitContext -> Maybe Value -> IO ToolResult
handleSetUrl ctx params =
  case (getTextParam "name" params, getTextParam "url" params) of
    (Just name, Just url) -> do
      let pushFlag = if getBoolParam "push" params == Just True then ["--push"] else []
      result <- runGit ctx (["remote", "set-url"] ++ pushFlag ++ [textArg name, textArg url])
      gitResultToToolResult result
    _ -> pure $ ToolResult [TextContent "Missing required parameters: name, url"] True
