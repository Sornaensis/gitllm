{-# LANGUAGE OverloadedStrings #-}

module MCP.TypesSpec (spec) where

import Data.Aeson
import qualified Data.Aeson.KeyMap as KM
import Data.Maybe (isJust)
import Test.Hspec

import GitLLM.MCP.Types

spec :: Spec
spec = do
  jsonRpcIdSpec
  jsonRpcRequestSpec
  jsonRpcResponseSpec
  toolResultSpec
  serverTypesSpec

-- -------------------------------------------------------------------------
jsonRpcIdSpec :: Spec
jsonRpcIdSpec = describe "JsonRpcId" $ do
  it "round-trips IdInt" $ do
    decode (encode (IdInt 42)) `shouldBe` Just (IdInt 42)

  it "round-trips IdStr" $ do
    decode (encode (IdStr "abc")) `shouldBe` Just (IdStr "abc")

  it "round-trips IdNull" $ do
    decode (encode IdNull) `shouldBe` Just IdNull

  it "decodes integer" $ do
    (decode "42" :: Maybe JsonRpcId) `shouldBe` Just (IdInt 42)

  it "decodes string" $ do
    (decode "\"hello\"" :: Maybe JsonRpcId) `shouldBe` Just (IdStr "hello")

  it "decodes null" $ do
    (decode "null" :: Maybe JsonRpcId) `shouldBe` Just IdNull

  it "rejects boolean" $ do
    (decode "true" :: Maybe JsonRpcId) `shouldBe` Nothing

  it "rejects array" $ do
    (decode "[1]" :: Maybe JsonRpcId) `shouldBe` Nothing

  it "encodes IdInt as Number" $ do
    toJSON (IdInt 7) `shouldBe` Number 7

  it "encodes IdStr as String" $ do
    toJSON (IdStr "x") `shouldBe` String "x"

  it "encodes IdNull as Null" $ do
    toJSON IdNull `shouldBe` Null

-- -------------------------------------------------------------------------
jsonRpcRequestSpec :: Spec
jsonRpcRequestSpec = describe "JsonRpcRequest" $ do
  it "decodes minimal request (no params, no id)" $ do
    let raw = "{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}"
    case eitherDecode raw of
      Right req -> do
        rpcReqMethod req `shouldBe` "ping"
        rpcReqId req `shouldBe` Nothing
        rpcReqParams req `shouldBe` Nothing
      Left err -> expectationFailure err

  it "decodes request with integer id and params" $ do
    let raw = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{}}"
    case eitherDecode raw of
      Right req -> do
        rpcReqMethod req `shouldBe` "tools/list"
        rpcReqId req `shouldBe` Just (IdInt 1)
        rpcReqParams req `shouldBe` Just (object [])
      Left err -> expectationFailure err

  it "decodes request with string id" $ do
    let raw = "{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"method\":\"initialize\"}"
    case eitherDecode raw of
      Right req -> rpcReqId req `shouldBe` Just (IdStr "abc")
      Left err -> expectationFailure err

  it "encodes jsonrpc=2.0 field" $ do
    let req = JsonRpcRequest (Just (IdInt 1)) "ping" Nothing
    case toJSON req of
      Object o -> KM.lookup "jsonrpc" o `shouldBe` Just (String "2.0")
      _        -> expectationFailure "Expected object"

  it "rejects request missing method" $ do
    let raw = "{\"jsonrpc\":\"2.0\",\"id\":1}"
    (eitherDecode raw :: Either String JsonRpcRequest) `shouldSatisfy` isLeft

  it "preserves params in round-trip" $ do
    let params = Just $ object ["key" .= ("val" :: String)]
        req = JsonRpcRequest (Just (IdInt 5)) "test" params
    case eitherDecode (encode req) :: Either String JsonRpcRequest of
      Right req' -> rpcReqParams req' `shouldBe` params
      Left err   -> expectationFailure err
  where
    isLeft (Left _) = True
    isLeft _        = False

