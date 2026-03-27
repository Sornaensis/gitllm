{-# LANGUAGE OverloadedStrings #-}

module GitLLM.MCP.Router
  ( routeRequest
  , allToolDefinitions
  ) where

import Data.Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import Data.IORef (readIORef, writeIORef)
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, doesFileExist, createDirectoryIfMissing)
import System.FilePath ((</>))
import GitLLM.MCP.Types
import GitLLM.Git.Types (GitContext(..), GitError(..), ServerState(..))
import GitLLM.Git.Runner (runGit)

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
allToolDefinitions = repoToolDefinitions ++ concat
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

-- | Tool definitions for repo root management.
repoToolDefinitions :: [ToolDefinition]
repoToolDefinitions =
  [ ToolDefinition
      "git_set_repo"
      "REQUIRED FIRST CALL — Set the git repository root before using any other git tool. Pass the absolute path to the workspace or repository root directory (e.g. the folder open in your editor). All other tools will fail until this is called."
      (object
        [ "type" .= ("object" :: Text)
        , "properties" .= object
            [ "path" .= object
                [ "type" .= ("string" :: Text)
                , "description" .= ("Absolute path to the git repository root directory. Use the workspace folder path from your environment context." :: Text)
                ]
            ]
        , "required" .= (["path"] :: [Text])
        , "additionalProperties" .= False
        ])
      (Just $ ToolAnnotations (Just False) (Just False) Nothing)
  , ToolDefinition
      "git_get_repo"
      "Get the current git repository root directory, or an error if not yet set."
      (object
        [ "type" .= ("object" :: Text)
        , "properties" .= object []
        , "additionalProperties" .= False
        ])
      (Just $ ToolAnnotations (Just True) (Just False) Nothing)
  , ToolDefinition
      "git_init"
      "Initialize a new git repository at the given path. Also sets the repo root for subsequent tool calls."
      (object
        [ "type" .= ("object" :: Text)
        , "properties" .= object
            [ "path" .= object
                [ "type" .= ("string" :: Text)
                , "description" .= ("Absolute path to the directory to initialize as a git repository" :: Text)
                ]
            , "bare" .= object
                [ "type" .= ("boolean" :: Text)
                , "description" .= ("Create a bare repository" :: Text)
                ]
            ]
        , "required" .= (["path"] :: [Text])
        , "additionalProperties" .= False
        ])
      (Just $ ToolAnnotations (Just False) (Just False) Nothing)
  ]

-- | Route a tools/call request to the appropriate handler.
routeRequest :: ServerState -> Text -> Maybe Value -> IO ToolResult
routeRequest state name params = case name of
  -- Repo management tools (work without repo being set)
  "git_set_repo" -> handleSetRepo state params
  "git_get_repo" -> handleGetRepo state
  "git_init"     -> handleInit state params

  -- All other tools require repo to be set
  _ -> do
    mPath <- readIORef (stateRepoPath state)
    case mPath of
      Nothing -> pure $ ToolResult
        [TextContent $ "ERROR: Repository root not set. Call git_set_repo with the absolute path to the repository before using " <> name <> "."]
        True
      Just path -> do
        let ctx = GitContext path (stateTimeout state)
        result <- routeGitTool ctx name params
        pure $ tagRepoPath path result

-- | Prepend the repo root to the tool result so the LLM always knows the context.
tagRepoPath :: FilePath -> ToolResult -> ToolResult
tagRepoPath path (ToolResult contents isErr) =
  let tag = TextContent ("[repo: " <> T.pack path <> "]")
  in ToolResult (tag : contents) isErr

-- | Handle git_set_repo: validate and set the repository root.
handleSetRepo :: ServerState -> Maybe Value -> IO ToolResult
handleSetRepo state params = case getPathParam params of
  Nothing -> pure $ ToolResult
    [TextContent "ERROR: git_set_repo requires a 'path' parameter with the absolute path to the git repository."]
    True
  Just path -> do
    let pathStr = T.unpack path
    -- Verify the directory exists
    dirExists <- doesDirectoryExist pathStr
    if not dirExists
      then pure $ ToolResult
        [TextContent $ "ERROR: Directory does not exist: " <> path]
        True
      else do
        -- Verify it's a git repo (has .git directory or file)
        let gitPath = pathStr </> ".git"
        gitDirExists <- doesDirectoryExist gitPath
        gitFileExists <- doesFileExist gitPath
        if not (gitDirExists || gitFileExists)
          then pure $ ToolResult
            [TextContent $ "ERROR: Not a git repository (no .git directory): " <> path]
            True
          else do
            writeIORef (stateRepoPath state) (Just pathStr)
            pure $ ToolResult
              [TextContent $ "Repository root set to: " <> path]
              False
  where
    getPathParam (Just (Object o)) = case KM.lookup "path" o of
      Just (String s) -> Just s
      _               -> Nothing
    getPathParam _ = Nothing

-- | Handle git_get_repo: return the current repo root.
handleGetRepo :: ServerState -> IO ToolResult
handleGetRepo state = do
  mPath <- readIORef (stateRepoPath state)
  case mPath of
    Nothing -> pure $ ToolResult
      [TextContent "Repository root is not set. Call git_set_repo first."]
      True
    Just path -> pure $ ToolResult
      [TextContent $ "Repository root: " <> T.pack path]
      False

