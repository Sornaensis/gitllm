{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Diff (tools, handle, handleStaged, handleBranches, handleStat, parseNumstat) where

import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as T
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_diff"
      "Show changes between working tree and index (unstaged changes). Returns unified diff"
      (mkSchema
        [ "path" .= object [ "type" .= ("string" :: Text), "description" .= ("Limit diff to a specific file path" :: Text) ]
        , "context_lines" .= object [ "type" .= ("integer" :: Text), "description" .= ("Number of context lines" :: Text), "default" .= (3 :: Int) ]
        ]
        [])
      readOnly
  , mkToolDefA "git_diff_staged"
      "Show changes between index and HEAD (staged changes ready to commit). Returns unified diff"
      (mkSchema
        [ "path" .= object [ "type" .= ("string" :: Text), "description" .= ("Limit diff to a specific file path" :: Text) ] ]
        [])
      readOnly
  , mkToolDefA "git_diff_branches"
      "Show changes between two branches, commits, or refs. Returns unified diff"
      (mkSchema
        [ "from_ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Source ref (branch, commit, tag)" :: Text) ]
        , "to_ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Target ref (branch, commit, tag)" :: Text) ]
        ]
        ["from_ref", "to_ref"])
      readOnly
  , mkToolDefA "git_diff_stat"
      "Show diff statistics (files changed, insertions, deletions). Returns file-level stats"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Ref to compare against" :: Text), "default" .= ("HEAD" :: Text) ]
        , outputParam
        ]
        [])
      readOnly
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params = do
  let pathArg = maybe [] (\p -> ["--", textArg p]) (getTextParam "path" params)
      ctxArg  = maybe [] (\n -> ["-U" ++ show n]) (getIntParam "context_lines" params)
  result <- runGit ctx (["diff"] ++ ctxArg ++ pathArg)
  gitResultToToolResult result

handleStaged :: GitContext -> Maybe Value -> IO ToolResult
handleStaged ctx params = do
  let pathArg = maybe [] (\p -> ["--", textArg p]) (getTextParam "path" params)
  result <- runGit ctx (["diff", "--staged"] ++ pathArg)
  gitResultToToolResult result

handleBranches :: GitContext -> Maybe Value -> IO ToolResult
handleBranches ctx params = do
  case (getTextParam "from_ref" params, getTextParam "to_ref" params) of
    (Just from, Just to) -> do
      result <- runGit ctx ["diff", textArg from ++ ".." ++ textArg to]
      gitResultToToolResult result
    _ -> pure $ ToolResult [TextContent "Missing required parameters: from_ref, to_ref"] True

handleStat :: GitContext -> Maybe Value -> IO ToolResult
handleStat ctx params
  | wantsJson params = do
      let ref = maybe "HEAD" textArg (getTextParam "ref" params)
      result <- runGit ctx ["diff", "--numstat", ref]
      pure $ case result of
        Right out -> jsonResult $ object ["files" .= parseNumstat out]
        Left (GitProcessError _ err) -> ToolResult [TextContent err] True
        Left (GitParseError err)     -> ToolResult [TextContent err] True
        Left (GitValidationError err)-> ToolResult [TextContent err] True
        Left (GitTimeoutError secs)  -> ToolResult [TextContent ("Command timed out after " <> T.pack (show secs) <> " seconds")] True
  | otherwise = do
      let ref = maybe "HEAD" textArg (getTextParam "ref" params)
      result <- runGit ctx ["diff", "--stat", ref]
      gitResultToToolResult result

parseNumstat :: Text -> [Value]
parseNumstat raw =
  [ parseNumstatLine l | l <- T.lines raw, not (T.null l) ]

parseNumstatLine :: Text -> Value
parseNumstatLine line =
  case T.words line of
    (added:deleted:rest) -> object
      [ "added"   .= added
      , "deleted" .= deleted
      , "path"    .= T.unwords rest
      ]
    _ -> object ["raw" .= line]
