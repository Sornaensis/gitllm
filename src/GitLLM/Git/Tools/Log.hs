{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Log (tools, handle, handleOneline, handleFile, handleGraph, handleShortlog, parseLogEntries) where

import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as T
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_log"
      "Show commit log with full details. Returns multiline commit entries"
      (mkSchema
        [ "max_count" .= object [ "type" .= ("integer" :: Text), "description" .= ("Maximum number of commits to show" :: Text) ]
        , "author" .= object [ "type" .= ("string" :: Text), "description" .= ("Filter by author pattern" :: Text) ]
        , "since" .= object [ "type" .= ("string" :: Text), "description" .= ("Show commits after date (e.g. '2 weeks ago')" :: Text) ]
        , "until" .= object [ "type" .= ("string" :: Text), "description" .= ("Show commits before date" :: Text) ]
        , "grep" .= object [ "type" .= ("string" :: Text), "description" .= ("Filter commits whose message matches this pattern" :: Text) ]
        , outputParam
        ]
        [])
      readOnly
  , mkToolDefA "git_log_oneline"
      "Show commit log in compact format. Returns one line per commit: SHA title"
      (mkSchema
        [ "max_count" .= object [ "type" .= ("integer" :: Text), "description" .= ("Maximum number of commits" :: Text) ]
        , outputParam
        ]
        [])
      readOnly
  , mkToolDefA "git_log_file"
      "Show commit log for a specific file, including renames"
      (mkSchema
        [ "path" .= object [ "type" .= ("string" :: Text), "description" .= ("File path to show history for" :: Text) ]
        , outputParam
        ]
        ["path"])
      readOnly
  , mkToolDefA "git_log_graph"
      "Show commit log as an ASCII graph with branch topology"
      (mkSchema
        [ "max_count" .= object [ "type" .= ("integer" :: Text), "description" .= ("Maximum number of commits" :: Text) ]
        , "all" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show all branches" :: Text) ]
        ]
        [])
      readOnly
  , mkToolDefA "git_shortlog"
      "Summarize commit output grouped by author"
      (mkSchema
        [ "numbered" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Sort output by number of commits per author (descending)" :: Text) ]
        , "summary" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show only commit count per author" :: Text) ]
        , "email" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show email address of each author" :: Text) ]
        , "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Rev range (e.g. 'v1.0..HEAD'). Default: all commits" :: Text) ]
        ]
        [])
      readOnly
  ]

-- | Delimiter for machine-parseable log format (unlikely in commit messages).
logDelim :: String
logDelim = "---gitllm-field---"

logDelimT :: Text
logDelimT = "---gitllm-field---"

-- | A --format string that produces delimited fields.
jsonLogFormat :: String
jsonLogFormat = "%H" ++ logDelim ++ "%h" ++ logDelim ++ "%an" ++ logDelim
  ++ "%ae" ++ logDelim ++ "%ai" ++ logDelim ++ "%s" ++ logDelim ++ "%P"

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params
  | wantsJson params = do
      let args = ["log", "--format=" ++ jsonLogFormat] ++ buildLogArgs params
      result <- runGit ctx args
      pure $ case result of
        Right out -> jsonResult $ object ["commits" .= parseLogEntries out]
        Left err  -> gitErrorToResult err
  | otherwise = do
      let args = ["log"] ++ buildLogArgs params
      result <- runGit ctx args
      gitResultToToolResult result

handleOneline :: GitContext -> Maybe Value -> IO ToolResult
handleOneline ctx params
  | wantsJson params = do
      let args = ["log", "--format=" ++ jsonLogFormat] ++ buildCountArg params
      result <- runGit ctx args
      pure $ case result of
        Right out -> jsonResult $ object ["commits" .= parseLogEntries out]
        Left err  -> gitErrorToResult err
  | otherwise = do
      let args = ["log", "--oneline"] ++ buildCountArg params
      result <- runGit ctx args
      gitResultToToolResult result

