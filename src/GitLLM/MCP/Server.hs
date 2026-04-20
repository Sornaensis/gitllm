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
import Data.IORef (newIORef)
import qualified Data.Text as T
import System.IO (hFlush, hSetBuffering, hSetEncoding, hIsEOF, stdin, stdout, BufferMode(..), utf8)

import GitLLM.MCP.Types
import GitLLM.MCP.Protocol
import GitLLM.MCP.Router
import GitLLM.Git.Types (ServerState(..))

-- | Run the MCP server on the configured transport.
-- The server starts with no repository root set — the LLM must call
-- git_set_repo before any other tool will work.
runServer :: ServerConfig -> IO ()
runServer cfg = do
  repoRef <- newIORef Nothing
  let state = ServerState { stateRepoPath = repoRef, stateTimeout = cfgTimeout cfg }
  case cfgTransport cfg of
    "stdio" -> runStdio cfg state
    _       -> putStrLn $ "Unsupported transport: " <> cfgTransport cfg

-- | Run the server over stdin/stdout (JSON-RPC over stdio).
runStdio :: ServerConfig -> ServerState -> IO ()
runStdio cfg state = do
  hSetBuffering stdin  LineBuffering
  hSetBuffering stdout LineBuffering
  hSetEncoding stdin  utf8
  hSetEncoding stdout utf8
  loop
  where
    loop = do
      msg <- readMessage
      case msg of
        Nothing -> pure ()
        Just body -> do
          processMessage cfg state body
          loop

readMessage :: IO (Maybe BL.ByteString)
readMessage = do
  eof <- hIsEOF stdin
  if eof
    then pure Nothing
    else Just . BL.fromStrict <$> BS8.hGetLine stdin

-- | Process a single JSON-RPC message body.
processMessage :: ServerConfig -> ServerState -> BL.ByteString -> IO ()
processMessage cfg state body
  | BL.null body = pure ()
  | otherwise = do
      case decodeRequest body of
        Left err -> do
          let resp = makeError Nothing (-32700) "Parse error" (Just $ toJSON err)
          sendResponse resp
        Right req -> do
          resp <- handleRequest cfg state req
            `catch` \(e :: SomeException) ->
              pure . Just $ internalError (rpcReqId req) (T.pack $ show e)
          case resp of
            Nothing -> pure ()
            Just r  -> sendResponse r

-- | Send a JSON-RPC response to stdout.
sendResponse :: JsonRpcResponse -> IO ()
sendResponse resp = do
  BL.putStr (encodeResponse resp)
  BS8.putStrLn ""
  hFlush stdout

-- | Handle a single JSON-RPC request.
handleRequest :: ServerConfig -> ServerState -> JsonRpcRequest -> IO (Maybe JsonRpcResponse)
handleRequest cfg state req = case rpcReqMethod req of

  "initialize" ->
    pure . Just $ makeResult (rpcReqId req) $ toJSON InitializeResult
      { irProtocolVersion = "2024-11-05"
      , irCapabilities    = ServerCapabilities { capTools = True }
      , irServerInfo      = ServerInfo
          { siName    = cfgServerName cfg
          , siVersion = cfgVersion cfg
          }
      }

  "notifications/initialized" ->
    pure Nothing

  "initialized" ->
    pure Nothing

  "tools/list" ->
    pure . Just $ makeResult (rpcReqId req) $ object
      [ "tools" .= map toJSON allToolDefinitions
      ]

  "tools/call" -> do
    case rpcReqParams req of
      Nothing -> pure . Just $ invalidParams (rpcReqId req) "Missing params for tools/call"
      Just (Object o) -> do
        case (KM.lookup "name" o, KM.lookup "arguments" o) of
          (Just (String toolName'), args) -> do
            result <- routeRequest state toolName' args
            pure . Just $ makeResult (rpcReqId req) (toJSON result)
          _ -> pure . Just $ invalidParams (rpcReqId req) "tools/call requires 'name' field"
      _ -> pure . Just $ invalidParams (rpcReqId req) "params must be an object"

  "ping" ->
    pure . Just $ makeResult (rpcReqId req) (object [])

  other ->
    pure . Just $ methodNotFound (rpcReqId req) other
