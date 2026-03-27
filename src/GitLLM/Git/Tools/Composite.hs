{-# LANGUAGE OverloadedStrings #-}

-- | High-level composite git operations that orchestrate multiple git commands.
module GitLLM.Git.Tools.Composite
  ( tools
  , handleBranchCleanup
  , handleSyncFork
  , handleRepoHealth
  , handleChangelogGenerate
  , handleBaseBranch
  , extractCommitType
  , parseChangelogEntries
  , filterBranches
  ) where

import Data.Aeson
import Data.Aeson.Key (Key, fromText, toText)
import qualified Data.Aeson.KeyMap as KM
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Vector as V
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_branch_cleanup"
      "Remove local branches that have been fully merged into a target branch. Use dry_run to preview which branches would be deleted"
      (mkSchema
        [ "target" .= object
            [ "type" .= ("string" :: Text)
            , "description" .= ("Branch to check merge status against (default: current branch)" :: Text)
            ]
        , "dry_run" .= object
            [ "type" .= ("boolean" :: Text)
            , "description" .= ("If true, only list branches that would be deleted without deleting them (default: true)" :: Text)
            ]
        , "include_remote" .= object
            [ "type" .= ("boolean" :: Text)
            , "description" .= ("Also consider remote-tracking branches for listing (does not delete remotes)" :: Text)
            ]
        , outputParam
        ]
        [])
      destructive

  , mkToolDefA "git_sync_fork"
      "Sync a fork by fetching from upstream remote, rebasing current branch onto upstream target, and optionally pushing to origin"
      (mkSchema
        [ "upstream" .= object
            [ "type" .= ("string" :: Text)
            , "description" .= ("Name of the upstream remote (default: 'upstream')" :: Text)
            ]
        , "branch" .= object
            [ "type" .= ("string" :: Text)
            , "description" .= ("Upstream branch to sync from (default: 'main')" :: Text)
            ]
        , "push" .= object
            [ "type" .= ("boolean" :: Text)
            , "description" .= ("Push to origin after rebasing (default: false)" :: Text)
            ]
        ]
        [])
      mutating

  , mkToolDefA "git_repo_health"
      "Run a comprehensive health check on the repository: object statistics, fsck integrity check, dangling objects, and stale references"
      (mkSchema
        [ "full" .= object
            [ "type" .= ("boolean" :: Text)
            , "description" .= ("Run a full fsck (slower but more thorough, default: false)" :: Text)
            ]
        , outputParam
        ]
        [])
      readOnly

  , mkToolDefA "git_changelog_generate"
      "Generate a changelog from commit history between two refs or for the last N commits"
      (mkSchema
        [ "from" .= object
            [ "type" .= ("string" :: Text)
            , "description" .= ("Starting ref (exclusive). If omitted with 'to', shows all history up to 'to'" :: Text)
            ]
        , "to" .= object
            [ "type" .= ("string" :: Text)
            , "description" .= ("Ending ref (inclusive, default: HEAD)" :: Text)
            ]
        , "limit" .= object
            [ "type" .= ("integer" :: Text)
            , "description" .= ("Maximum number of commits (default: 50)" :: Text)
            ]
        , "group_by" .= object
            [ "type" .= ("string" :: Text)
            , "description" .= ("Group commits by: 'type' (conventional commits prefix), 'author', or 'none' (default: 'type')" :: Text)
            , "enum" .= (["type", "author", "none"] :: [Text])
            ]
        , outputParam
        ]
        [])
      readOnly

  , mkToolDefA "git_base_branch"
      "Detect the default base branch of the repository (e.g. main, master, develop). Checks the remote HEAD, then falls back to well-known branch names"
      (mkSchema
        [ "remote" .= object
            [ "type" .= ("string" :: Text)
            , "description" .= ("Remote to check (default: 'origin')" :: Text)
            ]
        , outputParam
        ]
        [])
      readOnly
  ]

-- ---------------------------------------------------------------------------
-- git_branch_cleanup
-- ---------------------------------------------------------------------------

