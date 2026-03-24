{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Reflog (tools, handle) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_reflog"
      "Show the reference log — a history of HEAD movements and branch updates"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Ref to show reflog for" :: Text), "default" .= ("HEAD" :: Text) ]
        , "max_count" .= object [ "type" .= ("integer" :: Text), "description" .= ("Maximum entries to show" :: Text) ]
        ]
        [])
      readOnly
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params = do
  let ref      = maybe [] (\r -> [textArg r]) (getTextParam "ref" params)
      countArg = maybe ["--max-count=50"] (\n -> ["--max-count=" ++ show n]) (getIntParam "max_count" params)
  result <- runGit ctx (["reflog", "show"] ++ countArg ++ ref)
  gitResultToToolResult result
