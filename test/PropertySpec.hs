{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Property-based tests for parameter parsing, path validation,
-- JSON-RPC serialization, and result conversion.
module PropertySpec (spec) where

import Data.Aeson hiding (Success)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import Data.String (fromString)
import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck

import GitLLM.Git.Types
import GitLLM.Git.Runner (textArg)
import GitLLM.Git.Tools.Helpers
import GitLLM.MCP.Types

spec :: Spec
spec = do
  paramExtractionProps
  pathValidationProps
  jsonRpcIdProps
  gitResultProps
  textArgProps
  toolDefinitionProps

-- =========================================================================
-- Generators
-- =========================================================================

-- | Arbitrary non-empty text (no null bytes).
newtype SafeText = SafeText { unSafeText :: Text }
  deriving (Show, Eq)

instance Arbitrary SafeText where
  arbitrary = SafeText . T.pack <$> listOf1 (arbitraryPrintableChar `suchThat` (/= '\0'))
  shrink (SafeText t) = [SafeText (T.pack s) | s <- shrink (T.unpack t), not (null s)]

-- | Arbitrary text suitable for use as a JSON key.
newtype JsonKey = JsonKey { unJsonKey :: Text }
  deriving (Show, Eq)

instance Arbitrary JsonKey where
  arbitrary = JsonKey . T.pack <$> listOf1 (elements (['a'..'z'] ++ ['_']))
  shrink (JsonKey t) = [JsonKey (T.pack s) | s <- shrink (T.unpack t), not (null s)]

-- | A file path component that's safe (no "..", no leading "/").
newtype SafePath = SafePath { unSafePath :: Text }
  deriving (Show, Eq)

instance Arbitrary SafePath where
  arbitrary = do
    segments <- listOf1 (listOf1 (elements (['a'..'z'] ++ ['0'..'9'] ++ ['-', '_'])))
    pure $ SafePath $ T.intercalate "/" $ map T.pack segments
  shrink (SafePath t) = [SafePath (T.pack s) | s <- shrink (T.unpack t), not (null s), not (".." `T.isInfixOf` T.pack s)]

-- | A path that always contains "..".
newtype TraversalPath = TraversalPath { unTraversalPath :: Text }
  deriving (Show, Eq)

instance Arbitrary TraversalPath where
  arbitrary = do
    prefix <- elements ["", "foo/", "a/b/"]
    suffix <- elements ["", "/bar", "/c/d"]
    pure $ TraversalPath $ T.pack prefix <> ".." <> T.pack suffix

instance Arbitrary JsonRpcId where
  arbitrary = oneof
    [ IdInt <$> arbitrary
    , IdStr . unSafeText <$> arbitrary
    , pure IdNull
    ]

-- =========================================================================
-- Parameter extraction properties
-- =========================================================================
paramExtractionProps :: Spec
paramExtractionProps = describe "Parameter extraction properties" $ do

  prop "getTextParam round-trips any text value" $ \k v ->
    let params = Just $ object [fromText (unJsonKey k) .= unSafeText v]
    in getTextParam (unJsonKey k) params === Just (unSafeText v)

  prop "getTextParam returns Nothing for missing keys" $ \k v ->
    let params = Just $ object [fromText (unJsonKey k) .= unSafeText v]
    in getTextParam "definitely_not_a_key_zzz" params === Nothing

  prop "getTextParam returns Nothing for Nothing" $ \k ->
    getTextParam (unJsonKey k) Nothing === (Nothing :: Maybe Text)

  prop "getIntParam round-trips any integer" $ \k (n :: Int) ->
    let params = Just $ object [fromText (unJsonKey k) .= n]
    in getIntParam (unJsonKey k) params === Just n

  prop "getIntParam returns Nothing for text values" $ \k v ->
    let params = Just $ object [fromText (unJsonKey k) .= unSafeText v]
    in getIntParam (unJsonKey k) params === Nothing

  prop "getBoolParam round-trips booleans" $ \k (b :: Bool) ->
    let params = Just $ object [fromText (unJsonKey k) .= b]
    in getBoolParam (unJsonKey k) params === Just b

  prop "getBoolParam returns Nothing for non-bool" $ \k (n :: Int) ->
    let params = Just $ object [fromText (unJsonKey k) .= n]
    in getBoolParam (unJsonKey k) params === Nothing

  prop "getTextListParam round-trips text lists" $ \k ->
    forAll (listOf (unSafeText <$> arbitrary)) $ \vs ->
      let params = Just $ object [fromText (unJsonKey k) .= vs]
      in getTextListParam (unJsonKey k) params === Just vs

  prop "getTextListParam returns Nothing for non-array" $ \k v ->
    let params = Just $ object [fromText (unJsonKey k) .= unSafeText v]
    in getTextListParam (unJsonKey k) params === Nothing

  where
    fromText = fromString . T.unpack

-- =========================================================================
-- Path validation properties
-- =========================================================================
pathValidationProps :: Spec
pathValidationProps = describe "Path validation properties" $ do

  prop "safe paths are accepted" $ \p ->
    validatePath (unSafePath p) === Right (unSafePath p)

  prop "paths with .. are always rejected" $ \p ->
    case validatePath (unTraversalPath p) of
      Left err -> counterexample (T.unpack err) True
      Right _  -> counterexample "Expected rejection" False

  prop "absolute paths are rejected" $ \s ->
    let p = "/" <> unSafeText s
    in case validatePath p of
      Left _ -> property True
      Right _ -> property False

  prop "validatePaths accepts all-safe lists" $
    forAll (listOf (unSafePath <$> arbitrary)) $ \ps ->
      validatePaths ps === Right ps

  prop "validatePaths rejects if any path has .." $
    forAll (listOf (unSafePath <$> arbitrary)) $ \safePaths ->
      forAll (arbitrary :: Gen TraversalPath) $ \tp ->
        forAll (choose (0, length safePaths)) $ \i ->
          let mixed = take i safePaths ++ [unTraversalPath tp] ++ drop i safePaths
          in case validatePaths mixed of
            Left _  -> property True
            Right _ -> property False

  prop "validatePath and validatePaths agree on singletons" $ \s ->
    let p = unSafeText s
    in case (validatePath p, validatePaths [p]) of
      (Right _, Right _) -> property True
      (Left _,  Left _)  -> property True
      _                  -> property False

-- =========================================================================
-- JSON-RPC ID properties
-- =========================================================================
jsonRpcIdProps :: Spec
jsonRpcIdProps = describe "JsonRpcId properties" $ do

  prop "JSON round-trip preserves IdInt" $ \(n :: Int) ->
    let v = toJSON (IdInt n)
    in fromJSON v === Aeson.Success (IdInt n)

  prop "JSON round-trip preserves IdStr" $ \s ->
    let v = toJSON (IdStr (unSafeText s))
    in fromJSON v === Aeson.Success (IdStr (unSafeText s))

  it "JSON round-trip preserves IdNull" $
    fromJSON (toJSON IdNull) `shouldBe` Aeson.Success IdNull

  prop "JSON round-trip preserves arbitrary JsonRpcId" $ \(i :: JsonRpcId) ->
    fromJSON (toJSON i) === Aeson.Success i

-- =========================================================================
-- GitResult → ToolResult properties
-- =========================================================================
gitResultProps :: Spec
gitResultProps = describe "gitResultToToolResult properties" $ do

  prop "Right always produces isError=False" $ \t -> ioProperty $ do
    tr <- gitResultToToolResult (Right (unSafeText t))
    pure $ resultIsError tr === False

  prop "Right preserves the output text" $ \t -> ioProperty $ do
    tr <- gitResultToToolResult (Right (unSafeText t))
    pure $ resultContent tr === [TextContent (unSafeText t)]

  prop "GitProcessError always produces isError=True" $ \(n :: Int) msg -> ioProperty $ do
    tr <- gitResultToToolResult (Left $ GitProcessError n (unSafeText msg))
    pure $ resultIsError tr === True

  prop "GitParseError always produces isError=True" $ \msg -> ioProperty $ do
    tr <- gitResultToToolResult (Left $ GitParseError (unSafeText msg))
    pure $ resultIsError tr === True

  prop "GitValidationError always produces isError=True" $ \msg -> ioProperty $ do
    tr <- gitResultToToolResult (Left $ GitValidationError (unSafeText msg))
    pure $ resultIsError tr === True

  prop "GitTimeoutError always produces isError=True" $ \(Positive n) -> ioProperty $ do
    tr <- gitResultToToolResult (Left $ GitTimeoutError n)
    pure $ resultIsError tr === True

  prop "GitTimeoutError message contains seconds" $ \(Positive n) -> ioProperty $ do
    tr <- gitResultToToolResult (Left $ GitTimeoutError n)
    let [TextContent msg] = resultContent tr
    pure $ T.isInfixOf (T.pack $ show n) msg

-- =========================================================================
-- textArg properties
-- =========================================================================
textArgProps :: Spec
textArgProps = describe "textArg properties" $ do

  prop "T.pack . textArg = id" $ \t ->
    T.pack (textArg (unSafeText t)) === unSafeText t

  prop "textArg preserves length" $ \t ->
    length (textArg (unSafeText t)) === T.length (unSafeText t)

-- =========================================================================
-- Tool definition properties
-- =========================================================================
toolDefinitionProps :: Spec
toolDefinitionProps = describe "ToolDefinition properties" $ do

  prop "mkSchema always produces object type" $ \k ->
    let schema = mkSchema [Key.fromText (unJsonKey k) .= ("string" :: Text)] []
    in case schema of
      Object o -> counterexample "missing 'type' key" $
        KM.lookup (Key.fromString "type") o === Just (String "object")
      _ -> counterexample "schema is not an object" False

  prop "mkSchema includes required when non-empty" $ \r ->
    let schema = mkSchema [] [unSafeText r]
    in case schema of
      Object o -> counterexample "missing 'required'" $
        case KM.lookup (Key.fromString "required") o of
          Just (Array _) -> property True
          _              -> property False
      _ -> property False

  prop "mkSchema omits required when empty" $
    let schema = mkSchema [] []
    in case schema of
      Object o -> KM.lookup (Key.fromString "required") o === Nothing
      _        -> property False
