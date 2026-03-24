{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Search (tools, handleGrep, handleLogSearch) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_grep"
      "Search tracked files for a pattern (like grep but git-aware)"
      (mkSchema
        [ "pattern" .= object [ "type" .= ("string" :: Text), "description" .= ("Search pattern (regex)" :: Text) ]
        , "path" .= object [ "type" .= ("string" :: Text), "description" .= ("Limit search to a path" :: Text) ]
        , "ignore_case" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Case-insensitive search" :: Text) ]
        , "line_number" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show line numbers" :: Text) ]
        ]
        ["pattern"])
      readOnly
  , mkToolDefA "git_log_search"
      "Search commit messages and diffs for a pattern (pickaxe search)"
      (mkSchema
        [ "pattern" .= object [ "type" .= ("string" :: Text), "description" .= ("Search pattern" :: Text) ]
        , "in_diff" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Search in diffs rather than commit messages" :: Text) ]
        , "max_count" .= object [ "type" .= ("integer" :: Text), "description" .= ("Maximum results" :: Text) ]
        ]
        ["pattern"])
      readOnly
  ]

handleGrep :: GitContext -> Maybe Value -> IO ToolResult
handleGrep ctx params = case getTextParam "pattern" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: pattern"] True
  Just pat -> do
    let caseFlag = if getBoolParam "ignore_case" params == Just True then ["-i"] else []
        lineFlag = if getBoolParam "line_number" params == Just True then ["-n"] else ["-n"]
        pathArg  = maybe [] (\p -> ["--", textArg p]) (getTextParam "path" params)
    result <- runGit ctx (["grep"] ++ caseFlag ++ lineFlag ++ [textArg pat] ++ pathArg)
    gitResultToToolResult result

handleLogSearch :: GitContext -> Maybe Value -> IO ToolResult
handleLogSearch ctx params = case getTextParam "pattern" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: pattern"] True
  Just pat -> do
    let searchFlag = if getBoolParam "in_diff" params == Just True
                     then ["-G", textArg pat]
                     else ["--grep=" ++ textArg pat]
        countArg   = maybe ["--max-count=20"] (\n -> ["--max-count=" ++ show n]) (getIntParam "max_count" params)
    result <- runGit ctx (["log"] ++ countArg ++ searchFlag)
    gitResultToToolResult result