-- -------------------------------------------------------------------------
jsonRpcResponseSpec :: Spec
jsonRpcResponseSpec = describe "JsonRpcResponse" $ do
  it "encodes success response" $ do
    let resp = JsonRpcResponse (Just (IdInt 1)) (Just (String "ok")) Nothing
    case toJSON resp of
      Object o -> do
        KM.lookup "jsonrpc" o `shouldBe` Just (String "2.0")
        KM.lookup "result" o `shouldBe` Just (String "ok")
        KM.lookup "error" o `shouldBe` Just Null
      _ -> expectationFailure "Expected object"

  it "encodes error response" $ do
    let err = JsonRpcError (-32600) "Invalid request" Nothing
        resp = JsonRpcResponse (Just (IdInt 2)) Nothing (Just err)
    case toJSON resp of
      Object o -> do
        KM.lookup "result" o `shouldBe` Just Null
        case KM.lookup "error" o of
          Just (Object eo) -> KM.lookup "code" eo `shouldBe` Just (Number (-32600))
          _ -> expectationFailure "Expected error object"
      _ -> expectationFailure "Expected object"

  it "encodes null id" $ do
    let resp = JsonRpcResponse Nothing (Just (String "x")) Nothing
    case toJSON resp of
      Object o -> KM.lookup "id" o `shouldBe` Just Null
      _        -> expectationFailure "Expected object"

-- -------------------------------------------------------------------------
toolResultSpec :: Spec
toolResultSpec = describe "ToolResult / ToolResultContent" $ do
  it "encodes success result" $ do
    let tr = ToolResult [TextContent "hello"] False
    case toJSON tr of
      Object o -> do
        KM.lookup "isError" o `shouldBe` Just (Bool False)
        case KM.lookup "content" o of
          Just (Array arr) -> length arr `shouldBe` 1
          _                -> expectationFailure "Expected content array"
      _ -> expectationFailure "Expected object"

  it "encodes error result" $ do
    let tr = ToolResult [TextContent "bad"] True
    case toJSON tr of
      Object o -> KM.lookup "isError" o `shouldBe` Just (Bool True)
      _        -> expectationFailure "Expected object"

  it "TextContent has type=text and text field" $ do
    let tr = ToolResult [TextContent "output"] False
    case toJSON tr of
      Object o -> case KM.lookup "content" o of
        Just (Array arr) -> case head (foldr (:) [] arr) of
          Object co -> do
            KM.lookup "type" co `shouldBe` Just (String "text")
            KM.lookup "text" co `shouldBe` Just (String "output")
          _ -> expectationFailure "Expected content object"
        _ -> expectationFailure "Expected array"
      _ -> expectationFailure "Expected object"

  it "encodes multiple content items" $ do
    let tr = ToolResult [TextContent "a", TextContent "b", TextContent "c"] False
    case toJSON tr of
      Object o -> case KM.lookup "content" o of
        Just (Array arr) -> length arr `shouldBe` 3
        _                -> expectationFailure "Expected array"
      _ -> expectationFailure "Expected object"

  it "encodes empty content list" $ do
    let tr = ToolResult [] False
    case toJSON tr of
      Object o -> case KM.lookup "content" o of
        Just (Array arr) -> length arr `shouldBe` 0
        _                -> expectationFailure "Expected array"
      _ -> expectationFailure "Expected object"

-- -------------------------------------------------------------------------
serverTypesSpec :: Spec
serverTypesSpec = describe "ServerCapabilities / ServerInfo / InitializeResult" $ do
  it "capabilities tools=True encodes as object" $ do
    case toJSON (ServerCapabilities True) of
      Object o -> case KM.lookup "tools" o of
        Just (Object _) -> pure ()
        _               -> expectationFailure "Expected tools object"
      _ -> expectationFailure "Expected object"

  it "capabilities tools=False encodes as Null" $ do
    case toJSON (ServerCapabilities False) of
      Object o -> KM.lookup "tools" o `shouldBe` Just Null
      _ -> expectationFailure "Expected object"

  it "ServerInfo encodes name and version" $ do
    case toJSON (ServerInfo "gitllm" "0.1.0") of
      Object o -> do
        KM.lookup "name" o `shouldBe` Just (String "gitllm")
        KM.lookup "version" o `shouldBe` Just (String "0.1.0")
      _ -> expectationFailure "Expected object"

  it "InitializeResult encodes all fields" $ do
    let ir = InitializeResult "2024-11-05" (ServerCapabilities True) (ServerInfo "gitllm" "0.1.0")
    case toJSON ir of
      Object o -> do
        KM.lookup "protocolVersion" o `shouldBe` Just (String "2024-11-05")
        KM.lookup "serverInfo" o `shouldSatisfy` isJust
        KM.lookup "capabilities" o `shouldSatisfy` isJust
      _ -> expectationFailure "Expected object"
