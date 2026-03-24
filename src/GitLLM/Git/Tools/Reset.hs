{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Reset (tools, handle, handleFile) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_reset"
      "Reset the current HEAD to a specified state"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Commit to reset to" :: Text), "default" .= ("HEAD" :: Text) ]
        , "mode" .= object [ "type" .= ("string" :: Text), "description" .= ("Reset mode" :: Text), "enum" .= (["soft", "mixed", "hard"] :: [Text]), "default" .= ("mixed" :: Text) ]
        ]
        [])
      destructive
  , mkToolDefA "git_reset_file"
      "Reset specific files in the index to a given commit (unstage)"
      (mkSchema
        [ "paths" .= object [ "type" .= ("array" :: Text), "items" .= object ["type" .= ("string" :: Text)], "description" .= ("File paths to reset" :: Text) ]
        , "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Commit ref" :: Text), "default" .= ("HEAD" :: Text) ]
        ]
        ["paths"])
      mutating
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params = do
  let modeFlag = case getTextParam "mode" params of
        Just "soft" -> ["--soft"]
        Just "hard" -> ["--hard"]
        _           -> ["--mixed"]
      ref = maybe "HEAD" textArg (getTextParam "ref" params)
  result <- runGit ctx (["reset"] ++ modeFlag ++ [ref])
  gitResultToToolResult result

handleFile :: GitContext -> Maybe Value -> IO ToolResult
handleFile ctx params = case getTextListParam "paths" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: paths"] True
  Just paths -> do
    let ref = maybe "HEAD" textArg (getTextParam "ref" params)
    result <- runGit ctx (["reset", ref, "--"] ++ map textArg paths)
    gitResultToToolResult result
