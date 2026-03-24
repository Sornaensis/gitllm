{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Inspect
  ( tools
  , handleCatFile, handleLsFiles, handleLsTree
  , handleRevParse, handleCountObjects
  ) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_cat_file"
      "Display the contents, type, or size of a git object. Returns raw object content"
      (mkSchema
        [ "object" .= object [ "type" .= ("string" :: Text), "description" .= ("Object hash or ref" :: Text) ]
        , "mode" .= object [ "type" .= ("string" :: Text), "description" .= ("Output mode" :: Text), "enum" .= (["content", "type", "size"] :: [Text]), "default" .= ("content" :: Text) ]
        ]
        ["object"])
      readOnly
  , mkToolDefA "git_ls_files"
      "List files tracked by git, with optional filters. Returns one path per line"
      (mkSchema
        [ "stage" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show staged contents (mode, object, stage number)" :: Text) ]
        , "modified" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show only modified files" :: Text) ]
        , "others" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show untracked files" :: Text) ]
        , "path" .= object [ "type" .= ("string" :: Text), "description" .= ("Limit to a specific path" :: Text) ]
        ]
        [])
      readOnly
  , mkToolDefA "git_ls_tree"
      "List the contents of a tree object (directory at a commit). Returns one path per line"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Tree-ish ref" :: Text), "default" .= ("HEAD" :: Text) ]
        , "path" .= object [ "type" .= ("string" :: Text), "description" .= ("Subdirectory path" :: Text) ]
        , "recursive" .= object [ "type" .= ("boolean" :: Text), "description" .= ("List tree recursively" :: Text) ]
        , "name_only" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show only names" :: Text) ]
        ]
        [])
      readOnly
  , mkToolDefA "git_rev_parse"
      "Parse a revision string and output the corresponding object name (SHA)"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Ref to parse (e.g. HEAD, branch name, tag)" :: Text) ]
        , "short" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Output abbreviated SHA" :: Text) ]
        ]
        ["ref"])
      readOnly
  , mkToolDefA "git_count_objects"
      "Count unpacked objects and their disk consumption"
      (mkSchema
        [ "verbose" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show detailed breakdown" :: Text) ] ]
        [])
      readOnly
  ]

handleCatFile :: GitContext -> Maybe Value -> IO ToolResult
handleCatFile ctx params = case getTextParam "object" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: object"] True
  Just obj -> do
    let modeFlag = case getTextParam "mode" params of
          Just "type" -> ["-t"]
          Just "size" -> ["-s"]
          _           -> ["-p"]
    result <- runGit ctx (["cat-file"] ++ modeFlag ++ [textArg obj])
    gitResultToToolResult result

handleLsFiles :: GitContext -> Maybe Value -> IO ToolResult
handleLsFiles ctx params = do
  let stageFlag = if getBoolParam "stage" params == Just True then ["-s"] else []
      modFlag   = if getBoolParam "modified" params == Just True then ["-m"] else []
      othFlag   = if getBoolParam "others" params == Just True then ["-o"] else []
      pathArg   = maybe [] (\p -> ["--", textArg p]) (getTextParam "path" params)
  result <- runGit ctx (["ls-files"] ++ stageFlag ++ modFlag ++ othFlag ++ pathArg)
  gitResultToToolResult result

handleLsTree :: GitContext -> Maybe Value -> IO ToolResult
handleLsTree ctx params = do
  let ref       = maybe "HEAD" textArg (getTextParam "ref" params)
      recFlag   = if getBoolParam "recursive" params == Just True then ["-r"] else []
      nameFlag  = if getBoolParam "name_only" params == Just True then ["--name-only"] else []
      pathArg   = maybe [] (\p -> ["--", textArg p]) (getTextParam "path" params)
  result <- runGit ctx (["ls-tree"] ++ recFlag ++ nameFlag ++ [ref] ++ pathArg)
  gitResultToToolResult result

handleRevParse :: GitContext -> Maybe Value -> IO ToolResult
handleRevParse ctx params = case getTextParam "ref" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: ref"] True
  Just ref -> do
    let shortFlag = if getBoolParam "short" params == Just True then ["--short"] else []
    result <- runGit ctx (["rev-parse"] ++ shortFlag ++ [textArg ref])
    gitResultToToolResult result

handleCountObjects :: GitContext -> Maybe Value -> IO ToolResult
handleCountObjects ctx params = do
  let vFlag = if getBoolParam "verbose" params == Just True then ["-v"] else []
  result <- runGit ctx (["count-objects"] ++ vFlag)
  gitResultToToolResult result
