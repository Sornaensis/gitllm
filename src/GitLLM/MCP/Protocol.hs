{-# LANGUAGE OverloadedStrings #-}

module GitLLM.MCP.Protocol
  ( encodeResponse
  , decodeRequest
  , makeResult
  , makeError
  , methodNotFound
  , invalidParams
  , internalError
  ) where

import Data.Aeson
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import GitLLM.MCP.Types

-- | Decode a JSON-RPC request from a lazy ByteString.
decodeRequest :: BL.ByteString -> Either String JsonRpcRequest
decodeRequest = eitherDecode

-- | Encode a JSON-RPC response to a lazy ByteString.
encodeResponse :: JsonRpcResponse -> BL.ByteString
encodeResponse = encode

-- | Build a successful JSON-RPC response.
makeResult :: Maybe JsonRpcId -> Value -> JsonRpcResponse
makeResult rid val = JsonRpcResponse
  { rpcResId     = rid
  , rpcResResult = Just val
  , rpcResError  = Nothing
  }

-- | Build an error JSON-RPC response.
makeError :: Maybe JsonRpcId -> Int -> Text -> Maybe Value -> JsonRpcResponse
makeError rid code msg dat = JsonRpcResponse
  { rpcResId     = rid
  , rpcResResult = Nothing
  , rpcResError  = Just JsonRpcError
      { errCode    = code
      , errMessage = msg
      , errData    = dat
      }
  }

-- | Standard error: method not found (-32601).
methodNotFound :: Maybe JsonRpcId -> Text -> JsonRpcResponse
methodNotFound rid method = makeError rid (-32601) ("Method not found: " <> method) Nothing

-- | Standard error: invalid params (-32602).
invalidParams :: Maybe JsonRpcId -> Text -> JsonRpcResponse
invalidParams rid msg = makeError rid (-32602) msg Nothing

-- | Standard error: internal error (-32603).
internalError :: Maybe JsonRpcId -> Text -> JsonRpcResponse
internalError rid msg = makeError rid (-32603) msg Nothing