handleBranchCleanup :: GitContext -> Maybe Value -> IO ToolResult
handleBranchCleanup ctx params = do
  let target  = maybe "" textArg (getTextParam "target" params)
      dryRun  = getBoolParam "dry_run" params /= Just False  -- default True
  -- Get current branch to protect it
  currentResult <- runGit ctx ["branch", "--show-current"]
  case currentResult of
    Left err -> gitResultToToolResult (Left err)
    Right currentRaw -> do
      let current = T.strip currentRaw
          targetBranch = if T.null (T.strip (T.pack target)) then current else T.strip (T.pack target)
      -- Get merged branches
      mergedResult <- runGit ctx ["branch", "--merged", textArg targetBranch]
      case mergedResult of
        Left err -> gitResultToToolResult (Left err)
        Right mergedRaw -> do
          let merged = filterBranches current targetBranch mergedRaw
          if dryRun
            then dryRunResult params merged targetBranch
            else deleteBranches ctx params merged targetBranch

-- | Filter branch list: remove current branch, target branch, and HEAD pointers.
filterBranches :: Text -> Text -> Text -> [Text]
filterBranches current target raw =
  [ b | line <- T.lines raw
      , let b = T.strip (T.dropWhile (== '*') (T.strip line))
      , not (T.null b)
      , b /= current
      , b /= target
      , not (T.isPrefixOf "(" b)  -- filter out "HEAD detached at ..." etc.
  ]

dryRunResult :: Maybe Value -> [Text] -> Text -> IO ToolResult
dryRunResult params branches target
  | wantsJson params = pure $ jsonResult $ object
      [ "action"  .= ("dry_run" :: Text)
      , "target"  .= target
      , "branches_to_delete" .= branches
      , "count"   .= length branches
      ]
  | null branches = pure $ ToolResult
      [TextContent $ "No merged branches to clean up (target: " <> target <> ")"] False
  | otherwise = pure $ ToolResult
      [TextContent $ "Branches merged into " <> target <> " (would delete):\n"
        <> T.unlines (map ("  " <>) branches)
        <> "\n" <> T.pack (show (length branches)) <> " branch(es). Run with dry_run=false to delete."
      ] False

deleteBranches :: GitContext -> Maybe Value -> [Text] -> Text -> IO ToolResult
deleteBranches _ctx params [] target
  | wantsJson params = pure $ jsonResult $ object
      [ "action"  .= ("cleanup" :: Text)
      , "target"  .= target
      , "deleted" .= ([] :: [Text])
      , "failed"  .= ([] :: [Value])
      , "count"   .= (0 :: Int)
      ]
  | otherwise = pure $ ToolResult
      [TextContent $ "No merged branches to clean up (target: " <> target <> ")"] False
deleteBranches ctx params branches target = do
  results <- mapM (deleteBranch ctx) branches
  let (deleted, failed) = partitionResults results
  if wantsJson params
    then pure $ jsonResult $ object
      [ "action"  .= ("cleanup" :: Text)
      , "target"  .= target
      , "deleted" .= deleted
      , "failed"  .= [ object ["branch" .= b, "error" .= e] | (b, e) <- failed ]
      , "count"   .= length deleted
      ]
    else pure $ ToolResult [TextContent $ formatDeleteResults target deleted failed] (not (null failed))

deleteBranch :: GitContext -> Text -> IO (Text, Either Text Text)
deleteBranch ctx branch = do
  result <- runGit ctx ["branch", "-d", textArg branch]
  pure $ case result of
    Right out -> (branch, Right out)
    Left (GitProcessError _ err) -> (branch, Left err)
    Left (GitParseError err)     -> (branch, Left err)
    Left (GitValidationError err)-> (branch, Left err)
    Left (GitTimeoutError secs)  -> (branch, Left $ "Timed out after " <> T.pack (show secs) <> "s")

partitionResults :: [(Text, Either Text Text)] -> ([Text], [(Text, Text)])
partitionResults = foldr go ([], [])
  where
    go (b, Right _)  (ds, fs) = (b:ds, fs)
    go (b, Left err) (ds, fs) = (ds, (b, err):fs)

formatDeleteResults :: Text -> [Text] -> [(Text, Text)] -> Text
formatDeleteResults target deleted failed = T.unlines $ concat
  [ ["Branches cleaned up (target: " <> target <> "):"]
  , ["  Deleted: " <> b | b <- deleted]
  , ["  FAILED:  " <> b <> " — " <> e | (b, e) <- failed]
  , ["", T.pack (show (length deleted)) <> " deleted, " <> T.pack (show (length failed)) <> " failed"]
  ]

-- ---------------------------------------------------------------------------
-- git_sync_fork
-- ---------------------------------------------------------------------------

