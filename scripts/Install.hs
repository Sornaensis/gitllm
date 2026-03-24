{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE CPP #-}

-- | Haskell-based install script for gitllm.
--
-- Handles:
--   1. Copying the gitllm binary to the appropriate system location
--   2. Writing MCP server configuration for Claude Code
--   3. Writing MCP server configuration for GitHub Copilot (VS Code)
--   4. Installing Claude agent instructions (~/.claude/commands/)
--   5. Installing Copilot agent definition (VS Code user agents)
--
-- MCP definitions and agent files are read from the config/ directory.
-- Each component can be disabled individually via --no-{client}-{type} flags.
--
-- Works on both Windows and Linux/macOS.

module Main (main) where

import Control.Monad (when, unless)
import Data.Aeson (Value(..), object, (.=), encode, eitherDecodeStrict)
import Data.Aeson.Key (Key)
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import qualified Data.Text.IO as TIO
import Options.Applicative
import System.Directory
import System.Environment (lookupEnv)
import System.Exit (ExitCode(..), exitFailure)
import System.FilePath ((</>), takeDirectory)
import System.Info (os)
import System.IO (hPutStrLn, stderr)
import System.Process (readProcessWithExitCode)

-- ---------------------------------------------------------------------------
-- CLI
-- ---------------------------------------------------------------------------

data InstallOpts = InstallOpts
  { optBinaryOnly    :: Bool
  , optConfigOnly    :: Bool
  , optDryRun        :: Bool
  , optBinaryPath    :: Maybe FilePath
  , optNoClaudeMcp   :: Bool
  , optNoClaudeAgent :: Bool
  , optNoCopilotMcp  :: Bool
  , optNoCopilotAgent :: Bool
  , optConfigDir     :: FilePath
  , optUninstall     :: Bool
  , optWorkspace     :: Maybe FilePath
  }

installOptsParser :: Parser InstallOpts
installOptsParser = InstallOpts
  <$> switch
      ( long "binary-only"
     <> help "Only install the binary, skip MCP config generation"
      )
  <*> switch
      ( long "config-only"
     <> help "Only generate MCP configs, skip binary installation"
      )
  <*> switch
      ( long "dry-run"
     <> short 'n'
     <> help "Show what would be done without making changes"
      )
  <*> optional (strOption
      ( long "binary-path"
     <> metavar "PATH"
     <> help "Custom path to install the binary"
      ))
  <*> switch
      ( long "no-claude-mcp"
     <> help "Skip Claude MCP server configuration"
      )
  <*> switch
      ( long "no-claude-agent"
     <> help "Skip Claude agent instructions installation"
      )
  <*> switch
      ( long "no-copilot-mcp"
     <> help "Skip Copilot MCP server configuration"
      )
  <*> switch
      ( long "no-copilot-agent"
     <> help "Skip Copilot agent definition installation"
      )
  <*> strOption
      ( long "config-dir"
     <> metavar "DIR"
     <> value "config"
     <> showDefault
     <> help "Path to the config definitions directory"
      )
  <*> switch
      ( long "uninstall"
     <> help "Remove gitllm binary, MCP configs, and agent files"
      )
  <*> optional (strOption
      ( long "workspace"
     <> short 'w'
     <> metavar "DIR"
     <> help "Install into a VS Code workspace (.vscode/mcp.json + .github/copilot/ prompts)"
      ))

-- ---------------------------------------------------------------------------
-- Platform detection
-- ---------------------------------------------------------------------------

data Platform = Windows | Linux | MacOS | UnknownPlatform String
  deriving (Show, Eq)

currentPlatform :: Platform
currentPlatform = case os of
  "mingw32" -> Windows
  "linux"   -> Linux
  "darwin"  -> MacOS
  other     -> UnknownPlatform other

isWindows :: Bool
isWindows = currentPlatform == Windows

binaryName :: String
binaryName = if isWindows then "gitllm.exe" else "gitllm"

-- ---------------------------------------------------------------------------
-- Paths
-- ---------------------------------------------------------------------------

-- | Default binary install directory per platform.
defaultBinDir :: IO FilePath
defaultBinDir = case currentPlatform of
  Windows -> do
    appData <- getAppUserDataDirectory "gitllm"
    pure (appData </> "bin")
  _ -> do
    home <- getHomeDirectory
    pure (home </> ".local" </> "bin")

-- | Claude Code config file location.
claudeConfigPath :: IO FilePath
claudeConfigPath = case currentPlatform of
  Windows -> do
    appData <- getEnv' "APPDATA"
    pure (appData </> "Claude" </> "claude_desktop_config.json")
  MacOS -> do
    home <- getHomeDirectory
    pure (home </> "Library" </> "Application Support" </> "Claude" </> "claude_desktop_config.json")
  _ -> do
    home <- getHomeDirectory
    pure (home </> ".claude" </> "claude_desktop_config.json")

-- | VS Code user-level mcp.json location.
vscodeMcpPath :: IO FilePath
vscodeMcpPath = case currentPlatform of
  Windows -> do
    appData <- getEnv' "APPDATA"
    pure (appData </> "Code" </> "User" </> "mcp.json")
  MacOS -> do
    home <- getHomeDirectory
    pure (home </> "Library" </> "Application Support" </> "Code" </> "User" </> "mcp.json")
  _ -> do
    home <- getHomeDirectory
    pure (home </> ".config" </> "Code" </> "User" </> "mcp.json")

-- | Claude agent instructions install directory.
claudeAgentDir :: IO FilePath
claudeAgentDir = do
  home <- getHomeDirectory
  pure (home </> ".claude" </> "commands")

-- | VS Code user-level prompts directory.
vscodePromptsDir :: IO FilePath
vscodePromptsDir = case currentPlatform of
  Windows -> do
    appData <- getEnv' "APPDATA"
    pure (appData </> "Code" </> "User" </> "prompts")
  MacOS -> do
    home <- getHomeDirectory
    pure (home </> "Library" </> "Application Support" </> "Code" </> "User" </> "prompts")
  _ -> do
    home <- getHomeDirectory
    pure (home </> ".config" </> "Code" </> "User" </> "prompts")

-- | Get an environment variable with fallback to home directory.
getEnv' :: String -> IO FilePath
getEnv' var = do
  val <- lookupEnv var
  case val of
    Just v  -> pure v
    Nothing -> getHomeDirectory

-- ---------------------------------------------------------------------------
-- Binary installation
-- ---------------------------------------------------------------------------

installBinary :: InstallOpts -> FilePath -> IO ()
installBinary opts binDir = do
  let destPath = binDir </> binaryName

  -- Find the built binary from Stack
  stackLocalBin <- findStackBinary
  case stackLocalBin of
    Nothing -> do
      hPutStrLn stderr "ERROR: Could not find built gitllm binary."
      hPutStrLn stderr "       Run 'stack build' first, then re-run the installer."
      exitFailure
    Just srcPath -> do
      logInfo $ "Installing binary:"
      logInfo $ "  from: " ++ srcPath
      logInfo $ "  to:   " ++ destPath

      unless (optDryRun opts) $ do
        createDirectoryIfMissing True binDir
        copyFile srcPath destPath
        -- Make executable on Unix
        case currentPlatform of
          Windows -> pure ()
          _ -> do
            perms <- getPermissions destPath
            setPermissions destPath (setOwnerExecutable True perms)

      success $ "Binary installed to " ++ destPath

-- | Try to locate the stack-built binary.
-- First asks Stack for its local-install-root, then falls back to common paths.
findStackBinary :: IO (Maybe FilePath)
findStackBinary = do
  -- Primary: ask Stack directly where it installs binaries
  stackRoot <- getStackInstallRoot
  case stackRoot of
    Just root -> do
      let candidate = root </> "bin" </> binaryName
      exists <- doesFileExist candidate
      if exists then pure (Just candidate) else searchFallbacks
    Nothing -> searchFallbacks
  where
    searchFallbacks = do
      home <- getHomeDirectory
      let candidates = case currentPlatform of
            Windows ->
              [ home </> ".local" </> "bin" </> binaryName
              , home </> "AppData" </> "Local" </> "bin" </> binaryName
              ]
            _ ->
              [ home </> ".local" </> "bin" </> binaryName
              ]
      findFirst candidates

    findFirst [] = pure Nothing
    findFirst (p:ps) = do
      exists <- doesFileExist p
      if exists then pure (Just p) else findFirst ps

-- | Run @stack path --local-install-root@ to find where Stack builds to.
getStackInstallRoot :: IO (Maybe FilePath)
getStackInstallRoot = do
  result <- tryReadProcess "stack" ["path", "--local-install-root"] ""
  case result of
    Just out -> let trimmed = T.unpack . T.strip . T.pack $ out
                in if null trimmed then pure Nothing else pure (Just trimmed)
    Nothing  -> pure Nothing

-- | Safely run a process and capture stdout. Returns Nothing on failure.
tryReadProcess :: FilePath -> [String] -> String -> IO (Maybe String)
tryReadProcess cmd args input = do
  (exitCode, out, _err) <- readProcessWithExitCode cmd args input
  pure $ case exitCode of
    ExitSuccess -> Just out
    _           -> Nothing

-- ---------------------------------------------------------------------------
-- MCP template reading
-- ---------------------------------------------------------------------------

-- | Read an MCP template JSON from the config directory, substituting the
--   binary path for the {{GITLLM_PATH}} placeholder.
readMcpTemplate :: FilePath -> FilePath -> IO Value
readMcpTemplate templatePath binaryPath = do
  exists <- doesFileExist templatePath
  if exists
    then do
      template <- TIO.readFile templatePath
      let filled = T.replace "{{GITLLM_PATH}}" (T.pack binaryPath) template
      case eitherDecodeStrict (encodeUtf8 filled) of
        Right val -> pure val
        Left err  -> do
          hPutStrLn stderr $ "WARNING: Could not parse MCP template " ++ templatePath ++ ": " ++ err
          pure $ fallbackEntry binaryPath
    else do
      hPutStrLn stderr $ "WARNING: MCP template not found: " ++ templatePath
      hPutStrLn stderr   "         Using built-in default."
      pure $ fallbackEntry binaryPath
  where
    fallbackEntry bp = object
      [ "command" .= bp
      , "args"    .= ([] :: [Text])
      ]

-- ---------------------------------------------------------------------------
-- MCP config: Claude Code
-- ---------------------------------------------------------------------------

installClaudeMcp :: InstallOpts -> FilePath -> IO ()
installClaudeMcp opts binaryAbsPath = do
  configPath <- claudeConfigPath
  let templatePath = optConfigDir opts </> "claude" </> "mcp.json"

  logInfo $ "Configuring Claude Code MCP:"
  logInfo $ "  config:   " ++ configPath
  logInfo $ "  template: " ++ templatePath

  unless (optDryRun opts) $ do
    entry <- readMcpTemplate templatePath binaryAbsPath
    createDirectoryIfMissing True (takeDirectory configPath)

    existing <- doesFileExist configPath
    config <- if existing
      then do
        contents <- BS.readFile configPath
        if BS.null contents
          then pure (object [])
          else case eitherDecodeStrict contents of
            Right val -> pure val
            Left _    -> do
              hPutStrLn stderr "WARNING: Could not parse existing Claude config"
              hPutStrLn stderr "         Existing content will be replaced."
              pure (object [])
      else pure (object [])

    let updated = mergeClaudeConfig config entry
    BL.writeFile configPath (encode updated)

  success "Claude Code MCP configured"

-- | Merge a gitllm server entry into existing Claude config.
mergeClaudeConfig :: Value -> Value -> Value
mergeClaudeConfig (Object top) entry =
  let servers = case KM.lookup "mcpServers" top of
        Just (Object s) -> s
        _               -> KM.empty
      servers' = KM.insert "gitllm" entry servers
      top' = KM.insert "mcpServers" (Object servers') top
  in Object top'
