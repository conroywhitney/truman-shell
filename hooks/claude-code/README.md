# TrumanShell Claude Code Hooks

Sandbox Claude Code with TrumanShell. Intercepts **all** file-access tools (Read, Write, Edit, Glob, Grep) and Bash commands, validating them against the sandbox boundary.

## What It Does

| Tool | Behavior |
|------|----------|
| **Bash** | Rewrites command to route through `truman-shell execute` |
| **Read** | Validates `file_path` against sandbox; denies if outside |
| **Write** | Validates `file_path` against sandbox; denies if outside |
| **Edit** | Validates `file_path` against sandbox; denies if outside |
| **Glob** | Validates `path` against sandbox; allows if `path` not provided |
| **Grep** | Validates `path` against sandbox; allows if `path` not provided |
| **Other** | Passes through unchanged |

Denied paths return "No such file or directory" (the agent doesn't know it's sandboxed).

## Setup

### 1. Build the escript (recommended for performance)

```bash
cd /path/to/truman-shell
mix escript.build
```

This creates `dist/truman-shell` — a compiled binary with fast startup (~50ms vs ~2s for `mix run`). The hook automatically prefers the escript if it exists.

### 2. Add hooks to your project

Copy this into your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/truman-shell/hooks/claude-code/truman-sandbox.sh"
          }
        ]
      }
    ]
  }
}
```

Replace `/path/to/truman-shell` with the actual path to your TrumanShell checkout.

### 3. Set the sandbox boundary

```bash
export TRUMAN_DOME=~/code/my-project
```

If `TRUMAN_DOME` is not set, it falls back to `CLAUDE_PROJECT_DIR` (the project where Claude Code is running), then to the current working directory.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TRUMAN_DOME` | Sandbox root directory | `CLAUDE_PROJECT_DIR` or cwd |
| `TRUMAN_SHELL_PATH` | Path to truman-shell binary | Set by `truman-sandbox.sh` |

## How It Works

1. Claude Code fires a `PreToolUse` hook before each tool call
2. The hook reads the tool name and input from stdin (JSON)
3. For file/search tools, it extracts the path and calls `truman-shell validate-path`
4. `validate-path` uses TrumanShell's `Sandbox.validate_path/3` — the same battle-tested validation with ~400 tests covering symlink traversal, path normalization, `$VAR` injection, and more
5. If valid: the tool is allowed with the resolved absolute path
6. If invalid: the tool is denied with "No such file or directory"
7. For Bash: the command is rewritten to run through `truman-shell execute`

## Security

- **Fail closed**: If the hook encounters an error, it denies the tool call (not fail-open)
- **404 principle**: Denied paths appear as "not found" rather than "permission denied" — the agent doesn't learn about the sandbox boundary
- **Path resolution**: Symlinks, `../` traversal, tilde expansion, and `$VAR` injection are all handled by the Elixir sandbox module

## Testing

```bash
# Deny: Read /etc/passwd
echo '{"session_id":"test","cwd":"/tmp","tool_name":"Read","tool_input":{"file_path":"/etc/passwd"}}' \
  | TRUMAN_DOME=/tmp hooks/claude-code/truman-sandbox.sh

# Allow: Read file inside sandbox
echo '{"session_id":"test","cwd":"/tmp","tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}' \
  | TRUMAN_DOME=/tmp hooks/claude-code/truman-sandbox.sh

# Allow: Grep without path (searches cwd)
echo '{"session_id":"test","cwd":"/tmp","tool_name":"Grep","tool_input":{"pattern":"hello"}}' \
  | TRUMAN_DOME=/tmp hooks/claude-code/truman-sandbox.sh
```

## Files

```
hooks/claude-code/
  truman-sandbox.ts       # PreToolUse hook (TypeScript)
  truman-sandbox.sh       # Shell wrapper (resolves binary path)
  settings-snippet.json   # Copy-paste for .claude/settings.json
  README.md               # This file
```
