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
  , validatePath
  , validatePaths
  , wantsJson
  , jsonResult
  , outputParam
  ) where

import Data.Aeson
import Data.Aeson.Key (Key)
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
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
gitResultToToolResult (Left (GitTimeoutError secs)) = pure $ ToolResult [TextContent msg] True
  where msg = "Command timed out after " <> T.pack (show secs) <> " seconds"

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

-- | Validate a file path: reject directory traversal attempts.
-- Returns Left with error message if path is unsafe, Right path if safe.
validatePath :: Text -> Either Text Text
validatePath p
  | T.isInfixOf ".." p = Left $ "Path traversal not allowed: " <> p
  | T.isPrefixOf "/" p  = Left $ "Absolute paths not allowed: " <> p
  | otherwise           = Right p

-- | Validate a list of file paths.
validatePaths :: [Text] -> Either Text [Text]
validatePaths ps = case filter (T.isInfixOf "..") ps ++ filter (T.isPrefixOf "/") ps of
  []    -> Right ps
  bad:_ -> Left $ "Invalid path: " <> bad

-- | Check whether the caller requested JSON output.
wantsJson :: Maybe Value -> Bool
wantsJson params = getTextParam "output" params == Just "json"

-- | Build a success ToolResult containing a JSON value rendered as text.
jsonResult :: Value -> ToolResult
jsonResult v = ToolResult [TextContent (TE.decodeUtf8 $ BL.toStrict $ encode v)] False

-- | Schema property for the output format parameter. Add to tool schemas
-- that support structured JSON output.
outputParam :: (Key, Value)
outputParam = "output" .= object
  [ "type" .= ("string" :: Text)
  , "description" .= ("Output format: 'text' (default) or 'json' for structured JSON" :: Text)
  , "enum" .= (["text", "json"] :: [Text])
  ]