mergeClaudeConfig _ entry = mergeClaudeConfig (object []) entry

-- ---------------------------------------------------------------------------
-- MCP config: GitHub Copilot (VS Code)
-- ---------------------------------------------------------------------------

installCopilotMcp :: InstallOpts -> FilePath -> IO ()
installCopilotMcp opts binaryAbsPath = do
  configPath <- vscodeMcpPath
  let templatePath = optConfigDir opts </> "copilot" </> "mcp.json"

  logInfo $ "Configuring GitHub Copilot MCP:"
  logInfo $ "  config:   " ++ configPath
  logInfo $ "  template: " ++ templatePath

  unless (optDryRun opts) $ do
    entry <- readMcpTemplate templatePath binaryAbsPath
    createDirectoryIfMissing True (takeDirectory configPath)

    existing <- doesFileExist configPath
    config <- if existing
      then do
        contents <- BS.readFile configPath
        if BS.null contents
          then pure (object [])
          else case eitherDecodeStrict contents of
            Right val -> pure val
            Left _    -> do
              hPutStrLn stderr "WARNING: Could not parse existing mcp.json"
              hPutStrLn stderr "         Existing content will be replaced."
              pure (object [])
      else pure (object [])

    let updated = mergeCopilotConfig config entry
    BL.writeFile configPath (encode updated)

  success "GitHub Copilot MCP configured"

