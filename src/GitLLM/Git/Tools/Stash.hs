{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Stash (tools, handlePush, handlePop, handleApply, handleList, handleShow, handleDrop, parseStashLines) where

import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as T
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_stash_push"
      "Stash the current working directory changes"
      (mkSchema
        [ "message" .= object [ "type" .= ("string" :: Text), "description" .= ("Optional stash message" :: Text) ]
        , "include_untracked" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Include untracked files" :: Text) ]
        , "keep_index" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Keep staged changes in the index" :: Text) ]
        , "staged" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Stash only staged changes (git 2.35+)" :: Text) ]
        ]
        [])
      mutating
  , mkToolDefA "git_stash_pop"
      "Apply the top stash entry and remove it from the stash list"
      (mkSchema
        [ "index" .= object [ "type" .= ("integer" :: Text), "description" .= ("Stash index to pop" :: Text), "default" .= (0 :: Int) ] ]
        [])
      mutating
  , mkToolDefA "git_stash_apply"
      "Apply a stash entry without removing it from the stash list"
      (mkSchema
        [ "index" .= object [ "type" .= ("integer" :: Text), "description" .= ("Stash index to apply" :: Text), "default" .= (0 :: Int) ] ]
        [])
      mutating
  , mkToolDefA "git_stash_list"
      "List all stash entries"
      (mkSchema [outputParam] [])
      readOnly
  , mkToolDefA "git_stash_show"
      "Show the changes recorded in a stash entry"
      (mkSchema
        [ "index" .= object [ "type" .= ("integer" :: Text), "description" .= ("Stash index to show" :: Text), "default" .= (0 :: Int) ]
        , "patch" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show as patch diff" :: Text) ]
        ]
        [])
      readOnly
  , mkToolDefA "git_stash_drop"
      "Remove a specific stash entry"
      (mkSchema
        [ "index" .= object [ "type" .= ("integer" :: Text), "description" .= ("Stash index to drop" :: Text), "default" .= (0 :: Int) ] ]
        [])
      destructive
  ]

handlePush :: GitContext -> Maybe Value -> IO ToolResult
handlePush ctx params = do
  let msgFlag       = maybe [] (\m -> ["-m", textArg m]) (getTextParam "message" params)
      untrackedFlag = if getBoolParam "include_untracked" params == Just True then ["--include-untracked"] else []
      keepFlag      = if getBoolParam "keep_index" params == Just True then ["--keep-index"] else []
      stagedFlag    = if getBoolParam "staged" params == Just True then ["--staged"] else []
  result <- runGit ctx (["stash", "push"] ++ msgFlag ++ untrackedFlag ++ keepFlag ++ stagedFlag)
  gitResultToToolResult result

handlePop :: GitContext -> Maybe Value -> IO ToolResult
handlePop ctx params = do
  let idx = maybe "stash@{0}" (\n -> "stash@{" ++ show n ++ "}") (getIntParam "index" params)
  result <- runGit ctx ["stash", "pop", idx]
  gitResultToToolResult result

handleApply :: GitContext -> Maybe Value -> IO ToolResult
handleApply ctx params = do
  let idx = maybe "stash@{0}" (\n -> "stash@{" ++ show n ++ "}") (getIntParam "index" params)
  result <- runGit ctx ["stash", "apply", idx]
  gitResultToToolResult result

handleList :: GitContext -> Maybe Value -> IO ToolResult
handleList ctx params
  | wantsJson params = do
      result <- runGit ctx ["stash", "list", "--format=%gd\t%gs"]
      pure $ case result of
        Right out -> jsonResult $ object ["stashes" .= parseStashLines out]
        Left (GitProcessError _ err) -> ToolResult [TextContent err] True
        Left (GitParseError err)     -> ToolResult [TextContent err] True
        Left (GitValidationError err)-> ToolResult [TextContent err] True
        Left (GitTimeoutError secs)  -> ToolResult [TextContent ("Command timed out after " <> T.pack (show secs) <> " seconds")] True
  | otherwise = do
      result <- runGit ctx ["stash", "list"]
      gitResultToToolResult result

parseStashLines :: Text -> [Value]
parseStashLines raw =
  [ parseStashLine l | l <- T.lines raw, not (T.null l) ]

parseStashLine :: Text -> Value
parseStashLine line =
  case T.splitOn "\t" line of
    [ref, description] -> object
      [ "ref"         .= ref
      , "description" .= description
      ]
    _ -> object ["raw" .= line]

handleShow :: GitContext -> Maybe Value -> IO ToolResult
handleShow ctx params = do
  let idx       = maybe "stash@{0}" (\n -> "stash@{" ++ show n ++ "}") (getIntParam "index" params)
      patchFlag = if getBoolParam "patch" params == Just True then ["-p"] else []
  result <- runGit ctx (["stash", "show"] ++ patchFlag ++ [idx])
  gitResultToToolResult result

handleDrop :: GitContext -> Maybe Value -> IO ToolResult
handleDrop ctx params = do
  let idx = maybe "stash@{0}" (\n -> "stash@{" ++ show n ++ "}") (getIntParam "index" params)
  result <- runGit ctx ["stash", "drop", idx]
  gitResultToToolResult result
