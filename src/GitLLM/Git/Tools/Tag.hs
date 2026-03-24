{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Tag (tools, handleList, handleCreate, handleDelete) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_tag_list"
      "List all tags, optionally filtered by pattern"
      (mkSchema
        [ "pattern" .= object [ "type" .= ("string" :: Text), "description" .= ("Glob pattern to filter tags (e.g. 'v1.*')" :: Text) ]
        , "sort" .= object [ "type" .= ("string" :: Text), "description" .= ("Sort key (e.g. '-creatordate' for newest first)" :: Text) ]
        ]
        [])
      readOnly
  , mkToolDefA "git_tag_create"
      "Create a new tag (lightweight or annotated)"
      (mkSchema
        [ "name" .= object [ "type" .= ("string" :: Text), "description" .= ("Tag name" :: Text) ]
        , "message" .= object [ "type" .= ("string" :: Text), "description" .= ("Tag message (creates annotated tag)" :: Text) ]
        , "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Commit to tag" :: Text), "default" .= ("HEAD" :: Text) ]
        ]
        ["name"])
      mutating
  , mkToolDefA "git_tag_delete"
      "Delete a tag"
      (mkSchema
        [ "name" .= object [ "type" .= ("string" :: Text), "description" .= ("Tag name to delete" :: Text) ] ]
        ["name"])
      destructive
  ]

handleList :: GitContext -> Maybe Value -> IO ToolResult
handleList ctx params = do
  let patternArg = maybe [] (\p -> ["-l", textArg p]) (getTextParam "pattern" params)
      sortArg    = maybe [] (\s -> ["--sort=" ++ textArg s]) (getTextParam "sort" params)
  result <- runGit ctx (["tag"] ++ sortArg ++ patternArg)
  gitResultToToolResult result

handleCreate :: GitContext -> Maybe Value -> IO ToolResult
handleCreate ctx params = case getTextParam "name" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: name"] True
  Just name -> do
    let msgFlag = maybe [] (\m -> ["-a", "-m", textArg m]) (getTextParam "message" params)
        ref     = maybe [] (\r -> [textArg r]) (getTextParam "ref" params)
    result <- runGit ctx (["tag"] ++ msgFlag ++ [textArg name] ++ ref)
    gitResultToToolResult result

handleDelete :: GitContext -> Maybe Value -> IO ToolResult
handleDelete ctx params = case getTextParam "name" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: name"] True
  Just name -> do
    result <- runGit ctx ["tag", "-d", textArg name]
    gitResultToToolResult result