-- | Merge a gitllm entry into VS Code mcp.json.
-- mcp.json uses { "servers": { "name": { "command": ..., "args": [...] } } }
mergeCopilotConfig :: Value -> Value -> Value
mergeCopilotConfig (Object top) entry =
  let servers = case KM.lookup "servers" top of
        Just (Object s) -> s
        _               -> KM.empty
      servers' = KM.insert "gitllm" entry servers
      top' = KM.insert "servers" (Object servers') top
  in Object top'
mergeCopilotConfig _ entry = mergeCopilotConfig (object []) entry

-- ---------------------------------------------------------------------------
-- Agent definitions: Claude
-- ---------------------------------------------------------------------------

installClaudeAgent :: InstallOpts -> IO ()
installClaudeAgent opts = do
  destDir <- claudeAgentDir
  let srcDir = optConfigDir opts </> "claude"
      agentFiles = [ "gitllm.md"
                     , "gitllm-status.md"
                     , "gitllm-history.md"
                     , "gitllm-search.md"
                     , "gitllm-branch.md"
                     , "gitllm-staging.md"
                     , "gitllm-merge.md"
                     , "gitllm-remote.md"
                     , "gitllm-stash.md"
                     , "gitllm-maintenance.md"
                     ]

  logInfo "Installing Claude agent instructions:"

  unless (optDryRun opts) $
    createDirectoryIfMissing True destDir

  mapM_ (\f -> do
    let srcPath  = srcDir </> f
        destPath = destDir </> f
    logInfo $ "  " ++ srcPath ++ " -> " ++ destPath
    srcExists <- doesFileExist srcPath
    if srcExists
      then unless (optDryRun opts) $ copyFile srcPath destPath
      else hPutStrLn stderr $ "  WARNING: not found: " ++ srcPath
    ) agentFiles

  success "Claude agent instructions installed"

