{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import GitLLM.MCP.Server (runServer)
import GitLLM.MCP.Types (ServerConfig(..))
import Options.Applicative

data Opts = Opts
  { optRepoPath :: Maybe FilePath
  , optTransport :: Transport
  }

data Transport = StdioTransport | TcpTransport Int

optsParser :: Parser Opts
optsParser = Opts
  <$> optional (strOption
        ( long "repo"
       <> short 'r'
       <> metavar "PATH"
       <> help "Path to the git repository (defaults to current directory)"
        ))
  <*> transportParser

transportParser :: Parser Transport
transportParser = tcpParser <|> pure StdioTransport
  where
    tcpParser = TcpTransport <$> option auto
      ( long "port"
     <> short 'p'
     <> metavar "PORT"
     <> help "Run as TCP server on the given port (default: stdio)"
      )

main :: IO ()
main = do
  opts <- execParser optsInfo
  let cfg = ServerConfig
        { cfgRepoPath  = optRepoPath opts
        , cfgTransport = case optTransport opts of
            StdioTransport  -> "stdio"
            TcpTransport p  -> "tcp:" <> show p
        , cfgServerName = "gitllm"
        , cfgVersion    = "0.1.0.0"
        }
  runServer cfg
  where
    optsInfo = info (optsParser <**> helper)
      ( fullDesc
     <> progDesc "MCP server exposing granular git operations for LLM tooling"
     <> header "gitllm — a Model Context Protocol server for git"
      )
