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
import qualified Data.Aeson.Key as Key
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
import System.Exit (exitFailure)
import System.FilePath ((</>), takeDirectory)
import System.Info (os)
import System.IO (hPutStrLn, stderr)

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

-- | VS Code settings.json location (user-level).
vscodeSettingsPath :: IO FilePath
vscodeSettingsPath = case currentPlatform of
  Windows -> do
    appData <- getEnv' "APPDATA"
    pure (appData </> "Code" </> "User" </> "settings.json")
  MacOS -> do
    home <- getHomeDirectory
    pure (home </> "Library" </> "Application Support" </> "Code" </> "User" </> "settings.json")
  _ -> do
    home <- getHomeDirectory
    pure (home </> ".config" </> "Code" </> "User" </> "settings.json")

-- | Claude agent instructions install directory.
claudeAgentDir :: IO FilePath
claudeAgentDir = do
  home <- getHomeDirectory
  pure (home </> ".claude" </> "commands")

-- | VS Code user-level agents directory.
vscodeAgentsDir :: IO FilePath
vscodeAgentsDir = case currentPlatform of
  Windows -> do
    appData <- getEnv' "APPDATA"
    pure (appData </> "Code" </> "User" </> "agents")
  MacOS -> do
    home <- getHomeDirectory
    pure (home </> "Library" </> "Application Support" </> "Code" </> "User" </> "agents")
  _ -> do
    home <- getHomeDirectory
    pure (home </> ".config" </> "Code" </> "User" </> "agents")

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
findStackBinary :: IO (Maybe FilePath)
findStackBinary = do
  -- Stack installs to .stack-work/install/.../bin/
  -- We can also check the Stack local bin path
  home <- getHomeDirectory
  let candidates = case currentPlatform of
        Windows ->
          [ home </> "AppData" </> "Roaming" </> "local" </> "bin" </> binaryName
          , home </> ".local" </> "bin" </> binaryName
          ]
        _ ->
          [ home </> ".local" </> "bin" </> binaryName
          ]
  findFirst candidates
  where
    findFirst [] = pure Nothing
    findFirst (p:ps) = do
      exists <- doesFileExist p
      if exists then pure (Just p) else findFirst ps

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
        case eitherDecodeStrict contents of
          Right val -> pure val
          Left _    -> pure (object [])
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
  configPath <- vscodeSettingsPath
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
        case eitherDecodeStrict contents of
          Right val -> pure val
          Left _    -> do
            -- Don't overwrite a file we can't parse — it may have comments
            hPutStrLn stderr "WARNING: Could not parse existing settings.json"
            hPutStrLn stderr "         Skipping Copilot config. Add manually:"
            hPutStrLn stderr $ "         \"github.copilot.chat.mcpServers\": { \"gitllm\": { \"command\": \"" ++ binaryAbsPath ++ "\" } }"
            pure Null
      else pure (object [])

    case config of
      Null -> pure ()
      _    -> do
        let updated = mergeCopilotConfig config entry
        BL.writeFile configPath (encode updated)

  success "GitHub Copilot MCP configured"

-- | Merge a gitllm entry into VS Code settings for Copilot.
mergeCopilotConfig :: Value -> Value -> Value
mergeCopilotConfig (Object top) entry =
  let key = "github.copilot.chat.mcpServers"
      servers = case KM.lookup (Key.fromText key) top of
        Just (Object s) -> s
        _               -> KM.empty
      servers' = KM.insert "gitllm" entry servers
      top' = KM.insert (Key.fromText key) (Object servers') top
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
  destDir <- vscodeAgentsDir
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
  putStrLn ""

  -- Step 1: Install binary
  unless (optConfigOnly opts) $
    installBinary opts actualBinDir

  -- Step 2: Configure Claude Code MCP
  unless (optBinaryOnly opts || optNoClaudeMcp opts) $ do
    putStrLn ""
    installClaudeMcp opts binaryAbsPath

  -- Step 3: Configure GitHub Copilot MCP
  unless (optBinaryOnly opts || optNoCopilotMcp opts) $ do
    putStrLn ""
    installCopilotMcp opts binaryAbsPath

  -- Step 4: Install Claude agent instructions
  unless (optBinaryOnly opts || optNoClaudeAgent opts) $ do
    putStrLn ""
    installClaudeAgent opts

  -- Step 5: Install Copilot agent definition
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
