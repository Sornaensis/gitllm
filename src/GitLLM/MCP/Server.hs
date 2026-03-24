{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module GitLLM.MCP.Server
  ( runServer
  ) where

import Control.Exception (SomeException, catch)
import Data.Aeson
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (getCurrentDirectory)
import System.IO (hFlush, hSetBuffering, hSetEncoding, hIsEOF, stdin, stdout, BufferMode(..), utf8)

import GitLLM.MCP.Types
import GitLLM.MCP.Protocol
import GitLLM.MCP.Router
import GitLLM.Git.Types (GitContext(..))

-- | Run the MCP server on the configured transport.
runServer :: ServerConfig -> IO ()
runServer cfg = do
  repoPath <- maybe getCurrentDirectory pure (cfgRepoPath cfg)
  let ctx = GitContext { gitRepoPath = repoPath }
  case cfgTransport cfg of
    "stdio" -> runStdio cfg ctx
    _       -> putStrLn $ "Unsupported transport: " <> cfgTransport cfg

-- | Run the server over stdin/stdout (JSON-RPC over stdio).
runStdio :: ServerConfig -> GitContext -> IO ()
runStdio cfg ctx = do
  hSetBuffering stdin  LineBuffering
  hSetBuffering stdout LineBuffering
  hSetEncoding stdin  utf8
  hSetEncoding stdout utf8
  loop
  where
    loop = do
      eof <- hIsEOF stdin
      if eof
        then pure ()
        else do
          line <- BS8.hGetLine stdin
          processLine cfg ctx (BL.fromStrict line)
          loop

-- | Process a single JSON-RPC line.
processLine :: ServerConfig -> GitContext -> BL.ByteString -> IO ()
processLine cfg ctx line
  | BL.null line = pure ()
  | otherwise = do
      case decodeRequest line of
        Left err -> do
          let resp = makeError Nothing (-32700) "Parse error" (Just $ toJSON err)
          sendResponse resp
        Right req -> do
          resp <- handleRequest cfg ctx req
            `catch` \(e :: SomeException) ->
              pure $ internalError (rpcReqId req) (T.pack $ show e)
          sendResponse resp

-- | Send a JSON-RPC response to stdout.
sendResponse :: JsonRpcResponse -> IO ()
sendResponse resp = do
  BL.putStr (encodeResponse resp)
  BS8.putStrLn ""
  hFlush stdout

-- | Handle a single JSON-RPC request.
handleRequest :: ServerConfig -> GitContext -> JsonRpcRequest -> IO JsonRpcResponse
handleRequest cfg ctx req = case rpcReqMethod req of

  "initialize" ->
    pure $ makeResult (rpcReqId req) $ toJSON InitializeResult
      { irProtocolVersion = "2024-11-05"
      , irCapabilities    = ServerCapabilities { capTools = True }
      , irServerInfo      = ServerInfo
          { siName    = cfgServerName cfg
          , siVersion = cfgVersion cfg
          }
      }

  "initialized" ->
    -- Notification; no response needed, but we send acknowledgment
    pure $ makeResult (rpcReqId req) (toJSON Null)

  "tools/list" ->
    pure $ makeResult (rpcReqId req) $ object
      [ "tools" .= map toJSON allToolDefinitions
      ]

  "tools/call" -> do
    case rpcReqParams req of
      Nothing -> pure $ invalidParams (rpcReqId req) "Missing params for tools/call"
      Just (Object o) -> do
        case (KM.lookup "name" o, KM.lookup "arguments" o) of
          (Just (String toolName'), args) -> do
            result <- routeRequest ctx toolName' args
            pure $ makeResult (rpcReqId req) (toJSON result)
          _ -> pure $ invalidParams (rpcReqId req) "tools/call requires 'name' field"
      _ -> pure $ invalidParams (rpcReqId req) "params must be an object"

  "ping" ->
    pure $ makeResult (rpcReqId req) (object [])

  other ->
    pure $ methodNotFound (rpcReqId req) other
