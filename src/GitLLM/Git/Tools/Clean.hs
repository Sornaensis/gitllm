{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Clean (tools, handle, handleDryRun, handleGc) where

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
  , mkToolDefA "git_gc"
      "Run garbage collection to optimize the repository. Cleans up unnecessary files and compresses objects"
      (mkSchema
        [ "aggressive" .= object [ "type" .= ("boolean" :: Text), "description" .= ("More thorough but slower optimization (default: false)" :: Text) ]
        , "auto" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Only run if needed based on heuristics (default: false)" :: Text) ]
        , "prune" .= object [ "type" .= ("string" :: Text), "description" .= ("Prune objects older than this date (e.g. '2.weeks.ago', 'now'). Default: '2.weeks.ago'" :: Text) ]
        ]
        [])
      mutating
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

handleGc :: GitContext -> Maybe Value -> IO ToolResult
handleGc ctx params = do
  let aggrFlag  = if getBoolParam "aggressive" params == Just True then ["--aggressive"] else []
      autoFlag  = if getBoolParam "auto" params == Just True then ["--auto"] else []
      pruneFlag = maybe [] (\d -> ["--prune=" ++ textArg d]) (getTextParam "prune" params)
  result <- runGit ctx (["gc"] ++ aggrFlag ++ autoFlag ++ pruneFlag)
  gitResultToToolResult result
