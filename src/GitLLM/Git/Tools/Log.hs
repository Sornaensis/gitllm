{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Log (tools, handle, handleOneline, handleFile, handleGraph) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_log"
      "Show commit log with full details. Returns multiline commit entries"
      (mkSchema
        [ "max_count" .= object [ "type" .= ("integer" :: Text), "description" .= ("Maximum number of commits to show" :: Text) ]
        , "author" .= object [ "type" .= ("string" :: Text), "description" .= ("Filter by author pattern" :: Text) ]
        , "since" .= object [ "type" .= ("string" :: Text), "description" .= ("Show commits after date (e.g. '2 weeks ago')" :: Text) ]
        , "until" .= object [ "type" .= ("string" :: Text), "description" .= ("Show commits before date" :: Text) ]
        ]
        [])
      readOnly
  , mkToolDefA "git_log_oneline"
      "Show commit log in compact format. Returns one line per commit: SHA title"
      (mkSchema
        [ "max_count" .= object [ "type" .= ("integer" :: Text), "description" .= ("Maximum number of commits" :: Text) ] ]
        [])
      readOnly
  , mkToolDefA "git_log_file"
      "Show commit log for a specific file, including renames"
      (mkSchema
        [ "path" .= object [ "type" .= ("string" :: Text), "description" .= ("File path to show history for" :: Text) ] ]
        ["path"])
      readOnly
  , mkToolDefA "git_log_graph"
      "Show commit log as an ASCII graph with branch topology"
      (mkSchema
        [ "max_count" .= object [ "type" .= ("integer" :: Text), "description" .= ("Maximum number of commits" :: Text) ]
        , "all" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show all branches" :: Text) ]
        ]
        [])
      readOnly
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params = do
  let args = ["log"] ++ buildLogArgs params
  result <- runGit ctx args
  gitResultToToolResult result

handleOneline :: GitContext -> Maybe Value -> IO ToolResult
handleOneline ctx params = do
  let args = ["log", "--oneline"] ++ buildCountArg params
  result <- runGit ctx args
  gitResultToToolResult result

handleFile :: GitContext -> Maybe Value -> IO ToolResult
handleFile ctx params = do
  case getTextParam "path" params of
    Nothing -> pure $ ToolResult [TextContent "Missing required parameter: path"] True
    Just path -> do
      result <- runGit ctx ["log", "--follow", "--", textArg path]
      gitResultToToolResult result

handleGraph :: GitContext -> Maybe Value -> IO ToolResult
handleGraph ctx params = do
  let args = ["log", "--graph", "--oneline", "--decorate"] ++ buildCountArg params ++ allFlag params
  result <- runGit ctx args
  gitResultToToolResult result

-- Helpers
buildLogArgs :: Maybe Value -> [String]
buildLogArgs params = buildCountArg params ++ authorArg params ++ sinceArg params ++ untilArg params

buildCountArg :: Maybe Value -> [String]
buildCountArg params = case getIntParam "max_count" params of
  Just n  -> ["--max-count=" ++ show n]
  Nothing -> ["--max-count=50"]

authorArg :: Maybe Value -> [String]
authorArg params = case getTextParam "author" params of
  Just a  -> ["--author=" ++ textArg a]
  Nothing -> []

sinceArg :: Maybe Value -> [String]
sinceArg params = case getTextParam "since" params of
  Just s  -> ["--since=" ++ textArg s]
  Nothing -> []

untilArg :: Maybe Value -> [String]
untilArg params = case getTextParam "until" params of
  Just u  -> ["--until=" ++ textArg u]
  Nothing -> []

allFlag :: Maybe Value -> [String]
allFlag params = case getBoolParam "all" params of
  Just True -> ["--all"]
  _         -> []


