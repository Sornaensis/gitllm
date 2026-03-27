{-# LANGUAGE OverloadedStrings #-}

module GitLLM.Git.Tools.Inspect
  ( tools
  , handleCatFile, handleLsFiles, handleLsTree
  , handleRevParse, handleCountObjects
  , handleDescribe
  , handleNotesList, handleNotesAdd, handleNotesShow
  , handleNameRev
  ) where

import Data.Aeson
import Data.Text (Text)
import GitLLM.MCP.Types
import GitLLM.Git.Types
import GitLLM.Git.Runner
import GitLLM.Git.Tools.Helpers

tools :: [ToolDefinition]
tools =
  [ mkToolDefA "git_cat_file"
      "Display the contents, type, or size of a git object. Returns raw object content"
      (mkSchema
        [ "object" .= object [ "type" .= ("string" :: Text), "description" .= ("Object hash or ref" :: Text) ]
        , "mode" .= object [ "type" .= ("string" :: Text), "description" .= ("Output mode" :: Text), "enum" .= (["content", "type", "size"] :: [Text]), "default" .= ("content" :: Text) ]
        ]
        ["object"])
      readOnly
  , mkToolDefA "git_ls_files"
      "List files tracked by git, with optional filters. Returns one path per line"
      (mkSchema
        [ "stage" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show staged contents (mode, object, stage number)" :: Text) ]
        , "modified" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show only modified files" :: Text) ]
        , "others" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show untracked files" :: Text) ]
        , "path" .= object [ "type" .= ("string" :: Text), "description" .= ("Limit to a specific path" :: Text) ]
        ]
        [])
      readOnly
  , mkToolDefA "git_ls_tree"
      "List the contents of a tree object (directory at a commit). Returns one path per line"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Tree-ish ref" :: Text), "default" .= ("HEAD" :: Text) ]
        , "path" .= object [ "type" .= ("string" :: Text), "description" .= ("Subdirectory path" :: Text) ]
        , "recursive" .= object [ "type" .= ("boolean" :: Text), "description" .= ("List tree recursively" :: Text) ]
        , "name_only" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show only names" :: Text) ]
        ]
        [])
      readOnly
  , mkToolDefA "git_rev_parse"
      "Parse a revision string and output the corresponding object name (SHA)"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Ref to parse (e.g. HEAD, branch name, tag)" :: Text) ]
        , "short" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Output abbreviated SHA" :: Text) ]
        ]
        ["ref"])
      readOnly
  , mkToolDefA "git_count_objects"
      "Count unpacked objects and their disk consumption"
      (mkSchema
        [ "verbose" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Show detailed breakdown" :: Text) ] ]
        [])
      readOnly
  , mkToolDefA "git_describe"
      "Find the most recent tag reachable from a commit. Useful for version identification"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Commit to describe (default: HEAD)" :: Text) ]
        , "all" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Use any ref, not just annotated tags" :: Text) ]
        , "tags" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Use any tag, including lightweight tags" :: Text) ]
        , "long" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Always output the long format" :: Text) ]
        , "abbrev" .= object [ "type" .= ("integer" :: Text), "description" .= ("Number of hex digits for the abbreviated object name" :: Text) ]
        ]
        [])
      readOnly
  , mkToolDefA "git_notes_list"
      "List all notes refs or notes for a given object"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Object to list notes for (default: list all)" :: Text) ] ]
        [])
      readOnly
  , mkToolDefA "git_notes_add"
      "Add a note to an object (commit). Overwrites existing note if force is set"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Object to annotate (default: HEAD)" :: Text) ]
        , "message" .= object [ "type" .= ("string" :: Text), "description" .= ("Note message" :: Text) ]
        , "force" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Overwrite existing note (default: false)" :: Text) ]
        ]
        ["message"])
      mutating
  , mkToolDefA "git_notes_show"
      "Show the note attached to an object"
      (mkSchema
        [ "ref" .= object [ "type" .= ("string" :: Text), "description" .= ("Object to show note for (default: HEAD)" :: Text) ] ]
        [])
      readOnly
  , mkToolDefA "git_name_rev"
      "Find a symbolic name for a given rev. Shows the nearest ref-relative name (e.g. 'master~3', 'tags/v1.0~2'). Useful for identifying which branch or tag a commit is near"
      (mkSchema
        [ "commit" .= object [ "type" .= ("string" :: Text), "description" .= ("Commit SHA to name" :: Text) ]
        , "refs" .= object [ "type" .= ("string" :: Text), "description" .= ("Only use refs matching this pattern (e.g. 'refs/heads/*' for branches only)" :: Text) ]
        , "no_undefined" .= object [ "type" .= ("boolean" :: Text), "description" .= ("Error if a name cannot be found instead of printing 'undefined'" :: Text) ]
        ]
        ["commit"])
      readOnly
  ]

