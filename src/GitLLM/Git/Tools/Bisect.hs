{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Bisect (tools, handleStart, handleGood, handleBad, handleReset) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_bisect_start"
      "Start a bisect session to find the commit that introduced a bug"
      (mkSchema
        [ "bad"  .= object [ "type" .= ("string" :: Text), "description" .= ("Known bad commit" :: Text), "default" .= ("HEAD" :: Text) ]
        , "good" .= object [ "type" .= ("string" :: Text), "description" .= ("Known good commit" :: Text) ]
        ]
        [])
      mutating
  , mkToolDefA "git_bisect_good"
      "Mark the current bisect commit as good"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Specific commit to mark" :: Text), "default" .= ("current" :: Text) ] ]
        [])
      mutating
  , mkToolDefA "git_bisect_bad"
      "Mark the current bisect commit as bad"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Specific commit to mark" :: Text), "default" .= ("current" :: Text) ] ]
        [])
      mutating
  , mkToolDefA "git_bisect_reset"
      "End the bisect session and return to the original branch"
      (mkSchema [] [])
      mutating
  ]

handleStart :: GitContext -> Maybe Value -> IO ToolResult
handleStart ctx params = do
  let badArg  = maybe [] (\b -> [textArg b]) (getTextParam "bad" params)
      goodArg = maybe [] (\g -> [textArg g]) (getTextParam "good" params)
  result <- runGit ctx (["bisect", "start"] ++ badArg ++ goodArg)
  gitResultToToolResult result

handleGood :: GitContext -> Maybe Value -> IO ToolResult
handleGood ctx params = do
  let refArg = maybe [] (\r -> [textArg r]) (getTextParam "ref" params)
  result <- runGit ctx (["bisect", "good"] ++ refArg)
  gitResultToToolResult result

handleBad :: GitContext -> Maybe Value -> IO ToolResult
handleBad ctx params = do
  let refArg = maybe [] (\r -> [textArg r]) (getTextParam "ref" params)
  result <- runGit ctx (["bisect", "bad"] ++ refArg)
  gitResultToToolResult result

handleReset :: GitContext -> Maybe Value -> IO ToolResult
handleReset ctx _ = do
  result <- runGit ctx ["bisect", "reset"]
  gitResultToToolResult result
