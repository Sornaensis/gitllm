{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Property-based tests for parameter parsing, path validation,
-- JSON-RPC serialization, result conversion, and output parsers.
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

import GitLLM.Git.Tools.Status (parseStatusPorcelain)
import GitLLM.Git.Tools.Log (parseLogEntries)
import GitLLM.Git.Tools.Branch (parseBranchLines)
import GitLLM.Git.Tools.Tag (parseTagLines)
import GitLLM.Git.Tools.Stash (parseStashLines)
import GitLLM.Git.Tools.Diff (parseNumstat)
import GitLLM.Git.Tools.Config (parseConfigLines)
import GitLLM.Git.Tools.Remote (parseRemoteLines)
import GitLLM.Git.Tools.Composite (parseChangelogEntries, extractCommitType, filterBranches)

spec :: Spec
spec = do
  paramExtractionProps
  pathValidationProps
  jsonRpcIdProps
  gitResultProps
  textArgProps
  toolDefinitionProps
  parserProps

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

-- =========================================================================
-- Parser property tests
-- =========================================================================

-- | Arbitrary text with no newlines or null bytes — one "field" of data.
newtype FieldText = FieldText { unFieldText :: Text }
  deriving (Show, Eq)

instance Arbitrary FieldText where
  arbitrary = FieldText . T.pack <$> listOf1 (arbitraryPrintableChar `suchThat` (\c -> c /= '\0' && c /= '\n' && c /= '\t'))
  shrink (FieldText t) = [FieldText (T.pack s) | s <- shrink (T.unpack t), not (null s)]

-- | Generate a well-formed log line with the gitllm delimiter.
genLogLine :: Gen Text
genLogLine = do
  fields <- vectorOf 7 (unFieldText <$> arbitrary)
  let d = "---gitllm-field---"
  pure $ T.intercalate d fields

-- | Generate a well-formed tab-delimited branch line.
genBranchLine :: Gen Text
genBranchLine = do
  name    <- unFieldText <$> arbitrary
  sha     <- T.pack <$> vectorOf 7 (elements (['a'..'f'] ++ ['0'..'9']))
  current <- elements ["*", " "]
  upstr   <- elements ["origin/main", ""]
  subject <- unFieldText <$> arbitrary
  pure $ T.intercalate "\t" [name, sha, current, upstr, subject]

-- | Generate a well-formed tab-delimited tag line.
genTagLine :: Gen Text
genTagLine = do
  name    <- unFieldText <$> arbitrary
  sha     <- T.pack <$> vectorOf 7 (elements (['a'..'f'] ++ ['0'..'9']))
  objType <- elements ["commit", "tag"]
  date    <- pure "2026-01-01T00:00:00+00:00"
  subject <- unFieldText <$> arbitrary
  pure $ T.intercalate "\t" [name, sha, objType, date, subject]

-- | Generate a well-formed tab-delimited stash line.
genStashLine :: Gen Text
genStashLine = do
  idx  <- (choose (0, 99) :: Gen Int)
  desc <- unFieldText <$> arbitrary
  pure $ "stash@{" <> T.pack (show idx) <> "}\t" <> desc

-- | Generate a well-formed numstat line (added deleted path).
genNumstatLine :: Gen Text
genNumstatLine = do
  added   <- T.pack . show <$> (choose (0, 999) :: Gen Int)
  deleted <- T.pack . show <$> (choose (0, 999) :: Gen Int)
  path    <- unFieldText <$> arbitrary
  pure $ added <> "\t" <> deleted <> "\t" <> path

-- | Generate a well-formed config line (key=value).
genConfigLine :: Gen Text
genConfigLine = do
  k <- T.pack <$> listOf1 (elements (['a'..'z'] ++ ['.']))
  v <- unFieldText <$> arbitrary
  pure $ k <> "=" <> v

-- | Generate a well-formed remote -v fetch line.
genRemoteFetchLine :: Gen Text
genRemoteFetchLine = do
  name <- T.pack <$> listOf1 (elements ['a'..'z'])
  url  <- unFieldText <$> arbitrary
  pure $ name <> "\t" <> url <> " (fetch)"

-- | Generate a conventional commit subject.
genConventionalSubject :: Gen Text
genConventionalSubject = do
  ctype <- elements ["feat", "fix", "docs", "chore", "refactor", "test", "ci", "style", "perf"]
  msg   <- unFieldText <$> arbitrary
  pure $ ctype <> ": " <> msg

parserProps :: Spec
parserProps = describe "Output parser properties" $ do

  -- -----------------------------------------------------------------------
  -- parseStatusPorcelain
  -- -----------------------------------------------------------------------
  describe "parseStatusPorcelain" $ do
    prop "never crashes on arbitrary input" $ \t ->
      let _ = parseStatusPorcelain (unSafeText t) in True

    it "empty input returns default structure" $
      case parseStatusPorcelain "" of
        Object o -> do
          KM.lookup "files" o `shouldBe` Just (toJSON ([] :: [Value]))
          KM.lookup "untracked" o `shouldBe` Just (toJSON ([] :: [Text]))
        _ -> expectationFailure "expected object"

    prop "result is always an Object" $ \t ->
      case parseStatusPorcelain (unSafeText t) of
        Object _ -> True
        _        -> False

  -- -----------------------------------------------------------------------
  -- parseLogEntries
  -- -----------------------------------------------------------------------
  describe "parseLogEntries" $ do
    prop "never crashes on arbitrary input" $ \t ->
      let _ = parseLogEntries (unSafeText t) in True

    it "empty input returns []" $
      parseLogEntries "" `shouldBe` []

    prop "output length <= non-empty input lines" $ \t ->
      let input = unSafeText t
          lineCount = length (filter (not . T.null) (T.lines input))
      in length (parseLogEntries input) <= lineCount

    prop "well-formed lines produce objects with expected keys" $
      forAll (listOf1 genLogLine) $ \lines' ->
        let input = T.unlines lines'
            entries = parseLogEntries input
        in conjoin
          [ counterexample ("entry " ++ show i) $
            case e of
              Object o -> counterexample "missing hash" (KM.member "hash" o)
                     .&&. counterexample "missing author" (KM.member "author" o)
                     .&&. counterexample "missing subject" (KM.member "subject" o)
              _ -> counterexample "not an object" False
          | (i, e) <- zip [(0::Int)..] entries
          ]

  -- -----------------------------------------------------------------------
  -- parseBranchLines
  -- -----------------------------------------------------------------------
  describe "parseBranchLines" $ do
    prop "never crashes on arbitrary input" $ \t ->
      let _ = parseBranchLines (unSafeText t) in True

    it "empty input returns []" $
      parseBranchLines "" `shouldBe` []

    prop "well-formed lines produce objects with name and sha" $
      forAll (listOf1 genBranchLine) $ \lines' ->
        let input = T.unlines lines'
            branches = parseBranchLines input
        in conjoin
          [ case b of
              Object o -> counterexample "missing name" (KM.member "name" o)
                     .&&. counterexample "missing sha" (KM.member "sha" o)
                     .&&. counterexample "missing current" (KM.member "current" o)
              _ -> counterexample "not an object" False
          | b <- branches
          ]

    prop "current flag is always a Bool" $
      forAll (listOf1 genBranchLine) $ \lines' ->
        let input = T.unlines lines'
            branches = parseBranchLines input
        in conjoin
          [ case b of
              Object o -> case KM.lookup "current" o of
                Just (Bool _) -> property True
                _             -> counterexample "current is not Bool" False
              _ -> counterexample "not an object" False
          | b <- branches
          ]

  -- -----------------------------------------------------------------------
  -- parseTagLines
  -- -----------------------------------------------------------------------
  describe "parseTagLines" $ do
    prop "never crashes on arbitrary input" $ \t ->
      let _ = parseTagLines (unSafeText t) in True

    it "empty input returns []" $
      parseTagLines "" `shouldBe` []

    prop "well-formed lines produce objects with name, sha, type" $
      forAll (listOf1 genTagLine) $ \lines' ->
        let input = T.unlines lines'
            tags = parseTagLines input
        in conjoin
          [ case tag of
              Object o -> counterexample "missing name" (KM.member "name" o)
                     .&&. counterexample "missing sha" (KM.member "sha" o)
                     .&&. counterexample "missing type" (KM.member "type" o)
              _ -> counterexample "not an object" False
          | tag <- tags
          ]

  -- -----------------------------------------------------------------------
  -- parseStashLines
  -- -----------------------------------------------------------------------
  describe "parseStashLines" $ do
    prop "never crashes on arbitrary input" $ \t ->
      let _ = parseStashLines (unSafeText t) in True

    it "empty input returns []" $
      parseStashLines "" `shouldBe` []

    prop "well-formed lines produce objects with ref and description" $
      forAll (listOf1 genStashLine) $ \lines' ->
        let input = T.unlines lines'
            stashes = parseStashLines input
        in conjoin
          [ case s of
              Object o -> counterexample "missing ref" (KM.member "ref" o)
                     .&&. counterexample "missing description" (KM.member "description" o)
              _ -> counterexample "not an object" False
          | s <- stashes
          ]

  -- -----------------------------------------------------------------------
  -- parseNumstat
  -- -----------------------------------------------------------------------
  describe "parseNumstat" $ do
    prop "never crashes on arbitrary input" $ \t ->
      let _ = parseNumstat (unSafeText t) in True

    it "empty input returns []" $
      parseNumstat "" `shouldBe` []

    prop "well-formed lines produce objects with added, deleted, path" $
      forAll (listOf1 genNumstatLine) $ \lines' ->
        let input = T.unlines lines'
            files = parseNumstat input
        in conjoin
          [ case f of
              Object o -> counterexample "missing added" (KM.member "added" o)
                     .&&. counterexample "missing deleted" (KM.member "deleted" o)
                     .&&. counterexample "missing path" (KM.member "path" o)
              _ -> counterexample "not an object" False
          | f <- files
          ]

  -- -----------------------------------------------------------------------
  -- parseConfigLines
  -- -----------------------------------------------------------------------
  describe "parseConfigLines" $ do
    prop "never crashes on arbitrary input" $ \t ->
      let _ = parseConfigLines (unSafeText t) in True

    it "empty input returns []" $
      parseConfigLines "" `shouldBe` []

    prop "well-formed lines produce objects with key and value" $
      forAll (listOf1 genConfigLine) $ \lines' ->
        let input = T.unlines lines'
            configs = parseConfigLines input
        in conjoin
          [ case c of
              Object o -> counterexample "missing key" (KM.member "key" o)
                     .&&. counterexample "missing value" (KM.member "value" o)
              _ -> counterexample "not an object" False
          | c <- configs
          ]

  -- -----------------------------------------------------------------------
  -- parseRemoteLines
  -- -----------------------------------------------------------------------
  describe "parseRemoteLines" $ do
    prop "never crashes on arbitrary input" $ \t ->
      let _ = parseRemoteLines (unSafeText t) in True

    it "empty input returns []" $
      parseRemoteLines "" `shouldBe` []

    prop "well-formed fetch lines produce objects with name and url" $
      forAll (listOf1 genRemoteFetchLine) $ \lines' ->
        let input = T.unlines lines'
            remotes = parseRemoteLines input
        in conjoin
          [ case r of
              Object o -> counterexample "missing name" (KM.member "name" o)
                     .&&. counterexample "missing url" (KM.member "url" o)
              _ -> counterexample "not an object" False
          | r <- remotes
          ]

    prop "only keeps (fetch) lines, not (push)" $
      forAll (listOf1 genRemoteFetchLine) $ \fetchLines ->
        let pushLines = map (T.replace "(fetch)" "(push)") fetchLines
            input = T.unlines (fetchLines ++ pushLines)
            remotes = parseRemoteLines input
        in length remotes === length fetchLines

  -- -----------------------------------------------------------------------
  -- extractCommitType
  -- -----------------------------------------------------------------------
  describe "extractCommitType" $ do
    prop "never crashes on arbitrary input" $ \t ->
      let _ = extractCommitType (unSafeText t) in True

    prop "returns 'other' for empty input" $
      extractCommitType "" === "other"

    prop "conventional commits extract the type prefix" $
      forAll genConventionalSubject $ \subject ->
        let result = extractCommitType subject
        in counterexample (T.unpack $ "subject=" <> subject <> " type=" <> result) $
          result `elem` ["feat", "fix", "docs", "chore", "refactor", "test", "ci", "style", "perf"]

    prop "result is never empty" $ \t ->
      not (T.null (extractCommitType (unSafeText t)))

  -- -----------------------------------------------------------------------
  -- filterBranches
  -- -----------------------------------------------------------------------
  describe "filterBranches" $ do
    prop "never crashes on arbitrary input" $ \a b c ->
      let _ = filterBranches (unSafeText a) (unSafeText b) (unSafeText c) in True

    it "empty input returns []" $
      filterBranches "main" "main" "" `shouldBe` []

    prop "never includes current or target branch" $ \t ->
      forAll (elements ["main", "master", "develop"]) $ \branch ->
        let result = filterBranches branch branch (unSafeText t)
        in counterexample (show result) $
          all (\b -> T.strip b /= branch) result

    prop "never includes HEAD entries" $ \t ->
      let result = filterBranches "x" "x" (unSafeText t)
      in all (not . T.isInfixOf "HEAD") result

  -- -----------------------------------------------------------------------
  -- parseChangelogEntries
  -- -----------------------------------------------------------------------
  describe "parseChangelogEntries" $ do
    prop "never crashes on arbitrary input" $ \t ->
      let _ = parseChangelogEntries "---cl---" (unSafeText t) in True

    it "empty input returns []" $
      parseChangelogEntries "---cl---" "" `shouldBe` []

    prop "well-formed entries produce objects with hash and type" $
      forAll (listOf1 genConventionalSubject) $ \subjects ->
        let delim = "---cl---"
            mkLine subj = delim <> "abc123" <> delim <> "abc" <> delim <> "Author" <> delim <> "2026-01-01" <> delim <> subj
            input = T.unlines (map mkLine subjects)
            entries = parseChangelogEntries delim input
        in conjoin
          [ case e of
              Object o -> counterexample "missing hash" (KM.member "hash" o)
                     .&&. counterexample "missing type" (KM.member "type" o)
                     .&&. counterexample "missing author" (KM.member "author" o)
              _ -> counterexample "not an object" False
          | e <- entries
          ]
