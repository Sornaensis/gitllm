{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Status (tools, handle, handleShort, parseStatusPorcelain) where

import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as T
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_status"
      "Show the working tree status. Returns staged, unstaged, and untracked files"
      (mkSchema [outputParam] [])
      readOnly
  , mkToolDefA "git_status_short"
      "Show concise working tree status in short format. Returns XY path lines"
      (mkSchema [outputParam] [])
      readOnly
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params
  | wantsJson params = do
      result <- runGit ctx ["status", "--porcelain=v2", "--branch"]
      pure $ case result of
        Right out -> jsonResult (parseStatusPorcelain out)
        Left (GitProcessError _ err) -> ToolResult [TextContent err] True
        Left (GitParseError err)     -> ToolResult [TextContent err] True
        Left (GitValidationError err)-> ToolResult [TextContent err] True
        Left (GitTimeoutError secs)  -> ToolResult [TextContent ("Command timed out after " <> T.pack (show secs) <> " seconds")] True
  | otherwise = do
      result <- runGit ctx ["status"]
      gitResultToToolResult result

handleShort :: GitContext -> Maybe Value -> IO ToolResult
handleShort ctx params
  | wantsJson params = do
      result <- runGit ctx ["status", "--porcelain=v2", "--branch"]
      pure $ case result of
        Right out -> jsonResult (parseStatusPorcelain out)
        Left (GitProcessError _ err) -> ToolResult [TextContent err] True
        Left (GitParseError err)     -> ToolResult [TextContent err] True
        Left (GitValidationError err)-> ToolResult [TextContent err] True
        Left (GitTimeoutError secs)  -> ToolResult [TextContent ("Command timed out after " <> T.pack (show secs) <> " seconds")] True
  | otherwise = do
      result <- runGit ctx ["status", "--short", "--branch"]
      gitResultToToolResult result

-- | Parse porcelain v2 status output into structured JSON.
parseStatusPorcelain :: Text -> Value
parseStatusPorcelain raw =
  let ls = T.lines raw
      branchLines = filter (T.isPrefixOf "# ") ls
      fileLines   = filter (\l -> T.isPrefixOf "1 " l || T.isPrefixOf "2 " l) ls
      untrackedLines = filter (T.isPrefixOf "? ") ls
      branch  = parseBranchHeader branchLines
      files   = map parseChangedEntry fileLines
      untracked = map (T.drop 2) untrackedLines
  in object
       [ "branch"    .= branch
       , "files"     .= files
       , "untracked" .= untracked
       ]

parseBranchHeader :: [Text] -> Value
parseBranchHeader ls =
  let get key = case filter (T.isPrefixOf ("# branch." <> key <> " ")) ls of
        (l:_) -> Just $ T.drop (T.length ("# branch." <> key <> " ")) l
        _     -> Nothing
  in object
       [ "head"     .= get "head"
       , "upstream" .= get "upstream"
       , "ab"       .= get "ab"
       ]

parseChangedEntry :: Text -> Value
parseChangedEntry line =
  let parts = T.words line
  in case parts of
       -- Ordinary: 1 XY sub mH mI mW hH hI path
       ("1":xy:_sub:_mH:_mI:_mW:_hH:_hI:rest) -> object
         [ "status" .= xy
         , "path"   .= T.unwords rest
         ]
       -- Renamed/copied: 2 XY sub mH mI mW hH hI Xscore origPath\tpath
       ("2":xy:_sub:_mH:_mI:_mW:_hH:_hI:score:rest) -> object
         [ "status" .= xy
         , "score"  .= score
         , "path"   .= T.unwords rest
         ]
       _ -> object ["raw" .= line]
