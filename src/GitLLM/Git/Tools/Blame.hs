{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Blame (tools, handle) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_blame"
      "Show what revision and author last modified each line of a file. Returns one annotated line per source line"
      (mkSchema
        [ "path" .= object [ "type" .= ("string" :: Text), "description" .= ("File path to blame" :: Text) ]
        , "line_start" .= object [ "type" .= ("integer" :: Text), "description" .= ("Start line number" :: Text) ]
        , "line_end" .= object [ "type" .= ("integer" :: Text), "description" .= ("End line number" :: Text) ]
        , "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Commit ref to blame at" :: Text), "default" .= ("HEAD" :: Text) ]
        ]
        ["path"])
      readOnly
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params = case getTextParam "path" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: path"] True
  Just path -> case validatePath path of
    Left err -> pure $ ToolResult [TextContent err] True
    Right _ -> do
      let lineRange = case (getIntParam "line_start" params, getIntParam "line_end" params) of
            (Just s, Just e) -> ["-L", show s ++ "," ++ show e]
            (Just s, Nothing) -> ["-L", show s ++ ","]
            _                -> []
          refArg = maybe [] (\r -> [textArg r]) (getTextParam "ref" params)
      result <- runGit ctx (["blame"] ++ lineRange ++ refArg ++ ["--", textArg path])
      gitResultToToolResult result