handleSyncFork :: GitContext -> Maybe Value -> IO ToolResult
handleSyncFork ctx params = do
  let upstream = maybe "upstream" id (getTextParam "upstream" params)
      branch   = maybe "main"     id (getTextParam "branch" params)
      doPush   = getBoolParam "push" params == Just True
  -- Step 1: fetch upstream
  fetchResult <- runGit ctx ["fetch", textArg upstream]
  case fetchResult of
    Left err -> pure $ ToolResult
      [TextContent $ "Failed to fetch from " <> upstream <> ": " <> gitErrorText err] True
    Right _ -> do
      -- Step 2: rebase onto upstream/branch
      let upstreamRef = upstream <> "/" <> branch
      rebaseResult <- runGit ctx ["rebase", textArg upstreamRef]
      case rebaseResult of
        Left err -> pure $ ToolResult
          [TextContent $ "Fetch succeeded but rebase onto " <> upstreamRef <> " failed: " <> gitErrorText err
            <> "\nRun git_rebase_abort to undo."] True
        Right rebaseOut -> do
          if doPush
            then do
              -- Step 3 (optional): push to origin
              pushResult <- runGit ctx ["push", "origin", "HEAD"]
              case pushResult of
                Left err -> pure $ ToolResult
                  [TextContent $ "Fetch and rebase succeeded but push failed: " <> gitErrorText err] True
                Right pushOut -> pure $ ToolResult
                  [TextContent $ "Fork synced successfully.\n"
                    <> "Fetched: " <> upstream <> "\n"
                    <> "Rebased onto: " <> upstreamRef <> "\n"
                    <> T.strip rebaseOut <> "\n"
                    <> "Pushed to origin.\n"
                    <> T.strip pushOut] False
            else pure $ ToolResult
              [TextContent $ "Fork synced successfully.\n"
                <> "Fetched: " <> upstream <> "\n"
                <> "Rebased onto: " <> upstreamRef <> "\n"
                <> T.strip rebaseOut <> "\n"
                <> "Not pushed (set push=true to push)."] False

-- | Extract readable text from a GitError.
gitErrorText :: GitError -> Text
gitErrorText (GitProcessError _ t) = t
gitErrorText (GitParseError t)     = t
gitErrorText (GitValidationError t)= t
gitErrorText (GitTimeoutError s)   = "Timed out after " <> T.pack (show s) <> " seconds"

-- ---------------------------------------------------------------------------
-- git_repo_health
-- ---------------------------------------------------------------------------

handleRepoHealth :: GitContext -> Maybe Value -> IO ToolResult
handleRepoHealth ctx params = do
  -- 1. Object count/size statistics
  countResult <- runGit ctx ["count-objects", "-vH"]
  -- 2. Fsck integrity check
  let fsckArgs = if getBoolParam "full" params == Just True
                 then ["fsck", "--full", "--no-dangling"]
                 else ["fsck", "--no-dangling"]
  fsckResult <- runGit ctx fsckArgs
  -- 3. Dangling objects
  danglingResult <- runGit ctx ["fsck", "--dangling", "--no-progress"]
  -- 4. Stale remote refs
  staleResult <- runGit ctx ["remote", "prune", "--dry-run", "origin"]

  if wantsJson params
    then pure $ jsonResult $ object
      [ "object_stats" .= resultToText countResult
      , "fsck"         .= object
          [ "passed" .= isRight fsckResult
          , "output" .= resultToText fsckResult
          ]
      , "dangling"     .= parseDangling (resultToText danglingResult)
      , "stale_refs"   .= parseStaleRefs (resultToText staleResult)
      ]
    else pure $ ToolResult [TextContent $ formatHealth countResult fsckResult danglingResult staleResult] False

resultToText :: GitResult -> Text
resultToText (Right t) = t
resultToText (Left (GitProcessError _ t)) = t
resultToText (Left (GitParseError t))     = t
resultToText (Left (GitValidationError t))= t
resultToText (Left (GitTimeoutError s))   = "Timed out after " <> T.pack (show s) <> " seconds"

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight _         = False

parseDangling :: Text -> [Value]
parseDangling raw =
  [ object ["type" .= objType, "sha" .= sha]
  | line <- T.lines raw
  , Just (objType, sha) <- [parseDanglingLine line]
  ]

parseDanglingLine :: Text -> Maybe (Text, Text)
parseDanglingLine line =
  case T.words line of
    ["dangling", objType, sha] -> Just (objType, sha)
    _ -> Nothing

