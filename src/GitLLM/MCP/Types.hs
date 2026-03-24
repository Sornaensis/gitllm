{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}

module GitLLM.MCP.Types
  ( -- * Server configuration
    ServerConfig(..)
    -- * JSON-RPC types
  , JsonRpcRequest(..)
  , JsonRpcResponse(..)
  , JsonRpcError(..)
  , JsonRpcId(..)
    -- * MCP-specific types
  , ToolDefinition(..)
  , ToolAnnotations(..)
  , ToolParameter(..)
  , ToolParameterType(..)
  , ToolResult(..)
  , ToolResultContent(..)
  , ServerCapabilities(..)
  , ServerInfo(..)
  , InitializeResult(..)
  ) where

import Data.Aeson
import Data.Text (Text)
import GHC.Generics (Generic)

-- | Top-level server configuration.
data ServerConfig = ServerConfig
  { cfgRepoPath   :: Maybe FilePath
  , cfgTransport  :: String       -- ^ "stdio" or "tcp:<port>"
  , cfgServerName :: Text
  , cfgVersion    :: Text
  , cfgTimeout    :: Maybe Int    -- ^ Command timeout in seconds
  } deriving (Show, Eq)

-- | JSON-RPC 2.0 request identifier — integer or string.
data JsonRpcId
  = IdInt  !Int
  | IdStr  !Text
  | IdNull
  deriving (Show, Eq, Generic)

instance FromJSON JsonRpcId where
  parseJSON (Number n) = pure $ IdInt (round n)
  parseJSON (String s) = pure $ IdStr s
  parseJSON Null       = pure IdNull
  parseJSON _          = fail "Invalid JSON-RPC id"

instance ToJSON JsonRpcId where
  toJSON (IdInt n) = toJSON n
  toJSON (IdStr s) = toJSON s
  toJSON IdNull    = Null

-- | JSON-RPC 2.0 request.
data JsonRpcRequest = JsonRpcRequest
  { rpcReqId     :: Maybe JsonRpcId
  , rpcReqMethod :: Text
  , rpcReqParams :: Maybe Value
  } deriving (Show, Eq, Generic)

instance FromJSON JsonRpcRequest where
  parseJSON = withObject "JsonRpcRequest" $ \o -> JsonRpcRequest
    <$> o .:? "id"
    <*> o .:  "method"
    <*> o .:? "params"

instance ToJSON JsonRpcRequest where
  toJSON r = object
    [ "jsonrpc" .= ("2.0" :: Text)
    , "id"      .= rpcReqId r
    , "method"  .= rpcReqMethod r
    , "params"  .= rpcReqParams r
    ]

-- | JSON-RPC 2.0 response.
data JsonRpcResponse = JsonRpcResponse
  { rpcResId     :: Maybe JsonRpcId
  , rpcResResult :: Maybe Value
  , rpcResError  :: Maybe JsonRpcError
  } deriving (Show, Eq, Generic)

instance ToJSON JsonRpcResponse where
  toJSON r = object
    [ "jsonrpc" .= ("2.0" :: Text)
    , "id"      .= rpcResId r
    , "result"  .= rpcResResult r
    , "error"   .= rpcResError r
    ]

-- | JSON-RPC 2.0 error object.
data JsonRpcError = JsonRpcError
  { errCode    :: Int
  , errMessage :: Text
  , errData    :: Maybe Value
  } deriving (Show, Eq, Generic)

instance ToJSON JsonRpcError where
  toJSON e = object
    [ "code"    .= errCode e
    , "message" .= errMessage e
    , "data"    .= errData e
    ]

instance FromJSON JsonRpcError where
  parseJSON = withObject "JsonRpcError" $ \o -> JsonRpcError
    <$> o .:  "code"
    <*> o .:  "message"
    <*> o .:? "data"

-- | MCP tool annotations for client hints.
data ToolAnnotations = ToolAnnotations
  { annReadOnly    :: Maybe Bool
  , annDestructive :: Maybe Bool
  , annOpenWorld   :: Maybe Bool
  } deriving (Show, Eq, Generic)

instance ToJSON ToolAnnotations where
  toJSON a = object $ concat
    [ maybe [] (\v -> ["readOnlyHint"    .= v]) (annReadOnly a)
    , maybe [] (\v -> ["destructiveHint" .= v]) (annDestructive a)
    , maybe [] (\v -> ["openWorldHint"   .= v]) (annOpenWorld a)
    ]

-- | Describes a single MCP tool.
data ToolDefinition = ToolDefinition
  { toolName        :: Text
  , toolDescription :: Text
  , toolInputSchema :: Value  -- ^ JSON Schema for the tool's parameters
  , toolAnnotations :: Maybe ToolAnnotations
  } deriving (Show, Eq, Generic)

instance ToJSON ToolDefinition where
  toJSON t = object $ concat
    [ [ "name"        .= toolName t
      , "description" .= toolDescription t
      , "inputSchema" .= toolInputSchema t
      ]
    , maybe [] (\a -> ["annotations" .= a]) (toolAnnotations t)
    ]

-- | A single parameter in a tool's input schema.
data ToolParameter = ToolParameter
  { paramName        :: Text
  , paramType        :: ToolParameterType
  , paramDescription :: Text
  , paramRequired    :: Bool
  } deriving (Show, Eq, Generic)

data ToolParameterType = TString | TInt | TBool | TArray | TObject
  deriving (Show, Eq, Generic)

paramTypeToText :: ToolParameterType -> Text
paramTypeToText TString = "string"
paramTypeToText TInt    = "integer"
paramTypeToText TBool   = "boolean"
paramTypeToText TArray  = "array"
paramTypeToText TObject = "object"

-- | Result returned from executing a tool.
data ToolResult = ToolResult
  { resultContent :: [ToolResultContent]
  , resultIsError :: Bool
  } deriving (Show, Eq, Generic)

data ToolResultContent = TextContent Text
  deriving (Show, Eq, Generic)

instance ToJSON ToolResult where
  toJSON r = object
    [ "content" .= map contentToJson (resultContent r)
    , "isError" .= resultIsError r
    ]
    where
      contentToJson (TextContent t) = object
        [ "type" .= ("text" :: Text)
        , "text" .= t
        ]

-- | Server capabilities advertised during initialization.
data ServerCapabilities = ServerCapabilities
  { capTools :: Bool
  } deriving (Show, Eq, Generic)

instance ToJSON ServerCapabilities where
  toJSON c = object
    [ "tools" .= if capTools c then object [] else Null
    ]

-- | Server information returned during initialization.
data ServerInfo = ServerInfo
  { siName    :: Text
  , siVersion :: Text
  } deriving (Show, Eq, Generic)

instance ToJSON ServerInfo where
  toJSON si = object
    [ "name"    .= siName si
    , "version" .= siVersion si
    ]

-- | Result of the initialize handshake.
data InitializeResult = InitializeResult
  { irProtocolVersion :: Text
  , irCapabilities    :: ServerCapabilities
  , irServerInfo      :: ServerInfo
  } deriving (Show, Eq, Generic)

instance ToJSON InitializeResult where
  toJSON ir = object
    [ "protocolVersion" .= irProtocolVersion ir
    , "capabilities"    .= irCapabilities ir
    , "serverInfo"      .= irServerInfo ir
    ]
