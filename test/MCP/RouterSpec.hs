{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module MCP.RouterSpec (spec) where

import Control.Exception (SomeException, try)
import Control.Monad (forM_)
import Data.Aeson
import qualified Data.Aeson.KeyMap as KM
import Data.List (nub)
import qualified Data.Text as T
import Test.Hspec

import GitLLM.MCP.Router
import GitLLM.MCP.Types
import GitLLM.Git.Types (GitContext(..))
import TestHelpers (withTempGitRepo, createRepoFile, commitAll)

spec :: Spec
spec = do
  toolDefinitionsSpec
  routingSpec
  toolCoverageSpec

-- -------------------------------------------------------------------------
toolDefinitionsSpec :: Spec
toolDefinitionsSpec = describe "allToolDefinitions" $ do
  it "is non-empty" $ do
    length allToolDefinitions `shouldSatisfy` (> 0)

  it "contains at least 50 tools" $ do
    length allToolDefinitions `shouldSatisfy` (>= 50)

  it "has unique tool names" $ do
    let names = map toolName allToolDefinitions
    length names `shouldBe` length (nub names)

  it "every tool has non-empty name" $ do
    forM_ allToolDefinitions $ \td ->
      T.length (toolName td) `shouldSatisfy` (> 0)

  it "every tool has non-empty description" $ do
    forM_ allToolDefinitions $ \td ->
      T.length (toolDescription td) `shouldSatisfy` (> 0)

  it "every tool name starts with git_" $ do
    forM_ allToolDefinitions $ \td ->
      toolName td `shouldSatisfy` T.isPrefixOf "git_"

  it "every tool has object input schema" $ do
    forM_ allToolDefinitions $ \td ->
      case toolInputSchema td of
        Object o -> KM.lookup "type" o `shouldBe` Just (String "object")
        _        -> expectationFailure $
                      "Expected object schema for " ++ T.unpack (toolName td)

  it "every tool schema has properties field" $ do
    forM_ allToolDefinitions $ \td ->
      case toolInputSchema td of
        Object o -> KM.lookup "properties" o `shouldSatisfy` \v -> case v of
          Just (Object _) -> True
          _               -> False
        _ -> expectationFailure "Expected object"

  it "every tool schema has additionalProperties false" $ do
    forM_ allToolDefinitions $ \td ->
      case toolInputSchema td of
        Object o -> KM.lookup "additionalProperties" o `shouldBe` Just (Bool False)
        _        -> expectationFailure $
                      "Expected object schema for " ++ T.unpack (toolName td)

  it "every tool has annotations" $ do
    forM_ allToolDefinitions $ \td ->
      toolAnnotations td `shouldSatisfy` \a -> case a of
        Just _  -> True
        Nothing -> False

-- -------------------------------------------------------------------------
routingSpec :: Spec
routingSpec = describe "routeRequest" $ do
  it "returns error for unknown tool" $ do
    let ctx = GitContext "." Nothing
    result <- routeRequest ctx "nonexistent_tool" Nothing
    resultIsError result `shouldBe` True
    case resultContent result of
      [TextContent t] -> t `shouldSatisfy` T.isInfixOf "Unknown tool"
      _               -> expectationFailure "Expected single TextContent"

  it "returns error with tool name for unknown tool" $ do
    let ctx = GitContext "." Nothing
    result <- routeRequest ctx "bogus_tool_xyz" Nothing
    case resultContent result of
      [TextContent t] -> t `shouldSatisfy` T.isInfixOf "bogus_tool_xyz"
      _               -> expectationFailure "Expected error text"

  it "all registered tool names have routes (not 'Unknown tool')" $ do
    withTempGitRepo $ \ctx -> do
      createRepoFile ctx "init.txt" "init"
      commitAll ctx "initial"
      forM_ allToolDefinitions $ \td -> do
        result <- try (routeRequest ctx (toolName td) Nothing) :: IO (Either SomeException ToolResult)
        case result of
          Right tr -> resultContent tr `shouldSatisfy` \cs ->
            not (any (\(TextContent t) -> T.isPrefixOf "Unknown tool: " t) cs)
          Left _ -> pure ()  -- Git command errors are fine; means the route was found

-- -------------------------------------------------------------------------
toolCoverageSpec :: Spec
toolCoverageSpec = describe "tool category coverage" $ do
  let names = map toolName allToolDefinitions

  it "includes status tools" $ do
    names `shouldSatisfy` elem "git_status"
    names `shouldSatisfy` elem "git_status_short"

  it "includes log tools" $ do
    names `shouldSatisfy` elem "git_log"
    names `shouldSatisfy` elem "git_log_oneline"
    names `shouldSatisfy` elem "git_log_file"
    names `shouldSatisfy` elem "git_log_graph"

  it "includes diff tools" $ do
    names `shouldSatisfy` elem "git_diff"
    names `shouldSatisfy` elem "git_diff_staged"
    names `shouldSatisfy` elem "git_diff_branches"
    names `shouldSatisfy` elem "git_diff_stat"

  it "includes branch tools" $ do
    names `shouldSatisfy` elem "git_branch_list"
    names `shouldSatisfy` elem "git_branch_create"
    names `shouldSatisfy` elem "git_branch_delete"
    names `shouldSatisfy` elem "git_checkout"
    names `shouldSatisfy` elem "git_switch"

  it "includes commit tools" $ do
    names `shouldSatisfy` elem "git_commit"
    names `shouldSatisfy` elem "git_commit_amend"
    names `shouldSatisfy` elem "git_show"

  it "includes staging tools" $ do
    names `shouldSatisfy` elem "git_add"
    names `shouldSatisfy` elem "git_add_all"
    names `shouldSatisfy` elem "git_restore"
    names `shouldSatisfy` elem "git_restore_staged"

  it "includes remote tools" $ do
    names `shouldSatisfy` elem "git_remote_list"
    names `shouldSatisfy` elem "git_fetch"
    names `shouldSatisfy` elem "git_push"
    names `shouldSatisfy` elem "git_pull"

  it "includes stash tools" $ do
    names `shouldSatisfy` elem "git_stash_push"
    names `shouldSatisfy` elem "git_stash_list"
    names `shouldSatisfy` elem "git_stash_pop"

  it "includes tag tools" $ do
    names `shouldSatisfy` elem "git_tag_list"
    names `shouldSatisfy` elem "git_tag_create"
    names `shouldSatisfy` elem "git_tag_delete"

  it "includes merge tools" $ do
    names `shouldSatisfy` elem "git_merge"
    names `shouldSatisfy` elem "git_merge_abort"

  it "includes rebase tools" $ do
    names `shouldSatisfy` elem "git_rebase"
    names `shouldSatisfy` elem "git_rebase_abort"

  it "includes cherry-pick tools" $ do
    names `shouldSatisfy` elem "git_cherry_pick"

  it "includes config tools" $ do
    names `shouldSatisfy` elem "git_config_get"
    names `shouldSatisfy` elem "git_config_set"
    names `shouldSatisfy` elem "git_config_list"

  it "includes blame tool" $ do
    names `shouldSatisfy` elem "git_blame"

  it "includes bisect tools" $ do
    names `shouldSatisfy` elem "git_bisect_start"
    names `shouldSatisfy` elem "git_bisect_reset"

  it "includes clean tools" $ do
    names `shouldSatisfy` elem "git_clean"
    names `shouldSatisfy` elem "git_clean_dry_run"

  it "includes reset tools" $ do
    names `shouldSatisfy` elem "git_reset"
    names `shouldSatisfy` elem "git_reset_file"

  it "includes reflog tool" $ do
    names `shouldSatisfy` elem "git_reflog"

  it "includes search tools" $ do
    names `shouldSatisfy` elem "git_grep"
    names `shouldSatisfy` elem "git_log_search"

  it "includes patch tools" $ do
    names `shouldSatisfy` elem "git_format_patch"
    names `shouldSatisfy` elem "git_apply"

  it "includes archive tool" $ do
    names `shouldSatisfy` elem "git_archive"

  it "includes hooks tool" $ do
    names `shouldSatisfy` elem "git_hooks_list"

  it "includes inspect tools" $ do
    names `shouldSatisfy` elem "git_cat_file"
    names `shouldSatisfy` elem "git_ls_files"
    names `shouldSatisfy` elem "git_ls_tree"
    names `shouldSatisfy` elem "git_rev_parse"
    names `shouldSatisfy` elem "git_count_objects"

  it "includes worktree tools" $ do
    names `shouldSatisfy` elem "git_worktree_list"
    names `shouldSatisfy` elem "git_worktree_add"

  it "includes submodule tools" $ do
    names `shouldSatisfy` elem "git_submodule_list"
    names `shouldSatisfy` elem "git_submodule_add"