-- | Handle git_init: initialize a new repo and set it as the active repo.
handleInit :: ServerState -> Maybe Value -> IO ToolResult
handleInit state params = case getPathParam params of
  Nothing -> pure $ ToolResult
    [TextContent "ERROR: git_init requires a 'path' parameter with the absolute path to the directory."]
    True
  Just path -> do
    let pathStr = T.unpack path
    -- Create directory if it doesn't exist
    createDirectoryIfMissing True pathStr
    -- Check it's not already a git repo
    let gitPath = pathStr </> ".git"
    gitExists <- doesDirectoryExist gitPath
    if gitExists
      then pure $ ToolResult
        [TextContent $ "ERROR: Already a git repository: " <> path]
        True
      else do
        let bareFlag = case getBoolParam "bare" params of
              Just True -> ["--bare"]
              _         -> []
            ctx = GitContext pathStr (stateTimeout state)
        result <- runGit ctx (["init"] ++ bareFlag ++ [pathStr])
        case result of
          Right out -> do
            writeIORef (stateRepoPath state) (Just pathStr)
            pure $ ToolResult
              [TextContent $ out <> "\nRepository root set to: " <> path]
              False
          Left (GitProcessError _ err) -> pure $ ToolResult [TextContent err] True
          Left (GitParseError err)     -> pure $ ToolResult [TextContent err] True
          Left (GitValidationError err)-> pure $ ToolResult [TextContent err] True
          Left (GitTimeoutError secs)  -> pure $ ToolResult [TextContent ("Command timed out after " <> T.pack (show secs) <> " seconds")] True
  where
    getPathParam (Just (Object o)) = case KM.lookup "path" o of
      Just (String s) -> Just s
      _               -> Nothing
    getPathParam _ = Nothing
    getBoolParam key (Just (Object o)) = case KM.lookup (Key.fromText key) o of
      Just (Bool b) -> Just b
      _             -> Nothing
    getBoolParam _ _ = Nothing

-- | Route git tool calls to the appropriate handler.
routeGitTool :: GitContext -> Text -> Maybe Value -> IO ToolResult
routeGitTool ctx name params = case name of
  -- Status
  "git_status"            -> Status.handle ctx params
  "git_status_short"      -> Status.handleShort ctx params
  -- Log
  "git_log"               -> Log.handle ctx params
  "git_log_oneline"       -> Log.handleOneline ctx params
  "git_log_file"          -> Log.handleFile ctx params
  "git_log_graph"         -> Log.handleGraph ctx params
  "git_shortlog"           -> Log.handleShortlog ctx params
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
  "git_rm"                -> Staging.handleRm ctx params
  "git_mv"                -> Staging.handleMv ctx params
  -- Remote
  "git_remote_list"       -> Remote.handleList ctx params
  "git_remote_add"        -> Remote.handleAdd ctx params
  "git_remote_remove"     -> Remote.handleRemove ctx params
  "git_fetch"             -> Remote.handleFetch ctx params
  "git_pull"              -> Remote.handlePull ctx params
  "git_push"              -> Remote.handlePush ctx params
  "git_remote_get_url"    -> Remote.handleGetUrl ctx params
  "git_remote_set_url"    -> Remote.handleSetUrl ctx params
  -- Stash
  "git_stash_push"        -> Stash.handlePush ctx params
  "git_stash_pop"         -> Stash.handlePop ctx params
  "git_stash_apply"       -> Stash.handleApply ctx params
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
  "git_merge_base"        -> Merge.handleMergeBase ctx params
  -- Rebase
  "git_rebase"            -> Rebase.handle ctx params
  "git_rebase_interactive"-> Rebase.handleInteractive ctx params
  "git_rebase_abort"      -> Rebase.handleAbort ctx params
  "git_rebase_continue"   -> Rebase.handleContinue ctx params
  -- Cherry-pick
  "git_cherry_pick"       -> Cherry.handle ctx params
  "git_cherry_pick_abort" -> Cherry.handleAbort ctx params
  "git_revert"            -> Cherry.handleRevert ctx params
  -- Worktree
  "git_worktree_list"     -> Worktree.handleList ctx params
  "git_worktree_add"      -> Worktree.handleAdd ctx params
  "git_worktree_remove"   -> Worktree.handleRemove ctx params
  -- Submodule
  "git_submodule_list"    -> Submodule.handleList ctx params
  "git_submodule_add"     -> Submodule.handleAdd ctx params
  "git_submodule_update"  -> Submodule.handleUpdate ctx params
  "git_submodule_sync"    -> Submodule.handleSync ctx params
  "git_submodule_deinit"  -> Submodule.handleDeinit ctx params
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
  "git_gc"                -> Clean.handleGc ctx params
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
  "git_describe"          -> Inspect.handleDescribe ctx params
  "git_notes_list"        -> Inspect.handleNotesList ctx params
  "git_notes_add"         -> Inspect.handleNotesAdd ctx params
  "git_notes_show"        -> Inspect.handleNotesShow ctx params
  -- Composite operations
  "git_branch_cleanup"    -> Composite.handleBranchCleanup ctx params
  "git_sync_fork"         -> Composite.handleSyncFork ctx params
  "git_repo_health"       -> Composite.handleRepoHealth ctx params
  "git_changelog_generate"-> Composite.handleChangelogGenerate ctx params
  "git_base_branch"       -> Composite.handleBaseBranch ctx params

  _ -> pure $ ToolResult [TextContent ("Unknown tool: " <> name)] True
