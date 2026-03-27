{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Commit (tools, handle, handleAmend, handleShow) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_commit"
      "Create a new commit with the staged changes and the given message"
      (mkSchema
        [ "message" .= object [ "type" .= ("string" :: Text), "description" .= ("Commit message" :: Text) ]
        , "allow_empty" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Allow an empty commit" :: Text) ]
        , "no_verify" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Skip pre-commit and commit-msg hooks" :: Text) ]
        ]
        ["message"])
      mutating
  , mkToolDefA "git_commit_amend"
      "Amend the last commit (optionally with a new message)"
      (mkSchema
        [ "message" .= object [ "type" .= ("string" :: Text), "description" .= ("New commit message (omit to keep existing)" :: Text) ]
        , "no_edit" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Keep the existing commit message" :: Text) ]
        ]
        [])
      destructive
  , mkToolDefA "git_show"
      "Show details of a commit including diff"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Commit ref to show" :: Text), "default" .= ("HEAD" :: Text) ]
        , "stat" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show only stats, not full diff" :: Text) ]
        ]
        [])
      readOnly
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params = case getTextParam "message" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: message"] True
  Just msg -> do
    let emptyFlag  = if getBoolParam "allow_empty" params == Just True then ["--allow-empty"] else []
        verifyFlag = if getBoolParam "no_verify" params == Just True then ["--no-verify"] else []
    result <- runGit ctx (["commit", "-m", textArg msg] ++ emptyFlag ++ verifyFlag)
    gitResultToToolResult result

handleAmend :: GitContext -> Maybe Value -> IO ToolResult
handleAmend ctx params = do
  let msgArgs = case getTextParam "message" params of
        Just msg -> ["-m", textArg msg]
        Nothing  -> ["--no-edit"]
  result <- runGit ctx (["commit", "--amend"] ++ msgArgs)
  gitResultToToolResult result

handleShow :: GitContext -> Maybe Value -> IO ToolResult
handleShow ctx params = do
  let ref = maybe "HEAD" textArg (getTextParam "ref" params)
      statFlag = if getBoolParam "stat" params == Just True then ["--stat"] else []
  result <- runGit ctx (["show", ref] ++ statFlag)
  gitResultToToolResult result