parseStaleRefs :: Text -> [Text]
parseStaleRefs raw =
  [ T.strip ref
  | line <- T.lines raw
  , T.isPrefixOf " * [would prune]" line
  , let ref = T.strip $ T.drop (T.length " * [would prune]") line
  , not (T.null ref)
  ]

formatHealth :: GitResult -> GitResult -> GitResult -> GitResult -> Text
formatHealth countR fsckR danglingR staleR = T.unlines
  [ "=== Repository Health Report ==="
  , ""
  , "--- Object Statistics ---"
  , resultToText countR
  , "--- Integrity Check (fsck) ---"
  , case fsckR of
      Right _ -> "✓ No issues found"
      Left _  -> "✗ Issues detected:\n" <> resultToText fsckR
  , ""
  , "--- Dangling Objects ---"
  , let d = resultToText danglingR
    in if T.null (T.strip d) then "None" else d
  , "--- Stale Remote References ---"
  , let s = resultToText staleR
    in if T.null (T.strip s) then "None" else s
  ]

-- ---------------------------------------------------------------------------
-- git_changelog_generate
-- ---------------------------------------------------------------------------

handleChangelogGenerate :: GitContext -> Maybe Value -> IO ToolResult
handleChangelogGenerate ctx params = do
  let toRef   = maybe "HEAD" id (getTextParam "to" params)
      maxN    = maybe 50 id (getIntParam "limit" params)
      groupBy = maybe "type" id (getTextParam "group_by" params)
      -- Build the rev range
      range   = case getTextParam "from" params of
                  Just from -> [textArg from <> ".." <> textArg toRef]
                  Nothing   -> [textArg toRef]
      -- Use a delimiter-separated format for reliable parsing
      delim   = "---gitllm-cl---"
      fmt     = "--format=" <> delim <> "%H" <> delim <> "%h" <> delim <> "%an" <> delim <> "%as" <> delim <> "%s"
  result <- runGit ctx (["log", fmt, "-n", show maxN] ++ range)
  case result of
    Left err -> gitResultToToolResult (Left err)
    Right raw -> do
      let commits = parseChangelogEntries (T.pack delim) raw
      if wantsJson params
        then pure $ jsonResult $ object
          [ "commits"   .= commits
          , "range"     .= object
              [ "from" .= getTextParam "from" params
              , "to"   .= toRef
              ]
          , "count"     .= length commits
          , "group_by"  .= groupBy
          , "grouped"   .= groupCommits groupBy commits
          ]
        else pure $ ToolResult
          [TextContent $ formatChangelog groupBy commits toRef (getTextParam "from" params)] False

parseChangelogEntries :: Text -> Text -> [Value]
parseChangelogEntries delim raw =
  [ parseChangelogLine delim line
  | line <- T.lines raw
  , T.isPrefixOf delim line
  ]

parseChangelogLine :: Text -> Text -> Value
parseChangelogLine delim line =
  case T.splitOn delim (T.drop (T.length delim) line) of
    [hash, short, author, date, subject] -> object
      [ "hash"    .= hash
      , "short"   .= short
      , "author"  .= author
      , "date"    .= date
      , "subject" .= subject
      , "type"    .= extractCommitType subject
      ]
    _ -> object ["raw" .= line]

-- | Extract conventional commit type prefix (e.g., "feat", "fix", "docs").
extractCommitType :: Text -> Text
extractCommitType subject =
  case T.breakOn ":" subject of
    (prefix, rest)
      | not (T.null rest)
      , T.length prefix <= 20
      , T.all (\c -> c /= ' ' || c == '(' || c == ')') prefix
        -> let base = T.takeWhile (\c -> c /= '(' && c /= '!') prefix
           in if T.null base then "other" else T.toLower (T.strip base)
    _ -> "other"

-- | Group commits by the specified key.
groupCommits :: Text -> [Value] -> Value
groupCommits "author" commits = groupBy' "author" commits
groupCommits "type"   commits = groupBy' "type" commits
groupCommits _        _       = Null

groupBy' :: Text -> [Value] -> Value
groupBy' key commits =
  let groups = foldr (insertGroup key) KM.empty commits
  in Object (KM.map (Array . V.fromList) groups)

insertGroup :: Text -> Value -> KM.KeyMap [Value] -> KM.KeyMap [Value]
insertGroup key val km =
  case val of
    Object o -> case KM.lookup (fromText key) o of
      Just (String k) -> KM.insertWith (++) (fromText k) [val] km
      _               -> KM.insertWith (++) "unknown" [val] km
    _ -> KM.insertWith (++) "unknown" [val] km

