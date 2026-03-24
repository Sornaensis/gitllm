{-# LANGUAGE OverloadedStrings #-}

module MCP.ProtocolSpec (spec) where

import Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as BLC
import Data.Maybe (isJust, fromJust)
import qualified Data.Text as T
import Test.Hspec

import GitLLM.MCP.Protocol
import GitLLM.MCP.Types

spec :: Spec
spec = do
  decodeSpec
  encodeSpec
  makeResultSpec
  makeErrorSpec
  standardErrorsSpec

-- -------------------------------------------------------------------------
decodeSpec :: Spec
decodeSpec = describe "decodeRequest" $ do
  it "decodes valid JSON-RPC request" $ do
    let raw = BLC.pack "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}"
    case decodeRequest raw of
      Right req -> rpcReqMethod req `shouldBe` "ping"
      Left err  -> expectationFailure err

  it "fails on invalid JSON" $ do
    decodeRequest "not json" `shouldSatisfy` isLeft

  it "fails on valid JSON but missing method" $ do
    decodeRequest (BLC.pack "{\"jsonrpc\":\"2.0\",\"id\":1}") `shouldSatisfy` isLeft

  it "handles request without id" $ do
    let raw = BLC.pack "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\"}"
    case decodeRequest raw of
      Right req -> rpcReqId req `shouldBe` Nothing
      Left err  -> expectationFailure err

  it "handles request with complex params" $ do
    let raw = BLC.pack "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"git_status\",\"arguments\":{}}}"
    case decodeRequest raw of
      Right req -> do
        rpcReqMethod req `shouldBe` "tools/call"
        rpcReqParams req `shouldSatisfy` isJust
      Left err -> expectationFailure err
  where
    isLeft (Left _) = True
    isLeft _        = False

-- -------------------------------------------------------------------------
encodeSpec :: Spec
encodeSpec = describe "encodeResponse" $ do
  it "produces valid JSON" $ do
    let resp = makeResult (Just (IdInt 1)) (String "ok")
    (decode (encodeResponse resp) :: Maybe Value) `shouldSatisfy` isJust

  it "round-trips through decode" $ do
    let resp = makeResult (Just (IdInt 42)) (object ["key" .= ("val" :: String)])
        encoded = encodeResponse resp
    (decode encoded :: Maybe Value) `shouldSatisfy` isJust

-- -------------------------------------------------------------------------
makeResultSpec :: Spec
makeResultSpec = describe "makeResult" $ do
  it "sets result and no error" $ do
    let resp = makeResult (Just (IdInt 10)) (String "val")
    rpcResResult resp `shouldBe` Just (String "val")
    rpcResError resp `shouldBe` Nothing

  it "preserves the id" $ do
    let resp = makeResult (Just (IdStr "req-1")) (Bool True)
    rpcResId resp `shouldBe` Just (IdStr "req-1")

  it "handles null id" $ do
    let resp = makeResult Nothing (String "ok")
    rpcResId resp `shouldBe` Nothing

-- -------------------------------------------------------------------------
makeErrorSpec :: Spec
makeErrorSpec = describe "makeError" $ do
  it "sets error and no result" $ do
    let resp = makeError (Just (IdInt 2)) (-32600) "Bad" Nothing
    rpcResResult resp `shouldBe` Nothing
    case rpcResError resp of
      Just e -> do
        errCode e `shouldBe` (-32600)
        errMessage e `shouldBe` "Bad"
        errData e `shouldBe` Nothing
      Nothing -> expectationFailure "Expected error"

  it "includes error data when provided" $ do
    let dat = Just (String "details")
        resp = makeError (Just (IdInt 3)) (-32603) "Err" dat
    case rpcResError resp of
      Just e -> errData e `shouldBe` dat
      Nothing -> expectationFailure "Expected error"

-- -------------------------------------------------------------------------
standardErrorsSpec :: Spec
standardErrorsSpec = describe "standard errors" $ do
  it "methodNotFound uses -32601" $ do
    let resp = methodNotFound (Just (IdInt 1)) "foo"
    errCode (fromJust $ rpcResError resp) `shouldBe` (-32601)

  it "methodNotFound includes method name" $ do
    let resp = methodNotFound Nothing "bogus/method"
    errMessage (fromJust $ rpcResError resp) `shouldSatisfy` T.isInfixOf "bogus/method"

  it "invalidParams uses -32602" $ do
    errCode (fromJust $ rpcResError $ invalidParams (Just (IdInt 1)) "bad") `shouldBe` (-32602)

  it "internalError uses -32603" $ do
    errCode (fromJust $ rpcResError $ internalError (Just (IdInt 1)) "oops") `shouldBe` (-32603)

  it "all standard errors have no result" $ do
    rpcResResult (methodNotFound Nothing "x") `shouldBe` Nothing
    rpcResResult (invalidParams Nothing "x") `shouldBe` Nothing
    rpcResResult (internalError Nothing "x") `shouldBe` Nothing
