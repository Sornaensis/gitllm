{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for individual tool modules.
-- Tests tool definitions, parameter handling, and JSON output parsing
-- without requiring a real git repository.
module Git.ToolUnitSpec (spec) where

import Data.Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import Data.List (nub)
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Test.Hspec

import GitLLM.MCP.Types
import GitLLM.Git.Tools.Helpers

import qualified GitLLM.Git.Tools.Status    as Status
import qualified GitLLM.Git.Tools.Log       as Log
import qualified GitLLM.Git.Tools.Diff      as Diff
import qualified GitLLM.Git.Tools.Branch    as Branch
import qualified GitLLM.Git.Tools.Commit    as Commit
import qualified GitLLM.Git.Tools.Staging   as Staging
import qualified GitLLM.Git.Tools.Remote    as Remote
import qualified GitLLM.Git.Tools.Stash     as Stash
import qualified GitLLM.Git.Tools.Tag       as Tag
import qualified GitLLM.Git.Tools.Merge     as Merge
import qualified GitLLM.Git.Tools.Rebase    as Rebase
import qualified GitLLM.Git.Tools.Cherry    as Cherry
import qualified GitLLM.Git.Tools.Worktree  as Worktree
import qualified GitLLM.Git.Tools.Submodule as Submodule
import qualified GitLLM.Git.Tools.Config    as Config
import qualified GitLLM.Git.Tools.Blame     as Blame
import qualified GitLLM.Git.Tools.Bisect    as Bisect
import qualified GitLLM.Git.Tools.Clean     as Clean
import qualified GitLLM.Git.Tools.Reset     as Reset
import qualified GitLLM.Git.Tools.Reflog    as Reflog
import qualified GitLLM.Git.Tools.Search    as Search
import qualified GitLLM.Git.Tools.Patch     as Patch
import qualified GitLLM.Git.Tools.Archive   as Archive
import qualified GitLLM.Git.Tools.Hooks     as Hooks
import qualified GitLLM.Git.Tools.Inspect   as Inspect

import GitLLM.Git.Tools.Status (parseStatusPorcelain)
import GitLLM.Git.Tools.Log (parseLogEntries)
import GitLLM.Git.Tools.Branch (parseBranchLines)
import GitLLM.Git.Tools.Tag (parseTagLines)
import GitLLM.Git.Tools.Stash (parseStashLines)
import GitLLM.Git.Tools.Diff (parseNumstat)
import GitLLM.Git.Tools.Config (parseConfigLines)
import GitLLM.Git.Tools.Remote (parseRemoteLines)

spec :: Spec
spec = do
  toolDefinitionSpec
  jsonOutputHelpersSpec
  statusParsingSpec
  logParsingSpec
  branchParsingSpec
  tagParsingSpec
  stashParsingSpec
  diffStatParsingSpec
  configParsingSpec
  remoteParsingSpec
  wantsJsonSpec
  outputParamSpec

-- =========================================================================
-- Tool definition validation per module
-- =========================================================================
toolDefinitionSpec :: Spec
toolDefinitionSpec = describe "Tool definitions" $ do
  let allTools = concat
        [ Status.tools, Log.tools, Diff.tools, Branch.tools
        , Commit.tools, Staging.tools, Remote.tools, Stash.tools
        , Tag.tools, Merge.tools, Rebase.tools, Cherry.tools
        , Worktree.tools, Submodule.tools, Config.tools, Blame.tools
        , Bisect.tools, Clean.tools, Reset.tools, Reflog.tools
        , Search.tools, Patch.tools, Archive.tools, Hooks.tools
        , Inspect.tools
        ]

  describe "Status" $ toolModuleTests Status.tools 2
  describe "Log" $ toolModuleTests Log.tools 4
  describe "Diff" $ toolModuleTests Diff.tools 4
  describe "Branch" $ toolModuleTests Branch.tools 7
  describe "Commit" $ toolModuleTests Commit.tools 3
  describe "Staging" $ toolModuleTests Staging.tools 4
  describe "Remote" $ toolModuleTests Remote.tools 6
  describe "Stash" $ toolModuleTests Stash.tools 5
  describe "Tag" $ toolModuleTests Tag.tools 3
  describe "Merge" $ toolModuleTests Merge.tools 3
  describe "Rebase" $ toolModuleTests Rebase.tools 4
  describe "Cherry" $ toolModuleTests Cherry.tools 2
  describe "Worktree" $ toolModuleTests Worktree.tools 3
  describe "Submodule" $ toolModuleTests Submodule.tools 4
  describe "Config" $ toolModuleTests Config.tools 3
  describe "Blame" $ toolModuleTests Blame.tools 1
  describe "Bisect" $ toolModuleTests Bisect.tools 4
  describe "Clean" $ toolModuleTests Clean.tools 2
  describe "Reset" $ toolModuleTests Reset.tools 2
  describe "Reflog" $ toolModuleTests Reflog.tools 1
  describe "Search" $ toolModuleTests Search.tools 2
  describe "Patch" $ toolModuleTests Patch.tools 2
  describe "Archive" $ toolModuleTests Archive.tools 1
  describe "Hooks" $ toolModuleTests Hooks.tools 1
  describe "Inspect" $ toolModuleTests Inspect.tools 5

  it "all tool names are globally unique" $ do
    let names = map toolName allTools
    length names `shouldBe` length (nub names)

  it "all tool names start with git_" $ do
    let badNames = filter (not . T.isPrefixOf "git_") (map toolName allTools)
    badNames `shouldBe` []

  it "all tools have annotations" $ do
    let unannotated = filter (not . isJust . toolAnnotations) allTools
    map toolName unannotated `shouldBe` []

-- | Standard checks for a tool module's definitions.
toolModuleTests :: [ToolDefinition] -> Int -> Spec
toolModuleTests tools' expectedCount = do
  it ("exports exactly " ++ show expectedCount ++ " tools") $
    length tools' `shouldBe` expectedCount

  it "all names are unique within module" $ do
    let names = map toolName tools'
    length names `shouldBe` length (nub names)

  it "all descriptions are non-empty" $ do
    let empties = filter (T.null . toolDescription) tools'
    map toolName empties `shouldBe` []

  it "all schemas have type=object" $ do
    mapM_ (\td -> case toolInputSchema td of
      Object o -> KM.lookup "type" o `shouldBe` Just (String "object")
      _        -> expectationFailure $ "Bad schema for " ++ T.unpack (toolName td)
      ) tools'

  it "all schemas have properties" $ do
    mapM_ (\td -> case toolInputSchema td of
      Object o -> KM.lookup "properties" o `shouldSatisfy` isJust
      _        -> expectationFailure $ "Bad schema for " ++ T.unpack (toolName td)
      ) tools'

  it "required fields reference existing properties" $ do
    mapM_ (\td -> case toolInputSchema td of
      Object o -> do
        let props = case KM.lookup "properties" o of
              Just (Object p) -> map Key.toText $ KM.keys p
              _               -> []
        case KM.lookup "required" o of
          Just (Array reqs) -> mapM_ (\r -> case r of
            String rn -> rn `shouldSatisfy` (`elem` props)
            _         -> expectationFailure "required item is not a string"
            ) reqs
          _ -> pure ()
      _        -> expectationFailure $ "Bad schema for " ++ T.unpack (toolName td)
      ) tools'

-- =========================================================================
-- JSON output helper tests
-- =========================================================================
jsonOutputHelpersSpec :: Spec
jsonOutputHelpersSpec = describe "JSON output helpers" $ do
  describe "wantsJson" $ do
    it "returns True for output=json" $
      wantsJson (Just $ object ["output" .= ("json" :: Text)]) `shouldBe` True

    it "returns False for output=text" $
      wantsJson (Just $ object ["output" .= ("text" :: Text)]) `shouldBe` False

    it "returns False for missing output param" $
      wantsJson (Just $ object []) `shouldBe` False

    it "returns False for Nothing params" $
      wantsJson Nothing `shouldBe` False

  describe "jsonResult" $ do
    it "creates a non-error ToolResult" $ do
      let tr = jsonResult (object ["key" .= ("value" :: Text)])
      resultIsError tr `shouldBe` False

    it "content is valid JSON text" $ do
      let tr = jsonResult (object ["key" .= ("value" :: Text)])
          [TextContent txt] = resultContent tr
      (decode (encodeUtf8Lazy txt) :: Maybe Value) `shouldSatisfy` isJust

    it "round-trips structured data" $ do
      let v = object ["items" .= ([1,2,3] :: [Int])]
          tr = jsonResult v
          [TextContent txt] = resultContent tr
      decode (encodeUtf8Lazy txt) `shouldBe` Just v

  describe "outputParam" $ do
    it "defines a string type" $ do
      let (_, val) = outputParam
      case val of
        Object o -> KM.lookup "type" o `shouldBe` Just (String "string")
        _        -> expectationFailure "expected object"

    it "includes enum with text and json" $ do
      let (_, val) = outputParam
      case val of
        Object o -> case KM.lookup "enum" o of
          Just (Array _) -> pure ()
          _              -> expectationFailure "missing enum"
        _ -> expectationFailure "expected object"

-- =========================================================================
-- Status parsing
-- =========================================================================
statusParsingSpec :: Spec
statusParsingSpec = describe "Status JSON parsing" $ do
  it "parses porcelain v2 branch header" $ do
    let input = T.unlines
          [ "# branch.oid abc123def456"
          , "# branch.head main"
          , "# branch.upstream origin/main"
          , "# branch.ab +1 -0"
          ]
        result = parseStatusPorcelain input
    case result of
      Object o -> do
        case KM.lookup "branch" o of
          Just (Object b) -> do
            KM.lookup "head" b `shouldBe` Just (String "main")
            KM.lookup "upstream" b `shouldBe` Just (String "origin/main")
          _ -> expectationFailure "missing branch object"
      _ -> expectationFailure "expected object"

  it "parses ordinary changed entries" $ do
    let input = "1 .M N... 100644 100644 100644 abc def src/file.hs\n"
        result = parseStatusPorcelain input
    case result of
      Object o -> case KM.lookup "files" o of
        Just (Array arr) -> length arr `shouldBe` 1
        _ -> expectationFailure "missing files array"
      _ -> expectationFailure "expected object"

  it "parses untracked entries" $ do
    let input = "? newfile.txt\n"
        result = parseStatusPorcelain input
    case result of
      Object o -> case KM.lookup "untracked" o of
        Just (Array arr) -> length arr `shouldBe` 1
        _ -> expectationFailure "missing untracked array"
      _ -> expectationFailure "expected object"

  it "handles empty status" $ do
    let result = parseStatusPorcelain ""
    case result of
      Object o -> do
        KM.lookup "files" o `shouldBe` Just (toJSON ([] :: [Value]))
        KM.lookup "untracked" o `shouldBe` Just (toJSON ([] :: [Text]))
      _ -> expectationFailure "expected object"

  it "parses mixed status output" $ do
    let input = T.unlines
          [ "# branch.head main"
          , "1 M. N... 100644 100644 100644 abc def modified.txt"
          , "? untracked.txt"
          ]
        result = parseStatusPorcelain input
    case result of
      Object o -> do
        case KM.lookup "files" o of
          Just (Array arr) -> length arr `shouldBe` 1
          _ -> expectationFailure "missing files"
        case KM.lookup "untracked" o of
          Just (Array arr) -> length arr `shouldBe` 1
          _ -> expectationFailure "missing untracked"
      _ -> expectationFailure "expected object"

-- =========================================================================
-- Log parsing
-- =========================================================================
logParsingSpec :: Spec
logParsingSpec = describe "Log JSON parsing" $ do
  it "parses a delimited log entry" $ do
    let input = "abc123---gitllm-field---abc1---gitllm-field---Alice---gitllm-field---alice@example.com---gitllm-field---2026-01-01 12:00:00 +0000---gitllm-field---Initial commit---gitllm-field---\n"
        entries = parseLogEntries input
    length entries `shouldBe` 1
    case head entries of
      Object o -> do
        KM.lookup "hash" o   `shouldBe` Just (String "abc123")
        KM.lookup "author" o `shouldBe` Just (String "Alice")
        KM.lookup "subject" o `shouldBe` Just (String "Initial commit")
      _ -> expectationFailure "expected object"

  it "parses multiple entries" $ do
    let line = "abc---gitllm-field---ab---gitllm-field---Bob---gitllm-field---bob@x.com---gitllm-field---2026-01-01---gitllm-field---First---gitllm-field---"
        input = T.unlines [line, line, line]
        entries = parseLogEntries input
    length entries `shouldBe` 3

  it "handles entries with parent hashes" $ do
    let input = "abc123---gitllm-field---abc1---gitllm-field---Alice---gitllm-field---a@x.com---gitllm-field---date---gitllm-field---Merge---gitllm-field---parent1 parent2\n"
        entries = parseLogEntries input
    case head entries of
      Object o -> case KM.lookup "parents" o of
        Just (Array arr) -> length arr `shouldBe` 2
        _ -> expectationFailure "missing parents"
      _ -> expectationFailure "expected object"

  it "handles empty log output" $ do
    let entries = parseLogEntries ""
    entries `shouldBe` []

  it "handles malformed lines gracefully" $ do
    let entries = parseLogEntries "not a valid log line\n"
    length entries `shouldBe` 1
    case head entries of
      Object o -> KM.lookup "raw" o `shouldSatisfy` isJust
      _ -> expectationFailure "expected object"

-- =========================================================================
-- Branch parsing
-- =========================================================================
branchParsingSpec :: Spec
branchParsingSpec = describe "Branch JSON parsing" $ do
  it "parses formatted branch line" $ do
    let input = "main\tabc1234\t*\torigin/main\tInitial commit\n"
        branches = parseBranchLines input
    length branches `shouldBe` 1
    case head branches of
      Object o -> do
        KM.lookup "name" o    `shouldBe` Just (String "main")
        KM.lookup "sha" o     `shouldBe` Just (String "abc1234")
        KM.lookup "current" o `shouldBe` Just (Bool True)
        KM.lookup "subject" o `shouldBe` Just (String "Initial commit")
      _ -> expectationFailure "expected object"

  it "marks non-current branches correctly" $ do
    let input = "develop\tdef5678\t \t\tFeature work\n"
        branches = parseBranchLines input
    case head branches of
      Object o -> do
        KM.lookup "current" o `shouldBe` Just (Bool False)
        KM.lookup "upstream" o `shouldBe` Just Null
      _ -> expectationFailure "expected object"

  it "parses multiple branches" $ do
    let input = T.unlines
          [ "main\tabc\t*\torigin/main\tHello"
          , "develop\tdef\t \t\tWorld"
          , "feature\tghi\t \torigin/feature\tWIP"
          ]
        branches = parseBranchLines input
    length branches `shouldBe` 3

  it "handles empty output" $ do
    parseBranchLines "" `shouldBe` []

-- =========================================================================
-- Tag parsing
-- =========================================================================
tagParsingSpec :: Spec
tagParsingSpec = describe "Tag JSON parsing" $ do
  it "parses formatted tag line" $ do
    let input = "v1.0.0\tabc1234\tcommit\t2026-01-01T12:00:00+00:00\tRelease 1.0\n"
        tags = parseTagLines input
    length tags `shouldBe` 1
    case head tags of
      Object o -> do
        KM.lookup "name" o    `shouldBe` Just (String "v1.0.0")
        KM.lookup "sha" o     `shouldBe` Just (String "abc1234")
        KM.lookup "type" o    `shouldBe` Just (String "commit")
        KM.lookup "subject" o `shouldBe` Just (String "Release 1.0")
      _ -> expectationFailure "expected object"

  it "parses multiple tags" $ do
    let input = T.unlines
          [ "v1.0\tabc\tcommit\t2026-01-01\tFirst"
          , "v2.0\tdef\ttag\t2026-06-01\tSecond"
          ]
        tags = parseTagLines input
    length tags `shouldBe` 2

  it "handles empty output" $ do
    parseTagLines "" `shouldBe` []

-- =========================================================================
-- Stash parsing
-- =========================================================================
stashParsingSpec :: Spec
stashParsingSpec = describe "Stash JSON parsing" $ do
  it "parses stash entries" $ do
    let input = "stash@{0}\tWIP on main: abc123 Some commit\n"
        stashes = parseStashLines input
    length stashes `shouldBe` 1
    case head stashes of
      Object o -> do
        KM.lookup "ref" o         `shouldBe` Just (String "stash@{0}")
        KM.lookup "description" o `shouldBe` Just (String "WIP on main: abc123 Some commit")
      _ -> expectationFailure "expected object"

  it "parses multiple stash entries" $ do
    let input = T.unlines
          [ "stash@{0}\tWIP on main: abc First"
          , "stash@{1}\tOn develop: manual save"
          ]
        stashes = parseStashLines input
    length stashes `shouldBe` 2

  it "handles empty stash list" $ do
    parseStashLines "" `shouldBe` []

-- =========================================================================
-- Diff stat parsing
-- =========================================================================
diffStatParsingSpec :: Spec
diffStatParsingSpec = describe "Diff numstat JSON parsing" $ do
  it "parses numstat line" $ do
    let input = "10\t5\tsrc/Main.hs\n"
        files = parseNumstat input
    length files `shouldBe` 1
    case head files of
      Object o -> do
        KM.lookup "added" o   `shouldBe` Just (String "10")
        KM.lookup "deleted" o `shouldBe` Just (String "5")
        KM.lookup "path" o    `shouldBe` Just (String "src/Main.hs")
      _ -> expectationFailure "expected object"

  it "parses multiple files" $ do
    let input = T.unlines
          [ "10\t5\tsrc/Main.hs"
          , "0\t20\told/File.hs"
          , "3\t0\tnew/Module.hs"
          ]
        files = parseNumstat input
    length files `shouldBe` 3

  it "handles binary files with - markers" $ do
    let input = "-\t-\timage.png\n"
        files = parseNumstat input
    length files `shouldBe` 1
    case head files of
      Object o -> do
        KM.lookup "added" o `shouldBe` Just (String "-")
        KM.lookup "deleted" o `shouldBe` Just (String "-")
      _ -> expectationFailure "expected object"

  it "handles empty diff" $ do
    parseNumstat "" `shouldBe` []

-- =========================================================================
-- Config parsing
-- =========================================================================
configParsingSpec :: Spec
configParsingSpec = describe "Config JSON parsing" $ do
  it "parses key=value lines" $ do
    let input = "user.name=Test User\n"
        configs = parseConfigLines input
    length configs `shouldBe` 1
    case head configs of
      Object o -> do
        KM.lookup "key" o   `shouldBe` Just (String "user.name")
        KM.lookup "value" o `shouldBe` Just (String "Test User")
      _ -> expectationFailure "expected object"

  it "handles values with = signs" $ do
    let input = "url.ssh://git@github.com/.insteadOf=https://github.com/\n"
        configs = parseConfigLines input
    case head configs of
      Object o -> do
        KM.lookup "key" o   `shouldBe` Just (String "url.ssh://git@github.com/.insteadOf")
        KM.lookup "value" o `shouldBe` Just (String "https://github.com/")
      _ -> expectationFailure "expected object"

  it "parses multiple configs" $ do
    let input = T.unlines
          [ "user.name=Alice"
          , "user.email=alice@example.com"
          , "core.autocrlf=true"
          ]
        configs = parseConfigLines input
    length configs `shouldBe` 3

  it "handles empty config" $ do
    parseConfigLines "" `shouldBe` []

-- =========================================================================
-- Remote parsing
-- =========================================================================
remoteParsingSpec :: Spec
remoteParsingSpec = describe "Remote JSON parsing" $ do
  it "parses remote -v output (fetch lines)" $ do
    let input = T.unlines
          [ "origin\thttps://github.com/user/repo.git (fetch)"
          , "origin\thttps://github.com/user/repo.git (push)"
          ]
        remotes = parseRemoteLines input
    length remotes `shouldBe` 1
    case head remotes of
      Object o -> do
        KM.lookup "name" o `shouldBe` Just (String "origin")
        KM.lookup "url" o  `shouldBe` Just (String "https://github.com/user/repo.git")
      _ -> expectationFailure "expected object"

  it "parses multiple remotes" $ do
    let input = T.unlines
          [ "origin\thttps://github.com/user/repo.git (fetch)"
          , "origin\thttps://github.com/user/repo.git (push)"
          , "upstream\thttps://github.com/org/repo.git (fetch)"
          , "upstream\thttps://github.com/org/repo.git (push)"
          ]
        remotes = parseRemoteLines input
    length remotes `shouldBe` 2

  it "handles empty output" $ do
    parseRemoteLines "" `shouldBe` []

-- =========================================================================
-- wantsJson edge cases
-- =========================================================================
wantsJsonSpec :: Spec
wantsJsonSpec = describe "wantsJson" $ do
  it "rejects numeric output param" $
    wantsJson (Just $ object ["output" .= (42 :: Int)]) `shouldBe` False

  it "rejects boolean output param" $
    wantsJson (Just $ object ["output" .= True]) `shouldBe` False

  it "rejects output=JSON (case sensitive)" $
    wantsJson (Just $ object ["output" .= ("JSON" :: Text)]) `shouldBe` False

  it "rejects non-object params" $
    wantsJson (Just $ String "json") `shouldBe` False

-- =========================================================================
-- outputParam schema
-- =========================================================================
outputParamSpec :: Spec
outputParamSpec = describe "outputParam schema" $ do
  it "key is 'output'" $ do
    let (k, _) = outputParam
    k `shouldBe` "output"

  it "type is string" $ do
    let (_, v) = outputParam
    case v of
      Object o -> KM.lookup "type" o `shouldBe` Just (String "string")
      _        -> expectationFailure "expected object"

  it "has description" $ do
    let (_, v) = outputParam
    case v of
      Object o -> KM.lookup "description" o `shouldSatisfy` isJust
      _        -> expectationFailure "expected object"

-- =========================================================================
-- Helper
-- =========================================================================
encodeUtf8Lazy :: Text -> BL.ByteString
encodeUtf8Lazy = BL.fromStrict . TE.encodeUtf8