formatChangelog :: Text -> [Value] -> Text -> Maybe Text -> Text
formatChangelog groupBy commits toRef fromRef = T.unlines $ concat
  [ ["# Changelog", ""]
  , case fromRef of
      Just f  -> ["Range: " <> f <> ".." <> toRef, ""]
      Nothing -> ["Up to: " <> toRef, ""]
  , if groupBy == "none"
      then formatFlat commits
      else formatGrouped groupBy commits
  , ["", "Total: " <> T.pack (show (length commits)) <> " commit(s)"]
  ]

formatFlat :: [Value] -> [Text]
formatFlat = map formatCommitLine

formatGrouped :: Text -> [Value] -> [Text]
formatGrouped key commits =
  let groups = groupBy' key commits
  in case groups of
    Object km -> concatMap (formatGroup . fmap toList') (KM.toList km)
    _         -> formatFlat commits
  where
    toList' (Array a) = foldr (:) [] a
    toList' v         = [v]

formatGroup :: (Key, [Value]) -> [Text]
formatGroup (k, vs) =
  ["## " <> toText k, ""]
  ++ map formatCommitLine vs
  ++ [""]

formatCommitLine :: Value -> Text
formatCommitLine (Object o) =
  let short   = lookupStr "short" o
      date    = lookupStr "date" o
      author  = lookupStr "author" o
      subject = lookupStr "subject" o
  in "- " <> short <> " " <> date <> " (" <> author <> ") " <> subject
formatCommitLine v = "- " <> T.pack (show v)

lookupStr :: Text -> KM.KeyMap Value -> Text
lookupStr k m = case KM.lookup (fromText k) m of
  Just (String s) -> s
  _               -> ""

-- ---------------------------------------------------------------------------
-- git_base_branch
-- ---------------------------------------------------------------------------

handleBaseBranch :: GitContext -> Maybe Value -> IO ToolResult
handleBaseBranch ctx params = do
  let remote = maybe "origin" id (getTextParam "remote" params)
  -- Strategy 1: check remote HEAD symbolic ref
  symResult <- runGit ctx ["symbolic-ref", "refs/remotes/" <> textArg remote <> "/HEAD"]
  case symResult of
    Right raw -> do
      let branch = T.strip $ stripRemotePrefix remote raw
      if T.null branch
        then fallbackDetect ctx params remote
        else returnBranch params remote branch "remote HEAD"
    Left _ -> fallbackDetect ctx params remote

-- | Strip "refs/remotes/<remote>/" prefix from a ref.
stripRemotePrefix :: Text -> Text -> Text
stripRemotePrefix remote ref =
  let prefix = "refs/remotes/" <> remote <> "/"
  in if T.isPrefixOf prefix stripped then T.drop (T.length prefix) stripped else stripped
  where stripped = T.strip ref

-- | Fallback: check for well-known branch names.
fallbackDetect :: GitContext -> Maybe Value -> Text -> IO ToolResult
fallbackDetect ctx params remote = do
  let candidates = ["main", "master", "develop", "development", "trunk"]
  branchesResult <- runGit ctx ["branch", "-a", "--format=%(refname:short)"]
  case branchesResult of
    Left err -> gitResultToToolResult (Left err)
    Right raw -> do
      let branches = map T.strip (T.lines raw)
          -- Check remote branches first, then local
          found = firstMatch remote candidates branches
      case found of
        Just branch -> returnBranch params remote branch "branch name heuristic"
        Nothing     -> pure $ ToolResult
          [TextContent $ "Could not detect a base branch. No remote HEAD and none of "
            <> T.intercalate ", " candidates <> " found."] True

-- | Find the first candidate that exists as a branch (remote or local).
firstMatch :: Text -> [Text] -> [Text] -> Maybe Text
firstMatch remote candidates branches = go candidates
  where
    go [] = Nothing
    go (c:cs)
      | (remote <> "/" <> c) `elem` branches = Just c
      | c `elem` branches                    = Just c
      | otherwise                            = go cs

returnBranch :: Maybe Value -> Text -> Text -> Text -> IO ToolResult
returnBranch params remote branch method
  | wantsJson params = pure $ jsonResult $ object
      [ "base_branch" .= branch
      , "remote"      .= remote
      , "method"      .= method
      ]
  | otherwise = pure $ ToolResult [TextContent branch] False
