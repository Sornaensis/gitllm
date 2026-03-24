{-# LANGUAGE OverloadedStrings #-}

-- | Integration tests that exercise tool handlers against real temp git repos.
module Git.ToolsIntegrationSpec (spec) where

import Control.Monad (void)
import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as T
import Test.Hspec

import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.MCP.Types (ToolResult(..), ToolResultContent(..))
import GitLLM.MCP.Router (routeRequest)

import qualified GitLLM.Git.Tools.Status  as Status
import qualified GitLLM.Git.Tools.Log     as Log
import qualified GitLLM.Git.Tools.Diff    as Diff
import qualified GitLLM.Git.Tools.Branch  as Branch
import qualified GitLLM.Git.Tools.Commit  as Commit
import qualified GitLLM.Git.Tools.Staging as Staging
import qualified GitLLM.Git.Tools.Tag     as Tag
import qualified GitLLM.Git.Tools.Stash   as Stash
import qualified GitLLM.Git.Tools.Remote  as Remote
import qualified GitLLM.Git.Tools.Config  as Config
import qualified GitLLM.Git.Tools.Inspect as Inspect
import qualified GitLLM.Git.Tools.Blame   as Blame
import qualified GitLLM.Git.Tools.Search  as Search
import qualified GitLLM.Git.Tools.Clean   as Clean
import qualified GitLLM.Git.Tools.Reflog  as Reflog
import qualified GitLLM.Git.Tools.Reset   as Reset
import qualified GitLLM.Git.Tools.Merge   as Merge
import qualified GitLLM.Git.Tools.Cherry  as Cherry
import qualified GitLLM.Git.Tools.Rebase  as Rebase
import qualified GitLLM.Git.Tools.Bisect  as Bisect
import qualified GitLLM.Git.Tools.Worktree as Worktree
import qualified GitLLM.Git.Tools.Hooks   as Hooks
import qualified GitLLM.Git.Tools.Patch   as Patch
import qualified GitLLM.Git.Tools.Archive as Archive
import qualified GitLLM.Git.Tools.Submodule as Submodule
import qualified GitLLM.Git.Tools.Composite as Composite

import TestHelpers

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight _         = False

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _        = False

spec :: Spec
spec = do
  runnerSpec
  statusSpec
  stagingSpec
  commitSpec
  logSpec
  branchSpec
  diffSpec
  configSpec
  inspectSpec
  blameSpec
  searchSpec
  cleanSpec
  reflogSpec
  tagSpec
  stashSpec
  remoteSpec
  resetSpec
  mergeSpec
  cherryPickSpec
  rebaseSpec
  bisectSpec
  worktreeSpec
  hooksSpec
  patchSpec
  archiveSpec
  submoduleSpec
  pathValidationSpec
  routerIntegrationSpec
  compositeSpec

-- =========================================================================
-- Runner
-- =========================================================================
runnerSpec :: Spec
runnerSpec = describe "Git.Runner" $ around withTempGitRepo $ do
  it "runGit succeeds on valid command" $ \ctx -> do
    result <- runGit ctx ["status"]
    result `shouldSatisfy` isRight

  it "runGit returns error for bad command" $ \ctx -> do
    result <- runGit ctx ["not-a-command"]
    result `shouldSatisfy` isLeft

  it "runGit returns repo path in rev-parse" $ \ctx -> do
    result <- runGit ctx ["rev-parse", "--show-toplevel"]
    case result of
      Right out -> T.strip out `shouldSatisfy` \p -> T.length p > 0
      Left _    -> expectationFailure "Expected success"

-- =========================================================================
-- Status
-- =========================================================================
statusSpec :: Spec
statusSpec = describe "Status" $ around withTempGitRepo $ do
  it "git_status on empty repo succeeds" $ \ctx -> do
    result <- Status.handle ctx Nothing
    resultIsError result `shouldBe` False

  it "git_status_short on empty repo succeeds" $ \ctx -> do
    result <- Status.handleShort ctx Nothing
    resultIsError result `shouldBe` False

  it "shows untracked files" $ \ctx -> do
    createRepoFile ctx "new.txt" "content"
    result <- Status.handle ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "new.txt"

  it "short format shows branch info" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Status.handleShort ctx Nothing
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "##"

-- =========================================================================
-- Staging
-- =========================================================================
stagingSpec :: Spec
stagingSpec = describe "Staging" $ around withTempGitRepo $ do
  it "git_add stages a file" $ \ctx -> do
    createRepoFile ctx "staged.txt" "data"
    let params = Just $ object ["paths" .= (["staged.txt"] :: [Text])]
    result <- Staging.handleAdd ctx params
    resultIsError result `shouldBe` False
    st <- runGit ctx ["status", "--porcelain"]
    case st of
      Right out -> out `shouldSatisfy` T.isInfixOf "staged.txt"
      Left _    -> expectationFailure "status failed"

  it "git_add_all stages everything" $ \ctx -> do
    createRepoFile ctx "a.txt" "aaa"
    createRepoFile ctx "b.txt" "bbb"
    result <- Staging.handleAddAll ctx Nothing
    resultIsError result `shouldBe` False

  it "git_add with missing paths returns error" $ \ctx -> do
    result <- Staging.handleAdd ctx Nothing
    resultIsError result `shouldBe` True

  it "git_restore_staged unstages a file" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    createRepoFile ctx "unstage_me.txt" "data"
    void $ runGit ctx ["add", "unstage_me.txt"]
    let params = Just $ object ["paths" .= (["unstage_me.txt"] :: [Text])]
    result <- Staging.handleRestoreStaged ctx params
    resultIsError result `shouldBe` False

  it "git_restore_staged with missing paths returns error" $ \ctx -> do
    result <- Staging.handleRestoreStaged ctx Nothing
    resultIsError result `shouldBe` True

-- =========================================================================
-- Commit
-- =========================================================================
commitSpec :: Spec
commitSpec = describe "Commit" $ around withTempGitRepo $ do
  it "git_commit creates a commit" $ \ctx -> do
    createRepoFile ctx "hello.txt" "world"
    void $ runGit ctx ["add", "-A"]
    let params = Just $ object ["message" .= ("test commit" :: Text)]
    result <- Commit.handle ctx params
    resultIsError result `shouldBe` False

  it "git_commit fails without message" $ \ctx -> do
    result <- Commit.handle ctx Nothing
    resultIsError result `shouldBe` True

  it "git_commit with allow_empty" $ \ctx -> do
    createRepoFile ctx "x.txt" "x"
    commitAll ctx "init"
    let params = Just $ object
          [ "message" .= ("empty commit" :: Text)
          , "allow_empty" .= True
          ]
    result <- Commit.handle ctx params
    resultIsError result `shouldBe` False

  it "git_show displays a commit" $ \ctx -> do
    createRepoFile ctx "f.txt" "content"
    commitAll ctx "show test"
    result <- Commit.handleShow ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "show test"

  it "git_show with stat flag" $ \ctx -> do
    createRepoFile ctx "f.txt" "content"
    commitAll ctx "stat test"
    let params = Just $ object ["stat" .= True]
    result <- Commit.handleShow ctx params
    resultIsError result `shouldBe` False

  it "git_commit_amend changes message" $ \ctx -> do
    createRepoFile ctx "f.txt" "content"
    commitAll ctx "original"
    let params = Just $ object ["message" .= ("amended message" :: Text)]
    result <- Commit.handleAmend ctx params
    resultIsError result `shouldBe` False
    logResult <- runGit ctx ["log", "--oneline", "-1"]
    case logResult of
      Right out -> out `shouldSatisfy` T.isInfixOf "amended message"
      Left _    -> expectationFailure "log failed"

-- =========================================================================
-- Log
-- =========================================================================
logSpec :: Spec
logSpec = describe "Log" $ around withTempGitRepo $ do
  it "git_log on repo with commits" $ \ctx -> do
    createRepoFile ctx "l.txt" "log test"
    commitAll ctx "log entry"
    result <- Log.handle ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "log entry"

  it "git_log with max_count" $ \ctx -> do
    createRepoFile ctx "a.txt" "a"
    commitAll ctx "first"
    createRepoFile ctx "b.txt" "b"
    commitAll ctx "second"
    let params = Just $ object ["max_count" .= (1 :: Int)]
    result <- Log.handle ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "second"

  it "git_log_oneline" $ \ctx -> do
    createRepoFile ctx "o.txt" "o"
    commitAll ctx "oneline test"
    result <- Log.handleOneline ctx Nothing
    resultIsError result `shouldBe` False

  it "git_log_file" $ \ctx -> do
    createRepoFile ctx "tracked.txt" "v1"
    commitAll ctx "track file"
    let params = Just $ object ["path" .= ("tracked.txt" :: Text)]
    result <- Log.handleFile ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "track file"

  it "git_log_file requires path" $ \ctx -> do
    result <- Log.handleFile ctx Nothing
    resultIsError result `shouldBe` True

  it "git_log_graph" $ \ctx -> do
    createRepoFile ctx "g.txt" "g"
    commitAll ctx "graph test"
    result <- Log.handleGraph ctx Nothing
    resultIsError result `shouldBe` False

  it "git_log with author filter" $ \ctx -> do
    createRepoFile ctx "auth.txt" "x"
    commitAll ctx "by test user"
    let params = Just $ object ["author" .= ("Test User" :: Text)]
    result <- Log.handle ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "by test user"

-- =========================================================================
-- Branch
-- =========================================================================
branchSpec :: Spec
branchSpec = describe "Branch" $ around withTempGitRepo $ do
  it "git_branch_list on fresh repo" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Branch.handleList ctx Nothing
    resultIsError result `shouldBe` False

  it "git_branch_create creates a branch" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    let params = Just $ object ["name" .= ("feature-x" :: Text)]
    result <- Branch.handleCreate ctx params
    resultIsError result `shouldBe` False
    branches <- runGit ctx ["branch", "--list"]
    case branches of
      Right out -> out `shouldSatisfy` T.isInfixOf "feature-x"
      Left _    -> expectationFailure "branch list failed"

  it "git_branch_create requires name" $ \ctx -> do
    result <- Branch.handleCreate ctx Nothing
    resultIsError result `shouldBe` True

  it "git_branch_current shows current branch" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Branch.handleCurrent ctx Nothing
    resultIsError result `shouldBe` False

  it "git_switch changes branch" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["branch", "develop"]
    let params = Just $ object ["branch" .= ("develop" :: Text)]
    result <- Branch.handleSwitch ctx params
    resultIsError result `shouldBe` False
    curr <- Branch.handleCurrent ctx Nothing
    let [TextContent out] = resultContent curr
    T.strip out `shouldBe` "develop"

  it "git_switch requires branch" $ \ctx -> do
    result <- Branch.handleSwitch ctx Nothing
    resultIsError result `shouldBe` True

  it "git_branch_rename renames a branch" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["branch", "old-name"]
    let params = Just $ object
          [ "old_name" .= ("old-name" :: Text)
          , "new_name" .= ("new-name" :: Text)
          ]
    result <- Branch.handleRename ctx params
    resultIsError result `shouldBe` False

  it "git_branch_rename requires both names" $ \ctx -> do
    result <- Branch.handleRename ctx Nothing
    resultIsError result `shouldBe` True

  it "git_branch_delete deletes a branch" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["branch", "to-delete"]
    let params = Just $ object ["name" .= ("to-delete" :: Text)]
    result <- Branch.handleDelete ctx params
    resultIsError result `shouldBe` False

  it "git_checkout switches branch" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["branch", "other"]
    let params = Just $ object ["target" .= ("other" :: Text)]
    result <- Branch.handleCheckout ctx params
    resultIsError result `shouldBe` False

  it "git_checkout requires target" $ \ctx -> do
    result <- Branch.handleCheckout ctx Nothing
    resultIsError result `shouldBe` True

  it "git_branch_list with verbose" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    let params = Just $ object ["verbose" .= True]
    result <- Branch.handleList ctx params
    resultIsError result `shouldBe` False

-- =========================================================================
-- Diff
-- =========================================================================
diffSpec :: Spec
diffSpec = describe "Diff" $ around withTempGitRepo $ do
  it "git_diff on clean repo returns empty" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Diff.handle ctx Nothing
    resultIsError result `shouldBe` False

  it "git_diff shows unstaged changes" $ \ctx -> do
    createRepoFile ctx "mod.txt" "original"
    commitAll ctx "original"
    createRepoFile ctx "mod.txt" "modified"
    result <- Diff.handle ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "modified"

  it "git_diff with path filter" $ \ctx -> do
    createRepoFile ctx "a.txt" "original"
    createRepoFile ctx "b.txt" "original"
    commitAll ctx "initial"
    createRepoFile ctx "a.txt" "changed-a"
    createRepoFile ctx "b.txt" "changed-b"
    let params = Just $ object ["path" .= ("a.txt" :: Text)]
    result <- Diff.handle ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "changed-a"

  it "git_diff_staged shows staged changes" $ \ctx -> do
    createRepoFile ctx "s.txt" "original"
    commitAll ctx "initial"
    createRepoFile ctx "s.txt" "staged change"
    void $ runGit ctx ["add", "s.txt"]
    result <- Diff.handleStaged ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "staged change"

  it "git_diff_branches compares refs" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["checkout", "-b", "feat"]
    createRepoFile ctx "feat.txt" "feature content"
    commitAll ctx "feature"
    let params = Just $ object
          [ "from_ref" .= ("master" :: Text)
          , "to_ref" .= ("feat" :: Text)
          ]
    result <- Diff.handleBranches ctx params
    resultIsError result `shouldBe` False

  it "git_diff_branches requires both refs" $ \ctx -> do
    result <- Diff.handleBranches ctx Nothing
    resultIsError result `shouldBe` True

  it "git_diff_stat shows statistics" $ \ctx -> do
    createRepoFile ctx "stat.txt" "data"
    commitAll ctx "stat"
    result <- Diff.handleStat ctx Nothing
    resultIsError result `shouldBe` False

-- =========================================================================
-- Config
-- =========================================================================
configSpec :: Spec
configSpec = describe "Config" $ around withTempGitRepo $ do
  it "git_config_get reads a value" $ \ctx -> do
    let params = Just $ object ["key" .= ("user.name" :: Text)]
    result <- Config.handleGet ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    T.strip out `shouldBe` "Test User"

  it "git_config_get requires key" $ \ctx -> do
    result <- Config.handleGet ctx Nothing
    resultIsError result `shouldBe` True

  it "git_config_list lists config" $ \ctx -> do
    result <- Config.handleList ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "user.name"

  it "git_config_set sets a local value" $ \ctx -> do
    let params = Just $ object
          [ "key" .= ("test.mykey" :: Text)
          , "value" .= ("myval" :: Text)
          ]
    result <- Config.handleSet ctx params
    resultIsError result `shouldBe` False
    -- Verify
    getResult <- Config.handleGet ctx (Just $ object ["key" .= ("test.mykey" :: Text)])
    let [TextContent out] = resultContent getResult
    T.strip out `shouldBe` "myval"

  it "git_config_set requires both key and value" $ \ctx -> do
    result <- Config.handleSet ctx Nothing
    resultIsError result `shouldBe` True

-- =========================================================================
-- Inspect
-- =========================================================================
inspectSpec :: Spec
inspectSpec = describe "Inspect" $ around withTempGitRepo $ do
  it "git_rev_parse resolves HEAD" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    let params = Just $ object ["ref" .= ("HEAD" :: Text)]
    result <- Inspect.handleRevParse ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    T.length (T.strip out) `shouldSatisfy` (>= 40)

  it "git_rev_parse requires ref" $ \ctx -> do
    result <- Inspect.handleRevParse ctx Nothing
    resultIsError result `shouldBe` True

  it "git_rev_parse with short hash" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    let params = Just $ object ["ref" .= ("HEAD" :: Text), "short" .= True]
    result <- Inspect.handleRevParse ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    T.length (T.strip out) `shouldSatisfy` (< 40)

  it "git_ls_files lists tracked files" $ \ctx -> do
    createRepoFile ctx "tracked.txt" "data"
    commitAll ctx "initial"
    result <- Inspect.handleLsFiles ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "tracked.txt"

  it "git_count_objects shows stats" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Inspect.handleCountObjects ctx Nothing
    resultIsError result `shouldBe` False

  it "git_cat_file requires object" $ \ctx -> do
    result <- Inspect.handleCatFile ctx Nothing
    resultIsError result `shouldBe` True

  it "git_ls_tree lists tree" $ \ctx -> do
    createRepoFile ctx "tree.txt" "data"
    commitAll ctx "initial"
    result <- Inspect.handleLsTree ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "tree.txt"

-- =========================================================================
-- Blame
-- =========================================================================
blameSpec :: Spec
blameSpec = describe "Blame" $ around withTempGitRepo $ do
  it "git_blame shows line annotations" $ \ctx -> do
    createRepoFile ctx "blame.txt" "line1\nline2\nline3\n"
    commitAll ctx "blame test"
    let params = Just $ object ["path" .= ("blame.txt" :: Text)]
    result <- Blame.handle ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "line1"

  it "git_blame requires path" $ \ctx -> do
    result <- Blame.handle ctx Nothing
    resultIsError result `shouldBe` True

-- =========================================================================
-- Search
-- =========================================================================
searchSpec :: Spec
searchSpec = describe "Search" $ around withTempGitRepo $ do
  it "git_grep finds text in tracked files" $ \ctx -> do
    createRepoFile ctx "haystack.txt" "needle in the haystack"
    commitAll ctx "searchable"
    let params = Just $ object ["pattern" .= ("needle" :: Text)]
    result <- Search.handleGrep ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "needle"

  it "git_grep requires pattern" $ \ctx -> do
    result <- Search.handleGrep ctx Nothing
    resultIsError result `shouldBe` True

  it "git_log_search requires pattern" $ \ctx -> do
    result <- Search.handleLogSearch ctx Nothing
    resultIsError result `shouldBe` True

  it "git_log_search finds commit by message" $ \ctx -> do
    createRepoFile ctx "s.txt" "data"
    commitAll ctx "unique-search-term-xyz"
    let params = Just $ object ["pattern" .= ("unique-search-term-xyz" :: Text)]
    result <- Search.handleLogSearch ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "unique-search-term-xyz"

-- =========================================================================
-- Clean
-- =========================================================================
cleanSpec :: Spec
cleanSpec = describe "Clean" $ around withTempGitRepo $ do
  it "git_clean_dry_run shows what would be removed" $ \ctx -> do
    createRepoFile ctx "init.txt" "data"
    commitAll ctx "initial"
    createRepoFile ctx "untracked.txt" "junk"
    result <- Clean.handleDryRun ctx Nothing
    resultIsError result `shouldBe` False

-- =========================================================================
-- Reflog
-- =========================================================================
reflogSpec :: Spec
reflogSpec = describe "Reflog" $ around withTempGitRepo $ do
  it "git_reflog shows history" $ \ctx -> do
    createRepoFile ctx "r.txt" "data"
    commitAll ctx "reflog test"
    result <- Reflog.handle ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "reflog test"

  it "git_reflog with max_count" $ \ctx -> do
    createRepoFile ctx "r.txt" "data"
    commitAll ctx "first"
    createRepoFile ctx "r2.txt" "data"
    commitAll ctx "second"
    let params = Just $ object ["max_count" .= (1 :: Int)]
    result <- Reflog.handle ctx params
    resultIsError result `shouldBe` False

-- =========================================================================
-- Tag
-- =========================================================================
tagSpec :: Spec
tagSpec = describe "Tag" $ around withTempGitRepo $ do
  it "git_tag_create creates a tag" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    let params = Just $ object ["name" .= ("v1.0" :: Text)]
    result <- Tag.handleCreate ctx params
    resultIsError result `shouldBe` False

  it "git_tag_create requires name" $ \ctx -> do
    result <- Tag.handleCreate ctx Nothing
    resultIsError result `shouldBe` True

  it "git_tag_list shows tags" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["tag", "test-tag"]
    result <- Tag.handleList ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "test-tag"

  it "git_tag_delete removes a tag" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["tag", "del-me"]
    let params = Just $ object ["name" .= ("del-me" :: Text)]
    result <- Tag.handleDelete ctx params
    resultIsError result `shouldBe` False

  it "git_tag_delete requires name" $ \ctx -> do
    result <- Tag.handleDelete ctx Nothing
    resultIsError result `shouldBe` True

-- =========================================================================
-- Stash
-- =========================================================================
stashSpec :: Spec
stashSpec = describe "Stash" $ around withTempGitRepo $ do
  it "git_stash_list on empty stash succeeds" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Stash.handleList ctx Nothing
    resultIsError result `shouldBe` False

  it "git_stash_push and git_stash_pop round-trip" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    createRepoFile ctx "init.txt" "modified"
    pushResult <- Stash.handlePush ctx Nothing
    resultIsError pushResult `shouldBe` False
    popResult <- Stash.handlePop ctx Nothing
    resultIsError popResult `shouldBe` False

-- =========================================================================
-- Remote
-- =========================================================================
remoteSpec :: Spec
remoteSpec = describe "Remote" $ around withTempGitRepo $ do
  it "git_remote_list on local repo" $ \ctx -> do
    result <- Remote.handleList ctx Nothing
    resultIsError result `shouldBe` False

  it "git_remote_add and git_remote_remove" $ \ctx -> do
    let addParams = Just $ object
          [ "name" .= ("test-remote" :: Text)
          , "url" .= ("https://example.com/repo.git" :: Text)
          ]
    addResult <- Remote.handleAdd ctx addParams
    resultIsError addResult `shouldBe` False
    -- Verify added
    listResult <- Remote.handleList ctx Nothing
    let [TextContent out] = resultContent listResult
    out `shouldSatisfy` T.isInfixOf "test-remote"
    -- Remove
    let rmParams = Just $ object ["name" .= ("test-remote" :: Text)]
    rmResult <- Remote.handleRemove ctx rmParams
    resultIsError rmResult `shouldBe` False

  it "git_remote_add requires name and url" $ \ctx -> do
    result <- Remote.handleAdd ctx Nothing
    resultIsError result `shouldBe` True

  it "git_remote_remove requires name" $ \ctx -> do
    result <- Remote.handleRemove ctx Nothing
    resultIsError result `shouldBe` True

-- =========================================================================
-- Reset
-- =========================================================================
resetSpec :: Spec
resetSpec = describe "Reset" $ around withTempGitRepo $ do
  it "git_reset mixed (default)" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    createRepoFile ctx "new.txt" "new"
    commitAll ctx "second"
    let params = Just $ object ["ref" .= ("HEAD~1" :: Text)]
    result <- Reset.handle ctx params
    resultIsError result `shouldBe` False
    -- File should still exist but be unstaged
    st <- runGit ctx ["status", "--porcelain"]
    case st of
      Right out -> out `shouldSatisfy` T.isInfixOf "new.txt"
      Left _    -> expectationFailure "status failed"

  it "git_reset_file unstages a file" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    createRepoFile ctx "unstage.txt" "data"
    void $ runGit ctx ["add", "unstage.txt"]
    let params = Just $ object ["paths" .= (["unstage.txt"] :: [Text])]
    result <- Reset.handleFile ctx params
    resultIsError result `shouldBe` False

  it "git_reset_file requires paths" $ \ctx -> do
    result <- Reset.handleFile ctx Nothing
    resultIsError result `shouldBe` True

-- =========================================================================
-- Merge
-- =========================================================================
mergeSpec :: Spec
mergeSpec = describe "Merge" $ around withTempGitRepo $ do
  it "git_merge merges a branch" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["checkout", "-b", "feature"]
    createRepoFile ctx "feature.txt" "feature work"
    commitAll ctx "feature commit"
    void $ runGit ctx ["checkout", "master"]
    let params = Just $ object ["branch" .= ("feature" :: Text)]
    result <- Merge.handle ctx params
    resultIsError result `shouldBe` False
    -- Verify file from feature branch exists
    st <- runGit ctx ["ls-files"]
    case st of
      Right out -> out `shouldSatisfy` T.isInfixOf "feature.txt"
      Left _    -> expectationFailure "ls-files failed"

  it "git_merge with --no-ff" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["checkout", "-b", "feat2"]
    createRepoFile ctx "feat2.txt" "work"
    commitAll ctx "feat2"
    void $ runGit ctx ["checkout", "master"]
    let params = Just $ object
          [ "branch" .= ("feat2" :: Text)
          , "no_ff" .= True
          , "message" .= ("Merge feat2" :: Text)
          ]
    result <- Merge.handle ctx params
    resultIsError result `shouldBe` False

  it "git_merge requires branch" $ \ctx -> do
    result <- Merge.handle ctx Nothing
    resultIsError result `shouldBe` True

  it "git_merge_status on clean repo" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Merge.handleStatus ctx Nothing
    resultIsError result `shouldBe` False

-- =========================================================================
-- Cherry-pick
-- =========================================================================
cherryPickSpec :: Spec
cherryPickSpec = describe "Cherry-pick" $ around withTempGitRepo $ do
  it "git_cherry_pick applies a commit" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["checkout", "-b", "side"]
    createRepoFile ctx "cherry.txt" "cherry content"
    commitAll ctx "cherry commit"
    -- Get the commit SHA
    shaResult <- runGit ctx ["rev-parse", "HEAD"]
    case shaResult of
      Right sha -> do
        void $ runGit ctx ["checkout", "master"]
        let params = Just $ object ["commits" .= ([T.strip sha] :: [Text])]
        result <- Cherry.handle ctx params
        resultIsError result `shouldBe` False
        -- Verify cherry.txt exists
        ls <- runGit ctx ["ls-files"]
        case ls of
          Right out -> out `shouldSatisfy` T.isInfixOf "cherry.txt"
          Left _    -> expectationFailure "ls-files failed"
      Left _ -> expectationFailure "rev-parse failed"

  it "git_cherry_pick requires commits" $ \ctx -> do
    result <- Cherry.handle ctx Nothing
    resultIsError result `shouldBe` True

-- =========================================================================
-- Rebase
-- =========================================================================
rebaseSpec :: Spec
rebaseSpec = describe "Rebase" $ around withTempGitRepo $ do
  it "git_rebase onto another branch" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["checkout", "-b", "feature"]
    createRepoFile ctx "feat.txt" "work"
    commitAll ctx "feature work"
    void $ runGit ctx ["checkout", "master"]
    createRepoFile ctx "main.txt" "main work"
    commitAll ctx "main work"
    void $ runGit ctx ["checkout", "feature"]
    let params = Just $ object ["onto" .= ("master" :: Text)]
    result <- Rebase.handle ctx params
    resultIsError result `shouldBe` False

  it "git_rebase requires onto" $ \ctx -> do
    result <- Rebase.handle ctx Nothing
    resultIsError result `shouldBe` True

  it "git_rebase_interactive lists commits" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    createRepoFile ctx "a.txt" "a"
    commitAll ctx "second"
    let params = Just $ object ["onto" .= ("HEAD~1" :: Text)]
    result <- Rebase.handleInteractive ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "second"

  it "git_rebase_interactive requires onto" $ \ctx -> do
    result <- Rebase.handleInteractive ctx Nothing
    resultIsError result `shouldBe` True

-- =========================================================================
-- Bisect
-- =========================================================================
bisectSpec :: Spec
bisectSpec = describe "Bisect" $ around withTempGitRepo $ do
  it "git_bisect_start and git_bisect_reset" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    createRepoFile ctx "a.txt" "a"
    commitAll ctx "second"
    result <- Bisect.handleStart ctx Nothing
    resultIsError result `shouldBe` False
    resetResult <- Bisect.handleReset ctx Nothing
    resultIsError resetResult `shouldBe` False

  it "bisect workflow: start, good, bad" $ \ctx -> do
    createRepoFile ctx "init.txt" "v1"
    commitAll ctx "good commit"
    goodSha <- runGit ctx ["rev-parse", "HEAD"]
    createRepoFile ctx "init.txt" "v2"
    commitAll ctx "second"
    createRepoFile ctx "init.txt" "v3"
    commitAll ctx "bad commit"
    case goodSha of
      Right sha -> do
        let startParams = Just $ object
              [ "bad" .= ("HEAD" :: Text)
              , "good" .= T.strip sha
              ]
        startResult <- Bisect.handleStart ctx startParams
        resultIsError startResult `shouldBe` False
        resetResult <- Bisect.handleReset ctx Nothing
        resultIsError resetResult `shouldBe` False
      Left _ -> expectationFailure "rev-parse failed"

-- =========================================================================
-- Worktree
-- =========================================================================
worktreeSpec :: Spec
worktreeSpec = describe "Worktree" $ around withTempGitRepo $ do
  it "git_worktree_list shows main worktree" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Worktree.handleList ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    T.length out `shouldSatisfy` (> 0)

  it "git_worktree_add requires path" $ \ctx -> do
    result <- Worktree.handleAdd ctx Nothing
    resultIsError result `shouldBe` True

  it "git_worktree_remove requires path" $ \ctx -> do
    result <- Worktree.handleRemove ctx Nothing
    resultIsError result `shouldBe` True

  it "git_worktree_add rejects path traversal" $ \ctx -> do
    let params = Just $ object ["path" .= ("../../escape" :: Text)]
    result <- Worktree.handleAdd ctx params
    resultIsError result `shouldBe` True
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "traversal"

-- =========================================================================
-- Hooks
-- =========================================================================
hooksSpec :: Spec
hooksSpec = describe "Hooks" $ around withTempGitRepo $ do
  it "git_hooks_list shows available hooks" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Hooks.handleList ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "hooks"

-- =========================================================================
-- Patch
-- =========================================================================
patchSpec :: Spec
patchSpec = describe "Patch" $ around withTempGitRepo $ do
  it "git_format_patch generates patch" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    createRepoFile ctx "patch.txt" "patched"
    commitAll ctx "patch commit"
    result <- Patch.handleFormatPatch ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf ".patch"

  it "git_format_patch with count" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    createRepoFile ctx "a.txt" "a"
    commitAll ctx "second"
    let params = Just $ object ["count" .= (1 :: Int)]
    result <- Patch.handleFormatPatch ctx params
    resultIsError result `shouldBe` False

  it "git_apply requires patch_path" $ \ctx -> do
    result <- Patch.handleApply ctx Nothing
    resultIsError result `shouldBe` True

  it "git_apply rejects path traversal" $ \ctx -> do
    let params = Just $ object ["patch_path" .= ("../../evil.patch" :: Text)]
    result <- Patch.handleApply ctx params
    resultIsError result `shouldBe` True
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "traversal"

-- =========================================================================
-- Archive
-- =========================================================================
archiveSpec :: Spec
archiveSpec = describe "Archive" $ around withTempGitRepo $ do
  it "git_archive creates archive" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    let params = Just $ object
          [ "format" .= ("zip" :: Text)
          , "output" .= ("test.zip" :: Text)
          ]
    result <- Archive.handle ctx params
    resultIsError result `shouldBe` False

  it "git_archive with defaults" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    let params = Just $ object ["output" .= ("out.tar" :: Text)]
    result <- Archive.handle ctx params
    resultIsError result `shouldBe` False

-- =========================================================================
-- Submodule
-- =========================================================================
submoduleSpec :: Spec
submoduleSpec = describe "Submodule" $ around withTempGitRepo $ do
  it "git_submodule_list on repo with no submodules" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Submodule.handleList ctx Nothing
    resultIsError result `shouldBe` False

  it "git_submodule_add requires url" $ \ctx -> do
    result <- Submodule.handleAdd ctx Nothing
    resultIsError result `shouldBe` True

  it "git_submodule_sync succeeds on empty" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Submodule.handleSync ctx Nothing
    resultIsError result `shouldBe` False

-- =========================================================================
-- Path validation
-- =========================================================================
pathValidationSpec :: Spec
pathValidationSpec = describe "Path validation" $ around withTempGitRepo $ do
  it "git_add rejects path traversal" $ \ctx -> do
    let params = Just $ object ["paths" .= (["../../etc/passwd"] :: [Text])]
    result <- Staging.handleAdd ctx params
    resultIsError result `shouldBe` True
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "Invalid path"

  it "git_restore rejects path traversal" $ \ctx -> do
    let params = Just $ object ["paths" .= (["../escape"] :: [Text])]
    result <- Staging.handleRestore ctx params
    resultIsError result `shouldBe` True

  it "git_restore_staged rejects path traversal" $ \ctx -> do
    let params = Just $ object ["paths" .= (["../escape"] :: [Text])]
    result <- Staging.handleRestoreStaged ctx params
    resultIsError result `shouldBe` True

  it "git_blame rejects path traversal" $ \ctx -> do
    let params = Just $ object ["path" .= ("../../etc/shadow" :: Text)]
    result <- Blame.handle ctx params
    resultIsError result `shouldBe` True
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "traversal"

  it "git_reset_file rejects path traversal" $ \ctx -> do
    let params = Just $ object ["paths" .= (["../escape.txt"] :: [Text])]
    result <- Reset.handleFile ctx params
    resultIsError result `shouldBe` True

-- =========================================================================
-- Router integration
-- =========================================================================
routerIntegrationSpec :: Spec
routerIntegrationSpec = describe "Router (end-to-end)" $ around withTempGitRepo $ do
  it "routes git_status" $ \ctx -> do
    result <- routeRequest ctx "git_status" Nothing
    resultIsError result `shouldBe` False

  it "routes git_branch_current after commit" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- routeRequest ctx "git_branch_current" Nothing
    resultIsError result `shouldBe` False

  it "routes git_config_list" $ \ctx -> do
    result <- routeRequest ctx "git_config_list" Nothing
    resultIsError result `shouldBe` False

  it "routes git_remote_list" $ \ctx -> do
    result <- routeRequest ctx "git_remote_list" Nothing
    resultIsError result `shouldBe` False

-- =========================================================================
-- Composite Operations
-- =========================================================================
compositeSpec :: Spec
compositeSpec = describe "Composite" $ do
  branchCleanupSpec
  repoHealthSpec
  changelogSpec

branchCleanupSpec :: Spec
branchCleanupSpec = describe "git_branch_cleanup" $ around withTempGitRepo $ do
  it "dry run shows no branches to clean on fresh repo" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Composite.handleBranchCleanup ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "No merged branches"

  it "dry run lists merged branches" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    -- Create and merge a feature branch
    void $ runGit ctx ["checkout", "-b", "feature-x"]
    createRepoFile ctx "feature.txt" "feature"
    commitAll ctx "feature commit"
    void $ runGit ctx ["checkout", "master"]
    void $ runGit ctx ["merge", "feature-x"]
    result <- Composite.handleBranchCleanup ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "feature-x"

  it "actually deletes merged branches when dry_run=false" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    void $ runGit ctx ["checkout", "-b", "to-delete"]
    createRepoFile ctx "del.txt" "del"
    commitAll ctx "delete me"
    void $ runGit ctx ["checkout", "master"]
    void $ runGit ctx ["merge", "to-delete"]
    let params = Just $ object ["dry_run" .= False]
    result <- Composite.handleBranchCleanup ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "to-delete"
    -- Verify branch is actually gone
    branchResult <- runGit ctx ["branch"]
    case branchResult of
      Right branches -> branches `shouldNotSatisfy` T.isInfixOf "to-delete"
      Left _ -> expectationFailure "Failed to list branches"

  it "JSON output in dry run mode" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    let params = Just $ object ["output" .= ("json" :: Text)]
    result <- Composite.handleBranchCleanup ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "dry_run"

repoHealthSpec :: Spec
repoHealthSpec = describe "git_repo_health" $ around withTempGitRepo $ do
  it "returns health report on fresh repo" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    result <- Composite.handleRepoHealth ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "Repository Health Report"

  it "JSON output includes object_stats and fsck" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    let params = Just $ object ["output" .= ("json" :: Text)]
    result <- Composite.handleRepoHealth ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "object_stats"
    out `shouldSatisfy` T.isInfixOf "fsck"

changelogSpec :: Spec
changelogSpec = describe "git_changelog_generate" $ around withTempGitRepo $ do
  it "generates changelog from commit history" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "initial"
    createRepoFile ctx "feat.txt" "feat"
    commitAll ctx "feat: add feature"
    createRepoFile ctx "fix.txt" "fix"
    commitAll ctx "fix: resolve bug"
    result <- Composite.handleChangelogGenerate ctx Nothing
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "Changelog"
    out `shouldSatisfy` T.isInfixOf "feat: add feature"
    out `shouldSatisfy` T.isInfixOf "fix: resolve bug"

  it "respects limit parameter" $ \ctx -> do
    createRepoFile ctx "a.txt" "a"
    commitAll ctx "commit a"
    createRepoFile ctx "b.txt" "b"
    commitAll ctx "commit b"
    createRepoFile ctx "c.txt" "c"
    commitAll ctx "commit c"
    let params = Just $ object ["limit" .= (1 :: Int)]
    result <- Composite.handleChangelogGenerate ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "commit c"
    -- Should NOT contain the first commit since limit=1
    out `shouldNotSatisfy` T.isInfixOf "commit a"

  it "JSON output includes grouped commits" $ \ctx -> do
    createRepoFile ctx "init.txt" "init"
    commitAll ctx "feat: initial feature"
    createRepoFile ctx "fix.txt" "fix"
    commitAll ctx "fix: a bugfix"
    let params = Just $ object ["output" .= ("json" :: Text)]
    result <- Composite.handleChangelogGenerate ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "commits"
    out `shouldSatisfy` T.isInfixOf "grouped"

  it "group_by author works" $ \ctx -> do
    createRepoFile ctx "a.txt" "a"
    commitAll ctx "commit by author"
    let params = Just $ object ["group_by" .= ("author" :: Text)]
    result <- Composite.handleChangelogGenerate ctx params
    resultIsError result `shouldBe` False
    let [TextContent out] = resultContent result
    out `shouldSatisfy` T.isInfixOf "Test User"
