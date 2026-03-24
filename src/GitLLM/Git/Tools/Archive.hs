{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Archive (tools, handle) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_archive"
      "Create an archive (tar/zip) of files from a named tree"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Tree-ish to archive" :: Text), "default" .= ("HEAD" :: Text) ]
        , "format" .= object [ "type" .= ("string" :: Text), "description" .= ("Archive format" :: Text), "enum" .= (["tar", "tar.gz", "zip"] :: [Text]), "default" .= ("tar" :: Text) ]
        , "output" .= object [ "type" .= ("string" :: Text), "description" .= ("Output file path" :: Text) ]
        , "prefix" .= object [ "type" .= ("string" :: Text), "description" .= ("Prepend prefix to each filename" :: Text) ]
        ]
        [])
      mutating
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params = do
  let ref       = maybe "HEAD" textArg (getTextParam "ref" params)
      fmtArg    = maybe [] (\f -> ["--format=" ++ textArg f]) (getTextParam "format" params)
      outArg    = maybe [] (\o -> ["-o", textArg o]) (getTextParam "output" params)
      prefixArg = maybe [] (\p -> ["--prefix=" ++ textArg p]) (getTextParam "prefix" params)
  result <- runGit ctx (["archive"] ++ fmtArg ++ outArg ++ prefixArg ++ [ref])
  gitResultToToolResult result