-- ---------------------------------------------------------------------------
-- Agent definitions: GitHub Copilot (VS Code)
-- ---------------------------------------------------------------------------

installCopilotAgent :: InstallOpts -> IO ()
installCopilotAgent opts = do
  destDir <- vscodePromptsDir
  let srcDir = optConfigDir opts </> "copilot"
      agentFiles = [ "gitllm.agent.md"
                     , "gitllm-status.agent.md"
                     , "gitllm-history.agent.md"
                     , "gitllm-search.agent.md"
                     , "gitllm-branch.agent.md"
                     , "gitllm-staging.agent.md"
                     , "gitllm-merge.agent.md"
                     , "gitllm-remote.agent.md"
                     , "gitllm-stash.agent.md"
                     , "gitllm-maintenance.agent.md"
                     ]

  logInfo "Installing Copilot agent definitions:"

  unless (optDryRun opts) $
    createDirectoryIfMissing True destDir

  mapM_ (\f -> do
    let srcPath  = srcDir </> f
        destPath = destDir </> f
    logInfo $ "  " ++ srcPath ++ " -> " ++ destPath
    srcExists <- doesFileExist srcPath
    if srcExists
      then unless (optDryRun opts) $ copyFile srcPath destPath
      else hPutStrLn stderr $ "  WARNING: not found: " ++ srcPath
    ) agentFiles

  success "Copilot agent definitions installed"