handleCatFile :: GitContext -> Maybe Value -> IO ToolResult
handleCatFile ctx params = case getTextParam "object" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: object"] True
  Just obj -> do
    let modeFlag = case getTextParam "mode" params of
          Just "type" -> ["-t"]
          Just "size" -> ["-s"]
          _           -> ["-p"]
    result <- runGit ctx (["cat-file"] ++ modeFlag ++ [textArg obj])
    gitResultToToolResult result

handleLsFiles :: GitContext -> Maybe Value -> IO ToolResult
handleLsFiles ctx params = do
  let stageFlag = if getBoolParam "stage" params == Just True then ["-s"] else []
      modFlag   = if getBoolParam "modified" params == Just True then ["-m"] else []
      othFlag   = if getBoolParam "others" params == Just True then ["-o"] else []
      pathArg   = maybe [] (\p -> ["--", textArg p]) (getTextParam "path" params)
  result <- runGit ctx (["ls-files"] ++ stageFlag ++ modFlag ++ othFlag ++ pathArg)
  gitResultToToolResult result

handleLsTree :: GitContext -> Maybe Value -> IO ToolResult
handleLsTree ctx params = do
  let ref       = maybe "HEAD" textArg (getTextParam "ref" params)
      recFlag   = if getBoolParam "recursive" params == Just True then ["-r"] else []
      nameFlag  = if getBoolParam "name_only" params == Just True then ["--name-only"] else []
      pathArg   = maybe [] (\p -> ["--", textArg p]) (getTextParam "path" params)
  result <- runGit ctx (["ls-tree"] ++ recFlag ++ nameFlag ++ [ref] ++ pathArg)
  gitResultToToolResult result

handleRevParse :: GitContext -> Maybe Value -> IO ToolResult
handleRevParse ctx params = case getTextParam "ref" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: ref"] True
  Just ref -> do
    let shortFlag = if getBoolParam "short" params == Just True then ["--short"] else []
    result <- runGit ctx (["rev-parse"] ++ shortFlag ++ [textArg ref])
    gitResultToToolResult result

handleCountObjects :: GitContext -> Maybe Value -> IO ToolResult
handleCountObjects ctx params = do
  let vFlag = if getBoolParam "verbose" params == Just True then ["-v"] else []
  result <- runGit ctx (["count-objects"] ++ vFlag)
  gitResultToToolResult result

handleDescribe :: GitContext -> Maybe Value -> IO ToolResult
handleDescribe ctx params = do
  let ref      = maybe [] (\r -> [textArg r]) (getTextParam "ref" params)
      allFlag  = if getBoolParam "all" params == Just True then ["--all"] else []
      tagsFlag = if getBoolParam "tags" params == Just True then ["--tags"] else []
      longFlag = if getBoolParam "long" params == Just True then ["--long"] else []
      abbrFlag = maybe [] (\n -> ["--abbrev=" ++ show n]) (getIntParam "abbrev" params)
  result <- runGit ctx (["describe"] ++ allFlag ++ tagsFlag ++ longFlag ++ abbrFlag ++ ref)
  gitResultToToolResult result

handleNotesList :: GitContext -> Maybe Value -> IO ToolResult
handleNotesList ctx params = do
  let refArg = maybe [] (\r -> [textArg r]) (getTextParam "ref" params)
  result <- runGit ctx (["notes", "list"] ++ refArg)
  gitResultToToolResult result

handleNotesAdd :: GitContext -> Maybe Value -> IO ToolResult
handleNotesAdd ctx params = case getTextParam "message" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: message"] True
  Just msg -> do
    let refArg   = maybe [] (\r -> [textArg r]) (getTextParam "ref" params)
        forceFlg = if getBoolParam "force" params == Just True then ["-f"] else []
    result <- runGit ctx (["notes", "add"] ++ forceFlg ++ ["-m", textArg msg] ++ refArg)
    gitResultToToolResult result

handleNotesShow :: GitContext -> Maybe Value -> IO ToolResult
handleNotesShow ctx params = do
  let refArg = maybe [] (\r -> [textArg r]) (getTextParam "ref" params)
  result <- runGit ctx (["notes", "show"] ++ refArg)
  gitResultToToolResult result

handleNameRev :: GitContext -> Maybe Value -> IO ToolResult
handleNameRev ctx params = case getTextParam "commit" params of
  Nothing -> pure $ ToolResult [TextContent "Missing required parameter: commit"] True
  Just commit -> do
    let refsFlag = maybe [] (\r -> ["--refs", textArg r]) (getTextParam "refs" params)
        noUndefFlag = if getBoolParam "no_undefined" params == Just True then ["--no-undefined"] else []
    result <- runGit ctx (["name-rev"] ++ refsFlag ++ noUndefFlag ++ [textArg commit])
    gitResultToToolResult result
