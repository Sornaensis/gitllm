{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Clean (tools, handle, handleDryRun) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_clean"
      "Remove untracked files from the working tree"
      (mkSchema
        [ "directories" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Also remove untracked directories" :: Text) ]
        , "force" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Force clean (required by git)" :: Text) ]
        , "ignored" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Also remove ignored files" :: Text) ]
        ]
        [])
      destructive
  , mkToolDefA "git_clean_dry_run"
      "Preview which untracked files would be removed by git clean"
      (mkSchema
        [ "directories" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Include untracked directories" :: Text) ] ]
        [])
      readOnly
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params = do
  let forceFlag = if getBoolParam "force" params == Just True then ["-f"] else []
      dirFlag   = if getBoolParam "directories" params == Just True then ["-d"] else []
      ignFlag   = if getBoolParam "ignored" params == Just True then ["-x"] else []
  result <- runGit ctx (["clean"] ++ forceFlag ++ dirFlag ++ ignFlag)
  gitResultToToolResult result

handleDryRun :: GitContext -> Maybe Value -> IO ToolResult
handleDryRun ctx params = do
  let dirFlag = if getBoolParam "directories" params == Just True then ["-d"] else []
  result <- runGit ctx (["clean", "-n"] ++ dirFlag)
  gitResultToToolResult result
