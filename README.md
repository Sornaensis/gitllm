# gitllm

MCP server exposing 98 git tools for LLM agents over JSON-RPC 2.0 stdio.
Works with Claude Code, GitHub Copilot, and any MCP client.

## Install

```bash
stack build
stack run -- gitllm-install
```

This installs the binary and MCP configs for both Claude Code and Copilot.

```bash
stack run -- gitllm-install --binary-only   # binary only
stack run -- gitllm-install --config-only   # configs only
```

| Platform | Binary path |
|----------|-------------|
| Linux/macOS | `~/.local/bin/gitllm` |
| Windows | `%APPDATA%\gitllm\bin\gitllm.exe` |

### Manual MCP config

**Claude Code** (`~/.claude/claude_desktop_config.json`):
```json
{ "mcpServers": { "gitllm": { "command": "gitllm", "args": [] } } }
```

**GitHub Copilot** (VS Code `settings.json`):
```json
{ "github.copilot.chat.mcpServers": { "gitllm": { "command": "gitllm", "args": [] } } }
```

## License

MIT