handleFile :: GitContext -> Maybe Value -> IO ToolResult
handleFile ctx params = do
  case getTextParam "path" params of
    Nothing -> pure $ ToolResult [TextContent "Missing required parameter: path"] True
    Just path
      | wantsJson params -> do
          result <- runGit ctx ["log", "--follow", "--format=" ++ jsonLogFormat, "--", textArg path]
          pure $ case result of
            Right out -> jsonResult $ object ["commits" .= parseLogEntries out]
            Left err  -> gitErrorToResult err
      | otherwise -> do
          result <- runGit ctx ["log", "--follow", "--", textArg path]
          gitResultToToolResult result

handleGraph :: GitContext -> Maybe Value -> IO ToolResult
handleGraph ctx params = do
  let args = ["log", "--graph", "--oneline", "--decorate"] ++ buildCountArg params ++ allFlag params
  result <- runGit ctx args
  gitResultToToolResult result

-- | Parse delimited log output into a list of commit objects.
parseLogEntries :: Text -> [Value]
parseLogEntries raw =
  [ parseLogLine l | l <- T.lines raw, not (T.null l) ]

parseLogLine :: Text -> Value
parseLogLine line =
  case T.splitOn logDelimT line of
    [hash, short, author, email, date, subject, parents] -> object
      [ "hash"    .= hash
      , "short"   .= short
      , "author"  .= author
      , "email"   .= email
      , "date"    .= date
      , "subject" .= subject
      , "parents" .= T.words parents
      ]
    _ -> object ["raw" .= line]

gitErrorToResult :: GitError -> ToolResult
gitErrorToResult (GitProcessError _ err) = ToolResult [TextContent err] True
gitErrorToResult (GitParseError err)     = ToolResult [TextContent err] True
gitErrorToResult (GitValidationError err)= ToolResult [TextContent err] True
gitErrorToResult (GitTimeoutError secs)  = ToolResult [TextContent ("Command timed out after " <> T.pack (show secs) <> " seconds")] True

-- Helpers
buildLogArgs :: Maybe Value -> [String]
buildLogArgs params = buildCountArg params ++ authorArg params ++ sinceArg params ++ untilArg params ++ grepArg params

buildCountArg :: Maybe Value -> [String]
buildCountArg params = case getIntParam "max_count" params of
  Just n  -> ["--max-count=" ++ show n]
  Nothing -> ["--max-count=50"]

authorArg :: Maybe Value -> [String]
authorArg params = case getTextParam "author" params of
  Just a  -> ["--author=" ++ textArg a]
  Nothing -> []

sinceArg :: Maybe Value -> [String]
sinceArg params = case getTextParam "since" params of
  Just s  -> ["--since=" ++ textArg s]
  Nothing -> []

untilArg :: Maybe Value -> [String]
untilArg params = case getTextParam "until" params of
  Just u  -> ["--until=" ++ textArg u]
  Nothing -> []

grepArg :: Maybe Value -> [String]
grepArg params = case getTextParam "grep" params of
  Just g  -> ["--grep=" ++ textArg g]
  Nothing -> []

allFlag :: Maybe Value -> [String]
allFlag params = case getBoolParam "all" params of
  Just True -> ["--all"]
  _         -> []

handleShortlog :: GitContext -> Maybe Value -> IO ToolResult
handleShortlog ctx params = do
  let numFlag   = if getBoolParam "numbered" params == Just True then ["-n"] else []
      sumFlag   = if getBoolParam "summary" params == Just True then ["-s"] else []
      emailFlag = if getBoolParam "email" params == Just True then ["-e"] else []
      refArg    = maybe ["HEAD"] (\r -> [textArg r]) (getTextParam "ref" params)
  result <- runGit ctx (["shortlog"] ++ numFlag ++ sumFlag ++ emailFlag ++ refArg)
  gitResultToToolResult result


