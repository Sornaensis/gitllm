{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Config (tools, handleGet, handleSet, handleList, parseConfigLines) where

import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as T
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_config_get"
      "Get the value of a git configuration key"
      (mkSchema
        [ "key" .= object [ "type" .= ("string" :: Text), "description" .= ("Configuration key (e.g. user.name)" :: Text) ]
        , "scope" .= object [ "type" .= ("string" :: Text), "description" .= ("Configuration scope" :: Text), "enum" .= (["local", "global", "system"] :: [Text]) ]
        ]
        ["key"])
      readOnly
  , mkToolDefA "git_config_set"
      "Set a git configuration value (local scope only for safety)"
      (mkSchema
        [ "key" .= object [ "type" .= ("string" :: Text), "description" .= ("Configuration key" :: Text) ]
        , "value" .= object [ "type" .= ("string" :: Text), "description" .= ("Value to set" :: Text) ]
        ]
        ["key", "value"])
      mutating
  , mkToolDefA "git_config_list"
      "List all git configuration values in effect"
      (mkSchema
        [ "scope" .= object [ "type" .= ("string" :: Text), "description" .= ("Configuration scope" :: Text), "enum" .= (["local", "global", "system"] :: [Text]) ]
        , outputParam
        ]
        [])
      readOnly
  ]

handleGet :: GitContext -> Maybe Value -> IO ToolResult
handleGet ctx params = case getTextParam "key" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: key"] True
  Just key -> do
    let scopeArg = case getTextParam "scope" params of
          Just "global" -> ["--global"]
          Just "system" -> ["--system"]
          Just "local"  -> ["--local"]
          _             -> []
    result <- runGit ctx (["config"] ++ scopeArg ++ ["--get", textArg key])
    gitResultToToolResult result

handleSet :: GitContext -> Maybe Value -> IO ToolResult
handleSet ctx params =
  case (getTextParam "key" params, getTextParam "value" params) of
    (Just key, Just val) -> do
      -- Only allow local scope for safety
      result <- runGit ctx ["config", "--local", textArg key, textArg val]
      gitResultToToolResult result
    _ -> pure $ ToolResult [TextContent "Missing required parameters: key, value"] True

handleList :: GitContext -> Maybe Value -> IO ToolResult
handleList ctx params = do
  let scopeArg = case getTextParam "scope" params of
        Just "global" -> ["--global"]
        Just "system" -> ["--system"]
        Just "local"  -> ["--local"]
        _             -> []
  if wantsJson params
    then do
      result <- runGit ctx (["config"] ++ scopeArg ++ ["--list"])
      pure $ case result of
        Right out -> jsonResult $ object ["config" .= parseConfigLines out]
        Left (GitProcessError _ err) -> ToolResult [TextContent err] True
        Left (GitParseError err)     -> ToolResult [TextContent err] True
        Left (GitValidationError err)-> ToolResult [TextContent err] True
        Left (GitTimeoutError secs)  -> ToolResult [TextContent ("Command timed out after " <> T.pack (show secs) <> " seconds")] True
    else do
      result <- runGit ctx (["config"] ++ scopeArg ++ ["--list"])
      gitResultToToolResult result

parseConfigLines :: Text -> [Value]
parseConfigLines raw =
  [ parseConfigLine l | l <- T.lines raw, not (T.null l) ]

parseConfigLine :: Text -> Value
parseConfigLine line =
  case T.breakOn "=" line of
    (key, rest)
      | not (T.null rest) -> object
          [ "key"   .= key
          , "value" .= T.drop 1 rest
          ]
      | otherwise -> object ["raw" .= line]