-- ---------------------------------------------------------------------------
-- Workspace-level installation
-- ---------------------------------------------------------------------------

-- | Install gitllm MCP config into a VS Code workspace.
-- Writes .vscode/mcp.json with the server entry.
installWorkspaceMcp :: InstallOpts -> FilePath -> FilePath -> IO ()
installWorkspaceMcp opts wsDir binaryAbsPath = do
  let configPath = wsDir </> ".vscode" </> "mcp.json"
      templatePath = optConfigDir opts </> "copilot" </> "mcp.json"

  logInfo "Configuring workspace MCP:"
  logInfo $ "  config:   " ++ configPath
  logInfo $ "  template: " ++ templatePath

  unless (optDryRun opts) $ do
    entry <- readMcpTemplate templatePath binaryAbsPath
    createDirectoryIfMissing True (wsDir </> ".vscode")

    existing <- doesFileExist configPath
    config <- if existing
      then do
        contents <- BS.readFile configPath
        if BS.null contents
          then pure (object [])
          else case eitherDecodeStrict contents of
            Right val -> pure val
            Left _    -> do
              hPutStrLn stderr "WARNING: Could not parse existing .vscode/mcp.json"
              hPutStrLn stderr "         Existing content will be replaced."
              pure (object [])
      else pure (object [])

    let updated = mergeCopilotConfig config entry
    BL.writeFile configPath (encode updated)

  success "Workspace MCP configured"

-- | Install Copilot prompt files into the workspace.
-- Writes to .github/copilot/ in the workspace.
installWorkspacePrompts :: InstallOpts -> FilePath -> IO ()
installWorkspacePrompts opts wsDir = do
  let destDir = wsDir </> ".github" </> "copilot"
      srcDir  = optConfigDir opts </> "copilot"
      promptFiles = [ "gitllm.agent.md"
                    , "gitllm-status.agent.md"
                    , "gitllm-history.agent.md"
                    , "gitllm-search.agent.md"
                    , "gitllm-branch.agent.md"
                    , "gitllm-staging.agent.md"
                    , "gitllm-merge.agent.md"
                    , "gitllm-remote.agent.md"
                    , "gitllm-stash.agent.md"
                    , "gitllm-maintenance.agent.md"
                    ]

  logInfo "Installing workspace prompt files:"

  unless (optDryRun opts) $
    createDirectoryIfMissing True destDir

  mapM_ (\f -> do
    let srcPath  = srcDir </> f
        destPath = destDir </> f
    logInfo $ "  " ++ srcPath ++ " -> " ++ destPath
    srcExists <- doesFileExist srcPath
    if srcExists
      then unless (optDryRun opts) $ copyFile srcPath destPath
      else hPutStrLn stderr $ "  WARNING: not found: " ++ srcPath
    ) promptFiles

  success "Workspace prompt files installed"

-- | Remove gitllm MCP config from a workspace.
uninstallWorkspaceMcp :: InstallOpts -> FilePath -> IO ()
uninstallWorkspaceMcp opts wsDir = do
  let configPath = wsDir </> ".vscode" </> "mcp.json"
  logInfo $ "Removing gitllm from workspace MCP config: " ++ configPath
  removeJsonKey opts configPath "servers" "gitllm"
  success "Workspace MCP entry removed"

-- | Remove Copilot prompt files from a workspace.
uninstallWorkspacePrompts :: InstallOpts -> FilePath -> IO ()
uninstallWorkspacePrompts opts wsDir = do
  let destDir = wsDir </> ".github" </> "copilot"
      files = [ "gitllm.agent.md"
              , "gitllm-status.agent.md"
              , "gitllm-history.agent.md"
              , "gitllm-search.agent.md"
              , "gitllm-branch.agent.md"
              , "gitllm-staging.agent.md"
              , "gitllm-merge.agent.md"
              , "gitllm-remote.agent.md"
              , "gitllm-stash.agent.md"
              , "gitllm-maintenance.agent.md"
              ]
  logInfo "Removing workspace prompt files:"
  mapM_ (removeIfExists opts destDir) files
  success "Workspace prompt files removed"

