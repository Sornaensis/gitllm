# gitllm

**A Model Context Protocol (MCP) server that exposes comprehensive git operations as discrete, scoped tools for LLM agents.**

gitllm enables AI coding assistants like Claude Code and GitHub Copilot to interact
with git repositories through well-defined, type-safe tool interfaces — covering
everything from basic status queries to advanced rebase, worktree, and submodule
workflows.

## Features

- **71 git tools** across 25 categories — the most complete MCP git toolset available
- **JSON-RPC 2.0 over stdio** — standard MCP transport compatible with all major clients
- **Scoped operations** — each git operation is a discrete tool with typed parameters
- **Safe by default** — no shell expansion, local-only config writes, destructive ops require explicit flags
- **Written in Haskell** — compiled binary, no runtime dependencies beyond git

## Quick Start

### Prerequisites

- [Stack](https://docs.haskellstack.org/) (Haskell build tool)
- [Git](https://git-scm.com/) (2.25+ recommended)

### Build

```bash
stack build
```

### Run

```bash
# Serve over stdio (default)
stack run -- gitllm

# Point at a specific repository
stack run -- gitllm --repo /path/to/repo
```

### Install

The project includes a Haskell-based install script that handles binary
installation and MCP configuration for both Claude Code and GitHub Copilot:

```bash
# Build and run the installer
stack build
stack run -- gitllm-install

# Or install just the binary
stack run -- gitllm-install --binary-only

# Or generate just the MCP configs
stack run -- gitllm-install --config-only
```

See [Installation](#installation) for details on what the installer does.

## Tool Categories

| Category | Count | Tools |
|----------|-------|-------|
| **Status** | 2 | `git_status`, `git_status_short` |
| **Log** | 4 | `git_log`, `git_log_oneline`, `git_log_file`, `git_log_graph` |
| **Diff** | 4 | `git_diff`, `git_diff_staged`, `git_diff_branches`, `git_diff_stat` |
| **Branch** | 7 | `git_branch_list`, `git_branch_create`, `git_branch_delete`, `git_branch_rename`, `git_branch_current`, `git_checkout`, `git_switch` |
| **Commit** | 3 | `git_commit`, `git_commit_amend`, `git_show` |
| **Staging** | 4 | `git_add`, `git_add_all`, `git_restore`, `git_restore_staged` |
| **Remote** | 6 | `git_remote_list`, `git_remote_add`, `git_remote_remove`, `git_fetch`, `git_pull`, `git_push` |
| **Stash** | 5 | `git_stash_push`, `git_stash_pop`, `git_stash_list`, `git_stash_show`, `git_stash_drop` |
| **Tag** | 3 | `git_tag_list`, `git_tag_create`, `git_tag_delete` |
| **Merge** | 3 | `git_merge`, `git_merge_abort`, `git_merge_status` |
| **Rebase** | 4 | `git_rebase`, `git_rebase_interactive`, `git_rebase_abort`, `git_rebase_continue` |
| **Cherry-pick** | 2 | `git_cherry_pick`, `git_cherry_pick_abort` |
| **Worktree** | 3 | `git_worktree_list`, `git_worktree_add`, `git_worktree_remove` |
| **Submodule** | 4 | `git_submodule_list`, `git_submodule_add`, `git_submodule_update`, `git_submodule_sync` |
| **Config** | 3 | `git_config_get`, `git_config_set`, `git_config_list` |
| **Blame** | 1 | `git_blame` |
| **Bisect** | 4 | `git_bisect_start`, `git_bisect_good`, `git_bisect_bad`, `git_bisect_reset` |
| **Clean** | 2 | `git_clean`, `git_clean_dry_run` |
| **Reset** | 2 | `git_reset`, `git_reset_file` |
| **Reflog** | 1 | `git_reflog` |
| **Search** | 2 | `git_grep`, `git_log_search` |
| **Patch** | 2 | `git_format_patch`, `git_apply` |
| **Archive** | 1 | `git_archive` |
| **Hooks** | 1 | `git_hooks_list` |
| **Inspect** | 5 | `git_cat_file`, `git_ls_files`, `git_ls_tree`, `git_rev_parse`, `git_count_objects` |

## Installation

### What the Installer Does

#### Binary Installation

| Platform | Install Path |
|----------|-------------|
| Linux/macOS | `~/.local/bin/gitllm` |
| Windows | `%APPDATA%\gitllm\bin\gitllm.exe` |

#### MCP Configuration

**Claude Code** (`~/.claude/claude_desktop_config.json` or `%APPDATA%\Claude\claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "gitllm": {
      "command": "gitllm",
      "args": []
    }
  }
}
```

**GitHub Copilot** (VS Code `settings.json`):

```json
{
  "github.copilot.chat.mcpServers": {
    "gitllm": {
      "command": "gitllm",
      "args": []
    }
  }
}
```

### Manual Installation

```bash
# Build the optimized binary
stack build --copy-bins

# The binary is placed in ~/.local/bin/ (Stack default)
# Then configure your MCP client as shown above
```

## Configuration

```bash
# Use a specific repository (default: current directory)
gitllm --repo /path/to/repo

# Run on a TCP port instead of stdio
gitllm --port 8080
```

## Security

- **No shell expansion** — all git commands use process argument lists, preventing injection
- **Local config only** — `git_config_set` is restricted to `--local` scope
- **Explicit destructive flags** — operations like `git_clean` and `git_reset --hard` require explicit parameters
- **No credential leakage** — credentials and auth tokens are never surfaced in tool output

## Development

```bash
# Build
stack build

# Run tests
stack test

# Build with file watching
stack build --file-watch

# Open a REPL
stack ghci
```

## License

MIT
