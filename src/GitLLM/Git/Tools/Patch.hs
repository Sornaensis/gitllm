{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Patch (tools, handleFormatPatch, handleApply) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_format_patch"
      "Generate patch files from commits for email or transfer"
      (mkSchema
        [ "base" .= object [ "type" .= ("string" :: Text), "description" .= ("Base commit (patches generated from base..HEAD)" :: Text) ]
        , "count" .= object [ "type" .= ("integer" :: Text), "description" .= ("Number of commits from HEAD to format" :: Text) ]
        , "output_dir" .= object [ "type" .= ("string" :: Text), "description" .= ("Output directory for patch files" :: Text) ]
        ]
        [])
      mutating
  , mkToolDefA "git_apply"
      "Apply a patch file to the working tree"
      (mkSchema
        [ "patch_path" .= object [ "type" .= ("string" :: Text), "description" .= ("Path to the patch file" :: Text) ]
        , "check" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Only check if patch applies cleanly" :: Text) ]
        , "stat" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show stats instead of applying" :: Text) ]
        ]
        ["patch_path"])
      mutating
  ]

handleFormatPatch :: GitContext -> Maybe Value -> IO ToolResult
handleFormatPatch ctx params = do
  let baseArg = case getTextParam "base" params of
        Just b  -> [textArg b ++ "..HEAD"]
        Nothing -> case getIntParam "count" params of
          Just n  -> ["-" ++ show n]
          Nothing -> ["-1"]
      outArg = maybe [] (\d -> ["-o", textArg d]) (getTextParam "output_dir" params)
  result <- runGit ctx (["format-patch"] ++ outArg ++ baseArg)
  gitResultToToolResult result

handleApply :: GitContext -> Maybe Value -> IO ToolResult
handleApply ctx params = case getTextParam "patch_path" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: patch_path"] True
  Just path -> case validatePath path of
    Left err -> pure $ ToolResult [TextContent err] True
    Right _ -> do
      let checkFlag = if getBoolParam "check" params == Just True then ["--check"] else []
          statFlag  = if getBoolParam "stat" params == Just True then ["--stat"] else []
      result <- runGit ctx (["apply"] ++ checkFlag ++ statFlag ++ [textArg path])
      gitResultToToolResult result
