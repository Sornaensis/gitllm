{-# LANGUAGE OverloadedStrings #-}

module Git.TypesAndHelpersSpec (spec) where

import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import GitLLM.Git.Types
import GitLLM.Git.Runner (textArg)
import GitLLM.Git.Tools.Helpers
import GitLLM.MCP.Types (ToolResult(..), ToolResultContent(..))

spec :: Spec
spec = do
  gitTypesSpec
  getTextParamSpec
  getIntParamSpec
  getBoolParamSpec
  getTextListParamSpec
  gitResultToToolResultSpec
  textArgSpec

-- -------------------------------------------------------------------------
gitTypesSpec :: Spec
gitTypesSpec = describe "GitLLM.Git.Types" $ do
  it "GitContext stores repoPath" $ do
    gitRepoPath (GitContext "/tmp/repo" Nothing) `shouldBe` "/tmp/repo"

  it "GitContext supports Eq" $ do
    GitContext "/a" Nothing `shouldBe` GitContext "/a" Nothing
    GitContext "/a" Nothing `shouldNotBe` GitContext "/b" Nothing

  it "GitError constructors are distinct" $ do
    GitProcessError 1 "fail" `shouldNotBe` GitParseError "fail"
    GitParseError "x" `shouldNotBe` GitValidationError "x"

  it "GitProcessError contains exit code in Show" $ do
    show (GitProcessError 128 "msg") `shouldSatisfy` isInfixOf' "128"

  it "GitParseError contains message in Show" $ do
    show (GitParseError "parse failure") `shouldSatisfy` isInfixOf' "parse failure"

  it "GitValidationError contains message in Show" $ do
    show (GitValidationError "bad input") `shouldSatisfy` isInfixOf' "bad input"
  where
    isInfixOf' needle haystack = needle `T.isInfixOf` T.pack haystack

-- -------------------------------------------------------------------------
getTextParamSpec :: Spec
getTextParamSpec = describe "getTextParam" $ do
  it "extracts a string parameter" $ do
    let p = Just $ object ["name" .= ("hello" :: Text)]
    getTextParam "name" p `shouldBe` Just "hello"

  it "returns Nothing for missing key" $ do
    let p = Just $ object ["other" .= ("x" :: Text)]
    getTextParam "name" p `shouldBe` Nothing

  it "returns Nothing for non-string value" $ do
    let p = Just $ object ["name" .= (42 :: Int)]
    getTextParam "name" p `shouldBe` Nothing

  it "returns Nothing for Nothing params" $ do
    getTextParam "name" Nothing `shouldBe` Nothing

  it "returns Nothing for non-object params" $ do
    getTextParam "name" (Just $ String "bad") `shouldBe` Nothing

  it "handles empty string value" $ do
    let p = Just $ object ["key" .= ("" :: Text)]
    getTextParam "key" p `shouldBe` Just ""

  it "handles unicode values" $ do
    let p = Just $ object ["name" .= ("héllo" :: Text)]
    getTextParam "name" p `shouldBe` Just "héllo"

-- -------------------------------------------------------------------------
getIntParamSpec :: Spec
getIntParamSpec = describe "getIntParam" $ do
  it "extracts an integer parameter" $ do
    let p = Just $ object ["count" .= (10 :: Int)]
    getIntParam "count" p `shouldBe` Just 10

  it "extracts zero" $ do
    let p = Just $ object ["n" .= (0 :: Int)]
    getIntParam "n" p `shouldBe` Just 0

  it "extracts negative" $ do
    let p = Just $ object ["n" .= (-5 :: Int)]
    getIntParam "n" p `shouldBe` Just (-5)

  it "returns Nothing for string value" $ do
    let p = Just $ object ["count" .= ("ten" :: Text)]
    getIntParam "count" p `shouldBe` Nothing

  it "returns Nothing for Nothing params" $ do
    getIntParam "count" Nothing `shouldBe` Nothing

  it "returns Nothing for missing key" $ do
    getIntParam "count" (Just $ object []) `shouldBe` Nothing

  it "returns Nothing for bool value" $ do
    let p = Just $ object ["count" .= True]
    getIntParam "count" p `shouldBe` Nothing

-- -------------------------------------------------------------------------
getBoolParamSpec :: Spec
getBoolParamSpec = describe "getBoolParam" $ do
  it "extracts True" $ do
    let p = Just $ object ["flag" .= True]
    getBoolParam "flag" p `shouldBe` Just True

  it "extracts False" $ do
    let p = Just $ object ["flag" .= False]
    getBoolParam "flag" p `shouldBe` Just False

  it "returns Nothing for non-bool value" $ do
    let p = Just $ object ["flag" .= (1 :: Int)]
    getBoolParam "flag" p `shouldBe` Nothing

  it "returns Nothing for string value" $ do
    let p = Just $ object ["flag" .= ("true" :: Text)]
    getBoolParam "flag" p `shouldBe` Nothing

  it "returns Nothing for Nothing params" $ do
    getBoolParam "flag" Nothing `shouldBe` Nothing

  it "returns Nothing for missing key" $ do
    getBoolParam "flag" (Just $ object []) `shouldBe` Nothing

-- -------------------------------------------------------------------------
getTextListParamSpec :: Spec
getTextListParamSpec = describe "getTextListParam" $ do
  it "extracts a list of strings" $ do
    let p = Just $ object ["paths" .= (["a.txt", "b.txt"] :: [Text])]
    getTextListParam "paths" p `shouldBe` Just ["a.txt", "b.txt"]

  it "returns empty list for empty array" $ do
    let p = Just $ object ["paths" .= ([] :: [Text])]
    getTextListParam "paths" p `shouldBe` Just []

  it "filters non-string items from array" $ do
    let p = Just $ object ["paths" .= [String "a", Number 1, String "b"]]
    getTextListParam "paths" p `shouldBe` Just ["a", "b"]

  it "returns Nothing for non-array value" $ do
    let p = Just $ object ["paths" .= ("single" :: Text)]
    getTextListParam "paths" p `shouldBe` Nothing

  it "returns Nothing for Nothing params" $ do
    getTextListParam "paths" Nothing `shouldBe` Nothing

  it "returns Nothing for missing key" $ do
    getTextListParam "paths" (Just $ object []) `shouldBe` Nothing

  it "handles single-element array" $ do
    let p = Just $ object ["paths" .= (["only.txt"] :: [Text])]
    getTextListParam "paths" p `shouldBe` Just ["only.txt"]

-- -------------------------------------------------------------------------
gitResultToToolResultSpec :: Spec
gitResultToToolResultSpec = describe "gitResultToToolResult" $ do
  it "converts Right to success" $ do
    tr <- gitResultToToolResult (Right "output text")
    resultIsError tr `shouldBe` False
    resultContent tr `shouldBe` [TextContent "output text"]

  it "converts GitProcessError to error" $ do
    tr <- gitResultToToolResult (Left $ GitProcessError 1 "failed")
    resultIsError tr `shouldBe` True
    resultContent tr `shouldBe` [TextContent "failed"]

  it "converts GitParseError to error" $ do
    tr <- gitResultToToolResult (Left $ GitParseError "parse fail")
    resultIsError tr `shouldBe` True
    resultContent tr `shouldBe` [TextContent "parse fail"]

  it "converts GitValidationError to error" $ do
    tr <- gitResultToToolResult (Left $ GitValidationError "invalid")
    resultIsError tr `shouldBe` True
    resultContent tr `shouldBe` [TextContent "invalid"]

  it "preserves empty output" $ do
    tr <- gitResultToToolResult (Right "")
    resultIsError tr `shouldBe` False
    resultContent tr `shouldBe` [TextContent ""]

-- -------------------------------------------------------------------------
textArgSpec :: Spec
textArgSpec = describe "textArg" $ do
  it "converts Text to String" $ do
    textArg "hello" `shouldBe` "hello"

  it "handles empty text" $ do
    textArg "" `shouldBe` ""

  it "handles unicode" $ do
    textArg "héllo wörld" `shouldBe` "héllo wörld"

  it "handles spaces" $ do
    textArg "path with spaces" `shouldBe` "path with spaces"
