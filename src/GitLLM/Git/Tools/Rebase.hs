{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Rebase (tools, handle, handleInteractive, handleAbort, handleContinue) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_rebase"
      "Rebase the current branch onto another branch or commit"
      (mkSchema
        [ "onto" .= object [ "type" .= ("string" :: Text), "description" .= ("Branch or commit to rebase onto" :: Text) ] ]
        ["onto"])
      destructive
  , mkToolDefA "git_rebase_interactive"
      "Start an interactive rebase (returns the todo list for review)"
      (mkSchema
        [ "onto" .= object [ "type" .= ("string" :: Text), "description" .= ("Base commit for interactive rebase (e.g. HEAD~3)" :: Text) ] ]
        ["onto"])
      destructive
  , mkToolDefA "git_rebase_abort"
      "Abort an in-progress rebase and restore the original branch"
      (mkSchema [] [])
      mutating
  , mkToolDefA "git_rebase_continue"
      "Continue a rebase after resolving conflicts"
      (mkSchema [] [])
      mutating
  ]

handle :: GitContext -> Maybe Value -> IO ToolResult
handle ctx params = case getTextParam "onto" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: onto"] True
  Just onto -> do
    result <- runGit ctx ["rebase", textArg onto]
    gitResultToToolResult result

handleInteractive :: GitContext -> Maybe Value -> IO ToolResult
handleInteractive ctx params = case getTextParam "onto" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: onto"] True
  Just onto -> do
    -- Non-interactive listing of what would be rebased
    result <- runGit ctx ["log", "--oneline", textArg onto ++ "..HEAD"]
    gitResultToToolResult result

handleAbort :: GitContext -> Maybe Value -> IO ToolResult
handleAbort ctx _ = do
  result <- runGit ctx ["rebase", "--abort"]
  gitResultToToolResult result

handleContinue :: GitContext -> Maybe Value -> IO ToolResult
handleContinue ctx _ = do
  result <- runGit ctx ["rebase", "--continue"]
  gitResultToToolResult result