-- ---------------------------------------------------------------------------
-- Uninstall
-- ---------------------------------------------------------------------------

-- | Remove the gitllm binary from the install directory.
uninstallBinary :: InstallOpts -> FilePath -> IO ()
uninstallBinary opts binDir = do
  let destPath = binDir </> binaryName
  exists <- doesFileExist destPath
  if exists
    then do
      logInfo $ "Removing binary: " ++ destPath
      unless (optDryRun opts) $ removeFile destPath
      success "Binary removed"
    else logInfo $ "Binary not found at " ++ destPath ++ " (skipping)"

-- | Remove the gitllm entry from Claude's MCP config.
uninstallClaudeMcp :: InstallOpts -> IO ()
uninstallClaudeMcp opts = do
  configPath <- claudeConfigPath
  logInfo $ "Removing gitllm from Claude MCP config: " ++ configPath
  removeJsonKey opts configPath "mcpServers" "gitllm"
  success "Claude MCP entry removed"

-- | Remove the gitllm entry from VS Code's mcp.json.
uninstallCopilotMcp :: InstallOpts -> IO ()
uninstallCopilotMcp opts = do
  configPath <- vscodeMcpPath
  logInfo $ "Removing gitllm from Copilot MCP config: " ++ configPath
  removeJsonKey opts configPath "servers" "gitllm"
  success "Copilot MCP entry removed"

