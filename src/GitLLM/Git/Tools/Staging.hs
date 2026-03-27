{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Staging (tools, handleAdd, handleAddAll, handleRestore, handleRestoreStaged, handleRm, handleMv) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_add"
      "Stage specific files for the next commit"
      (mkSchema
        [ "paths" .= object [ "type" .= ("array" :: Text), "items" .= object ["type" .= ("string" :: Text)], "description" .= ("File paths to stage" :: Text) ] ]
        ["paths"])
      mutating
  , mkToolDefA "git_add_all"
      "Stage all changes (new, modified, deleted) in the working tree"
      (mkSchema [] [])
      mutating
  , mkToolDefA "git_restore"
      "Discard changes in working tree for specified files"
      (mkSchema
        [ "paths" .= object [ "type" .= ("array" :: Text), "items" .= object ["type" .= ("string" :: Text)], "description" .= ("File paths to restore" :: Text) ] ]
        ["paths"])
      mutating
  , mkToolDefA "git_restore_staged"
      "Unstage files (move from index back to working tree)"
      (mkSchema
        [ "paths" .= object [ "type" .= ("array" :: Text), "items" .= object ["type" .= ("string" :: Text)], "description" .= ("File paths to unstage" :: Text) ] ]
        ["paths"])
      mutating
  , mkToolDefA "git_rm"
      "Remove files from the working tree and the index. Use cached to only remove from the index (stop tracking) without deleting the file on disk"
      (mkSchema
        [ "paths" .= object [ "type" .= ("array" :: Text), "items" .= object ["type" .= ("string" :: Text)], "description" .= ("File paths to remove" :: Text) ]
        , "cached" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Only remove from the index, keep the file on disk (default: false)" :: Text) ]
        , "force" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Force removal even if the file has local modifications (default: false)" :: Text) ]
        , "recursive" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Allow recursive removal when a directory name is given (default: false)" :: Text) ]
        ]
        ["paths"])
      destructive
  , mkToolDefA "git_mv"
      "Move or rename a file, directory, or symlink tracked by git"
      (mkSchema
        [ "source" .= object [ "type" .= ("string" :: Text), "description" .= ("Source path" :: Text) ]
        , "destination" .= object [ "type" .= ("string" :: Text), "description" .= ("Destination path" :: Text) ]
        , "force" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Force rename even if target exists (default: false)" :: Text) ]
        ]
        ["source", "destination"])
      mutating
  ]

handleAdd :: GitContext -> Maybe Value -> IO ToolResult
handleAdd ctx params = case getTextListParam "paths" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: paths"] True
  Just paths -> case validatePaths paths of
    Left err -> pure $ ToolResult [TextContent err] True
    Right _ -> do
      result <- runGit ctx (["add", "--"] ++ map textArg paths)
      gitResultToToolResult result

handleAddAll :: GitContext -> Maybe Value -> IO ToolResult
handleAddAll ctx _ = do
  result <- runGit ctx ["add", "-A"]
  gitResultToToolResult result

handleRestore :: GitContext -> Maybe Value -> IO ToolResult
handleRestore ctx params = case getTextListParam "paths" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: paths"] True
  Just paths -> case validatePaths paths of
    Left err -> pure $ ToolResult [TextContent err] True
    Right _ -> do
      result <- runGit ctx (["restore", "--"] ++ map textArg paths)
      gitResultToToolResult result

handleRestoreStaged :: GitContext -> Maybe Value -> IO ToolResult
handleRestoreStaged ctx params = case getTextListParam "paths" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: paths"] True
  Just paths -> case validatePaths paths of
    Left err -> pure $ ToolResult [TextContent err] True
    Right _ -> do
      result <- runGit ctx (["restore", "--staged", "--"] ++ map textArg paths)
      gitResultToToolResult result

handleRm :: GitContext -> Maybe Value -> IO ToolResult
handleRm ctx params = case getTextListParam "paths" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: paths"] True
  Just paths -> case validatePaths paths of
    Left err -> pure $ ToolResult [TextContent err] True
    Right _ -> do
      let cachedFlag = if getBoolParam "cached" params == Just True then ["--cached"] else []
          forceFlag  = if getBoolParam "force" params == Just True then ["-f"] else []
          recurFlag  = if getBoolParam "recursive" params == Just True then ["-r"] else []
      result <- runGit ctx (["rm"] ++ cachedFlag ++ forceFlag ++ recurFlag ++ ["--"] ++ map textArg paths)
      gitResultToToolResult result

handleMv :: GitContext -> Maybe Value -> IO ToolResult
handleMv ctx params =
  case (getTextParam "source" params, getTextParam "destination" params) of
    (Just src, Just dst) -> case (validatePath src, validatePath dst) of
      (Right _, Right _) -> do
        let forceFlag = if getBoolParam "force" params == Just True then ["-f"] else []
        result <- runGit ctx (["mv"] ++ forceFlag ++ [textArg src, textArg dst])
        gitResultToToolResult result
      (Left err, _) -> pure $ ToolResult [TextContent err] True
      (_, Left err) -> pure $ ToolResult [TextContent err] True
    _ -> pure $ ToolResult [TextContent "Missing required parameters: source, destination"] True
