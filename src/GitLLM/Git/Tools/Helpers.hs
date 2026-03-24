{-# LANGUAGE OverloadedStrings #-}

-- | Shared helpers for tool parameter extraction and result building.
module GitLLM.Git.Tools.Helpers
  ( getTextParam
  , getIntParam
  , getBoolParam
  , getTextListParam
  , gitResultToToolResult
  , mkToolDef
  , mkToolDefA
  , mkSchema
  , readOnly
  , mutating
  , destructive
  ) where

import Data.Aeson
import Data.Aeson.Key (Key)
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types

getTextParam :: Text -> Maybe Value -> Maybe Text
getTextParam key (Just (Object o)) = case KM.lookup (Key.fromText key) o of
  Just (String s) -> Just s
  _               -> Nothing
getTextParam _ _ = Nothing

getIntParam :: Text -> Maybe Value -> Maybe Int
getIntParam key (Just (Object o)) = case KM.lookup (Key.fromText key) o of
  Just (Number n) -> Just (round n)
  _               -> Nothing
getIntParam _ _ = Nothing

getBoolParam :: Text -> Maybe Value -> Maybe Bool
getBoolParam key (Just (Object o)) = case KM.lookup (Key.fromText key) o of
  Just (Bool b) -> Just b
  _             -> Nothing
getBoolParam _ _ = Nothing

getTextListParam :: Text -> Maybe Value -> Maybe [Text]
getTextListParam key (Just (Object o)) = case KM.lookup (Key.fromText key) o of
  Just (Array arr) -> Just [t | String t <- foldr (:) [] arr]
  _                -> Nothing
getTextListParam _ _ = Nothing

gitResultToToolResult :: GitResult -> IO ToolResult
gitResultToToolResult (Right out) = pure $ ToolResult [TextContent out] False
gitResultToToolResult (Left (GitProcessError _ err)) = pure $ ToolResult [TextContent err] True
gitResultToToolResult (Left (GitParseError err)) = pure $ ToolResult [TextContent err] True
gitResultToToolResult (Left (GitValidationError err)) = pure $ ToolResult [TextContent err] True

mkToolDef :: Text -> Text -> Value -> ToolDefinition
mkToolDef n d s = ToolDefinition n d s Nothing

mkToolDefA :: Text -> Text -> Value -> ToolAnnotations -> ToolDefinition
mkToolDefA n d s a = ToolDefinition n d s (Just a)

mkSchema :: [(Key, Value)] -> [Text] -> Value
mkSchema props reqs = object $ concat
  [ [ "type" .= ("object" :: Text)
    , "properties" .= object props
    , "additionalProperties" .= False
    ]
  , [ "required" .= reqs | not (null reqs) ]
  ]

readOnly, mutating, destructive :: ToolAnnotations
readOnly    = ToolAnnotations (Just True)  (Just False) Nothing
mutating    = ToolAnnotations (Just False) (Just False) Nothing
destructive = ToolAnnotations (Just False) (Just True)  Nothing
