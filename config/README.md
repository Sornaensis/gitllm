# gitllm — Configuration & Definitions

This directory contains MCP server definitions and agent instructions for
each supported LLM client. The `gitllm-install` script reads these files and
installs them to the appropriate centralized locations on your system.

## Directory Layout

```
config/
  claude/
    mcp.json                  MCP server entry for Claude Code / Desktop
    gitllm.md                 Orchestrator — routes to sub-agents below
    gitllm-status.md          Status & diff overview
    gitllm-history.md         Log, show, blame, reflog
    gitllm-search.md          Grep, file listing, object inspection
    gitllm-branch.md          Branch & tag CRUD, checkout, switch
    gitllm-staging.md         Add, restore, commit
    gitllm-merge.md           Merge, rebase, cherry-pick
    gitllm-remote.md          Remote, fetch, pull, push
    gitllm-stash.md           Stash management
    gitllm-maintenance.md     Clean, reset, bisect, config, patch, etc.
  copilot/
    mcp.json                  MCP server entry for VS Code settings
    gitllm.agent.md           Orchestrator — delegates to sub-agents
    gitllm-status.agent.md    Status & diff (6 tools)
    gitllm-history.agent.md   Log, show, blame, reflog (7 tools)
    gitllm-search.agent.md    Grep, file listing, inspection (7 tools)
    gitllm-branch.agent.md    Branch & tag CRUD (10 tools)
    gitllm-staging.agent.md   Add, restore, commit (9 tools)
    gitllm-merge.agent.md     Merge, rebase, cherry-pick (16 tools)
    gitllm-remote.agent.md    Remote, fetch, pull, push (6 tools)
    gitllm-stash.agent.md     Stash management (5 tools)
    gitllm-maintenance.agent.md  Cleanup & advanced ops (22 tools)
  opencode/
    mcp.json                  MCP server entry for opencode.json
```

## Install Flags

The installer supports granular control over what gets installed:

| Flag                 | Effect                                  |
|----------------------|-----------------------------------------|
| `--no-claude-mcp`   | Skip Claude MCP server configuration    |
| `--no-claude-agent`  | Skip Claude agent instructions          |
| `--no-copilot-mcp`  | Skip Copilot MCP server configuration   |
| `--no-copilot-agent` | Skip Copilot agent definition           |
| `--no-opencode-mcp` | Skip OpenCode MCP server configuration  |
| `--no-opencode-agent` | Skip OpenCode agent installation      |
| `--binary-only`     | Skip all configuration (binary only)    |
| `--config-only`     | Skip binary installation                |
| `--dry-run`         | Preview changes without writing files   |

## Customization

Edit the files in this directory to customize what gets installed. The MCP
definition files use `{{GITLLM_PATH}}` as a placeholder that the installer
replaces with the actual binary path at install time.

For OpenCode, the installer writes a `gitllm` entry into the global
`opencode.json` `mcp` map and installs agent markdown files into the global
`agents/` directory. The OpenCode agent content currently reuses the
OpenCode-compatible manifests in `config/copilot/` and installs them with
OpenCode-style filenames such as `gitllm.md`.