-- | Remove a key from a nested JSON object.
-- Looks for @{ parentKey: { childKey: ... } }@ and deletes @childKey@.
removeJsonKey :: InstallOpts -> FilePath -> Key -> Key -> IO ()
removeJsonKey opts configPath parentKey childKey = do
  exists <- doesFileExist configPath
  when exists $ unless (optDryRun opts) $ do
    contents <- BS.readFile configPath
    unless (BS.null contents) $
      case eitherDecodeStrict contents of
        Right (Object top) ->
          case KM.lookup parentKey top of
            Just (Object nested) -> do
              let nested' = KM.delete childKey nested
                  top' = KM.insert parentKey (Object nested') top
              BL.writeFile configPath (encode (Object top'))
            _ -> pure ()
        _ -> pure ()

-- | Remove Claude agent instruction files.
uninstallClaudeAgent :: InstallOpts -> IO ()
uninstallClaudeAgent opts = do
  destDir <- claudeAgentDir
  let files = [ "gitllm.md"
              , "gitllm-status.md"
              , "gitllm-history.md"
              , "gitllm-search.md"
              , "gitllm-branch.md"
              , "gitllm-staging.md"
              , "gitllm-merge.md"
              , "gitllm-remote.md"
              , "gitllm-stash.md"
              , "gitllm-maintenance.md"
              , "gitllm-ops.md"
              ]
  logInfo "Removing Claude agent instructions:"
  mapM_ (removeIfExists opts destDir) files
  success "Claude agent instructions removed"

-- | Remove Copilot prompt files.
uninstallCopilotAgent :: InstallOpts -> IO ()
uninstallCopilotAgent opts = do
  destDir <- vscodePromptsDir
  let files = [ "gitllm.agent.md"
              , "gitllm-status.agent.md"
              , "gitllm-history.agent.md"
              , "gitllm-search.agent.md"
              , "gitllm-branch.agent.md"
              , "gitllm-staging.agent.md"
              , "gitllm-merge.agent.md"
              , "gitllm-remote.agent.md"
              , "gitllm-stash.agent.md"
              , "gitllm-maintenance.agent.md"
              ]
  logInfo "Removing Copilot prompt files:"
  mapM_ (removeIfExists opts destDir) files
  success "Copilot prompt files removed"

-- | Remove a file if it exists, respecting dry-run.
removeIfExists :: InstallOpts -> FilePath -> FilePath -> IO ()
removeIfExists opts dir fileName = do
  let path = dir </> fileName
  exists <- doesFileExist path
  if exists
    then do
      logInfo $ "  removing: " ++ path
      unless (optDryRun opts) $ removeFile path
    else logInfo $ "  not found: " ++ path ++ " (skipping)"

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  opts <- execParser optsInfo
  let binDir = fromMaybe "" (optBinaryPath opts)

  actualBinDir <- if null binDir
    then defaultBinDir
    else pure binDir

  let binaryAbsPath = actualBinDir </> binaryName

  header' "gitllm installer"
  logInfo $ "Platform:    " ++ show currentPlatform
  logInfo $ "Binary:      " ++ binaryAbsPath
  logInfo $ "Config dir:  " ++ optConfigDir opts
  when (optDryRun opts) $
    logInfo "Mode:        DRY RUN (no changes will be made)"
  when (optUninstall opts) $
    logInfo "Mode:        UNINSTALL"
  case optWorkspace opts of
    Just ws -> logInfo $ "Workspace:   " ++ ws
    Nothing -> pure ()
  putStrLn ""

  case optWorkspace opts of
    Just wsDir ->
      -- Workspace mode: only touch .vscode/mcp.json and .github/copilot/
      if optUninstall opts
        then do
          putStrLn ""
          uninstallWorkspaceMcp opts wsDir
          putStrLn ""
          uninstallWorkspacePrompts opts wsDir
          putStrLn ""
          success "Workspace uninstall complete!"
        else do
          putStrLn ""
          installWorkspaceMcp opts wsDir binaryAbsPath
          putStrLn ""
          installWorkspacePrompts opts wsDir
          putStrLn ""
          success "Workspace installation complete!"
          logInfo ""
          logInfo "Next steps:"
          logInfo "  1. Open this workspace in VS Code"
          logInfo "  2. The MCP server will start automatically"
          logInfo "  3. Verify by asking your AI assistant to run 'git_status'"
          logInfo ""

    Nothing -> do
      -- Global mode: install binary + global configs
      if optUninstall opts
        then do
          unless (optConfigOnly opts) $
            uninstallBinary opts actualBinDir

          unless (optBinaryOnly opts || optNoClaudeMcp opts) $ do
            putStrLn ""
            uninstallClaudeMcp opts

          unless (optBinaryOnly opts || optNoCopilotMcp opts) $ do
            putStrLn ""
            uninstallCopilotMcp opts

          unless (optBinaryOnly opts || optNoClaudeAgent opts) $ do
            putStrLn ""
            uninstallClaudeAgent opts

          unless (optBinaryOnly opts || optNoCopilotAgent opts) $ do
            putStrLn ""
            uninstallCopilotAgent opts

          putStrLn ""
          success "Uninstall complete!"

        else do
          unless (optConfigOnly opts) $
            installBinary opts actualBinDir

          unless (optBinaryOnly opts || optNoClaudeMcp opts) $ do
            putStrLn ""
            installClaudeMcp opts binaryAbsPath

          unless (optBinaryOnly opts || optNoCopilotMcp opts) $ do
            putStrLn ""
            installCopilotMcp opts binaryAbsPath

          unless (optBinaryOnly opts || optNoClaudeAgent opts) $ do
            putStrLn ""
            installClaudeAgent opts

          unless (optBinaryOnly opts || optNoCopilotAgent opts) $ do
            putStrLn ""
            installCopilotAgent opts

          putStrLn ""
          success "Installation complete!"
          logInfo ""
          logInfo "Next steps:"
          logInfo "  1. Restart Claude Code / VS Code to pick up the new MCP server"
          logInfo "  2. Verify by asking your AI assistant to run 'git_status'"
          logInfo ""

  where
    optsInfo = info (installOptsParser <**> helper)
      ( fullDesc
     <> progDesc "Install gitllm binary and configure MCP clients"
     <> Options.Applicative.header "gitllm-install — setup gitllm on your system"
      )

-- ---------------------------------------------------------------------------
-- Output helpers
-- ---------------------------------------------------------------------------

header' :: String -> IO ()
header' msg = do
  putStrLn $ "=== " ++ msg ++ " ==="

logInfo :: String -> IO ()
logInfo msg = putStrLn $ "  " ++ msg

success :: String -> IO ()
success msg = putStrLn $ "  [OK] " ++ msg
