{-# LANGUAGE OverloadedStrings #-}

module GitLLM.MCP.Router
  ( routeRequest
  , allToolDefinitions
  ) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types (GitContext(..))

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
import qualified GitLLM.Git.Tools.Composite as Composite

-- | All tool definitions registered with the server.
allToolDefinitions :: [ToolDefinition]
allToolDefinitions = concat
  [ Status.tools
  , Log.tools
  , Diff.tools
  , Branch.tools
  , Commit.tools
  , Staging.tools
  , Remote.tools
  , Stash.tools
  , Tag.tools
  , Merge.tools
  , Rebase.tools
  , Cherry.tools
  , Worktree.tools
  , Submodule.tools
  , Config.tools
  , Blame.tools
  , Bisect.tools
  , Clean.tools
  , Reset.tools
  , Reflog.tools
  , Search.tools
  , Patch.tools
  , Archive.tools
  , Hooks.tools
  , Inspect.tools
  , Composite.tools
  ]

-- | Route a tools/call request to the appropriate handler.
routeRequest :: GitContext -> Text -> Maybe Value -> IO ToolResult
routeRequest ctx name params = case name of
  -- Status
  "git_status"            -> Status.handle ctx params
  "git_status_short"      -> Status.handleShort ctx params
  -- Log
  "git_log"               -> Log.handle ctx params
  "git_log_oneline"       -> Log.handleOneline ctx params
  "git_log_file"          -> Log.handleFile ctx params
  "git_log_graph"         -> Log.handleGraph ctx params
  -- Diff
  "git_diff"              -> Diff.handle ctx params
  "git_diff_staged"       -> Diff.handleStaged ctx params
  "git_diff_branches"     -> Diff.handleBranches ctx params
  "git_diff_stat"         -> Diff.handleStat ctx params
  -- Branch
  "git_branch_list"       -> Branch.handleList ctx params
  "git_branch_create"     -> Branch.handleCreate ctx params
  "git_branch_delete"     -> Branch.handleDelete ctx params
  "git_branch_rename"     -> Branch.handleRename ctx params
  "git_branch_current"    -> Branch.handleCurrent ctx params
  "git_checkout"          -> Branch.handleCheckout ctx params
  "git_switch"            -> Branch.handleSwitch ctx params
  -- Commit
  "git_commit"            -> Commit.handle ctx params
  "git_commit_amend"      -> Commit.handleAmend ctx params
  "git_show"              -> Commit.handleShow ctx params
  -- Staging
  "git_add"               -> Staging.handleAdd ctx params
  "git_add_all"           -> Staging.handleAddAll ctx params
  "git_restore"           -> Staging.handleRestore ctx params
  "git_restore_staged"    -> Staging.handleRestoreStaged ctx params
  -- Remote
  "git_remote_list"       -> Remote.handleList ctx params
  "git_remote_add"        -> Remote.handleAdd ctx params
  "git_remote_remove"     -> Remote.handleRemove ctx params
  "git_fetch"             -> Remote.handleFetch ctx params
  "git_pull"              -> Remote.handlePull ctx params
  "git_push"              -> Remote.handlePush ctx params
  -- Stash
  "git_stash_push"        -> Stash.handlePush ctx params
  "git_stash_pop"         -> Stash.handlePop ctx params
  "git_stash_list"        -> Stash.handleList ctx params
  "git_stash_show"        -> Stash.handleShow ctx params
  "git_stash_drop"        -> Stash.handleDrop ctx params
  -- Tag
  "git_tag_list"          -> Tag.handleList ctx params
  "git_tag_create"        -> Tag.handleCreate ctx params
  "git_tag_delete"        -> Tag.handleDelete ctx params
  -- Merge
  "git_merge"             -> Merge.handle ctx params
  "git_merge_abort"       -> Merge.handleAbort ctx params
  "git_merge_status"      -> Merge.handleStatus ctx params
  -- Rebase
  "git_rebase"            -> Rebase.handle ctx params
  "git_rebase_interactive"-> Rebase.handleInteractive ctx params
  "git_rebase_abort"      -> Rebase.handleAbort ctx params
  "git_rebase_continue"   -> Rebase.handleContinue ctx params
  -- Cherry-pick
  "git_cherry_pick"       -> Cherry.handle ctx params
  "git_cherry_pick_abort" -> Cherry.handleAbort ctx params
  -- Worktree
  "git_worktree_list"     -> Worktree.handleList ctx params
  "git_worktree_add"      -> Worktree.handleAdd ctx params
  "git_worktree_remove"   -> Worktree.handleRemove ctx params
  -- Submodule
  "git_submodule_list"    -> Submodule.handleList ctx params
  "git_submodule_add"     -> Submodule.handleAdd ctx params
  "git_submodule_update"  -> Submodule.handleUpdate ctx params
  "git_submodule_sync"    -> Submodule.handleSync ctx params
  -- Config
  "git_config_get"        -> Config.handleGet ctx params
  "git_config_set"        -> Config.handleSet ctx params
  "git_config_list"       -> Config.handleList ctx params
  -- Blame
  "git_blame"             -> Blame.handle ctx params
  -- Bisect
  "git_bisect_start"      -> Bisect.handleStart ctx params
  "git_bisect_good"       -> Bisect.handleGood ctx params
  "git_bisect_bad"        -> Bisect.handleBad ctx params
  "git_bisect_reset"      -> Bisect.handleReset ctx params
  -- Clean
  "git_clean"             -> Clean.handle ctx params
  "git_clean_dry_run"     -> Clean.handleDryRun ctx params
  -- Reset
  "git_reset"             -> Reset.handle ctx params
  "git_reset_file"        -> Reset.handleFile ctx params
  -- Reflog
  "git_reflog"            -> Reflog.handle ctx params
  -- Search
  "git_grep"              -> Search.handleGrep ctx params
  "git_log_search"        -> Search.handleLogSearch ctx params
  -- Patch
  "git_format_patch"      -> Patch.handleFormatPatch ctx params
  "git_apply"             -> Patch.handleApply ctx params
  -- Archive
  "git_archive"           -> Archive.handle ctx params
  -- Hooks
  "git_hooks_list"        -> Hooks.handleList ctx params
  -- Inspect
  "git_cat_file"          -> Inspect.handleCatFile ctx params
  "git_ls_files"          -> Inspect.handleLsFiles ctx params
  "git_ls_tree"           -> Inspect.handleLsTree ctx params
  "git_rev_parse"         -> Inspect.handleRevParse ctx params
  "git_count_objects"     -> Inspect.handleCountObjects ctx params
  -- Composite operations
  "git_branch_cleanup"    -> Composite.handleBranchCleanup ctx params
  "git_sync_fork"         -> Composite.handleSyncFork ctx params
  "git_repo_health"       -> Composite.handleRepoHealth ctx params
  "git_changelog_generate"-> Composite.handleChangelogGenerate ctx params

  _ -> pure $ ToolResult [TextContent ("Unknown tool: " <> name)] True
