# Agent Mediation Layer

> TrumanShell as a Universal Agent Sandbox

## The Discovery (2026-01-24)

Claude Code's `PreToolUse` hooks support `updatedInput` - you can **rewrite tool parameters** before execution. This means TrumanShell can transparently proxy ALL agent operations.

```
Agent: Bash("rm -rf /")
    ↓ PreToolUse Hook
    ↓ updatedInput.command = "truman-shell execute 'rm -rf /'"
    ↓
TrumanShell: "rm: /: No such file or directory"
```

**The agent doesn't know it's being proxied.**

## Current State: Bash Hooked

```json
// .claude/settings.json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/truman-proxy-experiment.sh"
      }]
    }]
  }
}
```

### What Works Now

| Test | Result |
|------|--------|
| `ls` | ✅ Shows sandbox contents |
| `ls /etc` | ❌ "No such file or directory" |
| `cat /etc/passwd` | ❌ "No such file or directory" |
| `ls ../` | ❌ Path traversal blocked |
| `rm -rf /` | ❌ "No such file or directory" |
| `whoami` | ❌ "command not found" (not whitelisted) |
| `git status` | ❌ "command not found" (not whitelisted) |
| `echo $HOME` | Returns literal `$HOME` (no expansion) |
| `cat ~/.ssh/id_rsa` | Tries sandbox/.ssh (tilde rewritten) |
| `touch file && cat file` | ✅ File ops work in sandbox |
| `rm file` | ✅ Moves to .trash (reversible) |
| `which ls` | "ls: TrumanShell builtin" |

### The Escape Hatch

**Problem**: Other tools bypass the sandbox!

```
# This is blocked (goes through TrumanShell):
Bash("cat /etc/passwd")  → "No such file or directory"

# This works (raw tool access):
Read("/etc/passwd")  → [full file contents]
```

## Tool-by-Tool Mediation Plan

### Claude Code Tools

| Tool | Category | Current | Mediation Strategy |
|------|----------|---------|-------------------|
| `Bash` | Execute | ✅ Hooked | Route through TrumanShell |
| `Read` | File | ❌ Raw | Validate path, return 404 or content |
| `Write` | File | ❌ Raw | Validate path, enforce sandbox |
| `Edit` | File | ❌ Raw | Validate path, enforce sandbox |
| `Glob` | Search | ❌ Raw | Filter results to whitelisted paths |
| `Grep` | Search | ❌ Raw | Only search whitelisted paths |
| `NotebookEdit` | File | ❌ Raw | Validate notebook path |
| `WebFetch` | Web | ❌ Raw | URL allowlist? |
| `WebSearch` | Web | ❌ Raw | Query filtering? |
| `Task` | Agent | ❌ Raw | Subagent inherits sandbox? |

### Hook Implementation Pattern

```typescript
// Generic PreToolUse handler pattern
interface PreToolUseInput {
  tool_name: string;
  tool_input: Record<string, unknown>;
}

interface HookOutput {
  hookSpecificOutput: {
    hookEventName: 'PreToolUse';
    permissionDecision: 'allow' | 'deny';
    permissionDecisionReason?: string;
    updatedInput?: Record<string, unknown>;
  };
}

// For Read tool:
if (input.tool_name === 'Read') {
  const path = input.tool_input.file_path;
  if (!isInSandbox(path)) {
    return {
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'deny',
        permissionDecisionReason: `File not found: ${path}`
      }
    };
  }
}
```

### Priority Order

1. **Read** - Most obvious escape (demonstrated with /etc/passwd)
2. **Write** - Could write outside sandbox
3. **Edit** - Could edit outside sandbox
4. **Glob** - Could discover files outside sandbox
5. **Grep** - Could search outside sandbox
6. **WebFetch** - Lower priority (network vs filesystem)
7. **Task** - Complex (subagent sandboxing)

## Configuration

### TRUMAN_DOME Environment Variable

Set `TRUMAN_DOME` to configure the sandbox root:

```bash
export TRUMAN_DOME=~/code/my-project
```

**Features:**
- `~` expands to `$HOME`
- `.` and `./path` expand relative to cwd
- Trailing slashes normalized
- Does NOT expand `$VAR` (security)

**Without env var:** Falls back to `File.cwd!()`

### Hook Integration

```typescript
// In hook:
const dome = process.env.CLAUDE_PROJECT_DIR;
const wrappedCommand = `TRUMAN_DOME='${dome}' ~/code/truman-shell/bin/truman-shell execute '${escapedCmd}'`;
```

"You're not leaving the dome, Truman."

## The Agent Landscape

TrumanShell currently hooks Claude Code. But there are many agents:

| Product | Company | Type | Hookable? |
|---------|---------|------|-----------|
| Claude Code | Anthropic | CLI | ✅ PreToolUse hooks |
| Gemini CLI | Google | CLI | ? |
| Codex CLI | OpenAI | CLI | ? |
| Cursor | Cursor | IDE | ? |
| Windsurf | Codeium | IDE | ? |
| Goose | Block | CLI (OSS) | Likely |
| aider | Community | CLI (OSS) | Likely |

### Agent Client Protocol (ACP)

[agentclientprotocol.com](https://agentclientprotocol.com) - Zed + JetBrains standard for agent ↔ editor communication.

#### ACP Terminal Protocol

Five core methods TrumanShell would implement:

```typescript
interface ACPTerminal {
  'terminal/create'(params: {
    command: string,      // ← TrumanShell validates against whitelist
    args?: string[],      // ← TrumanShell validates paths
    env?: Record<string, string>,  // ← TrumanShell filters
    cwd?: string,         // ← TrumanShell enforces sandbox
    outputByteLimit?: number
  }): { terminalId: string }

  'terminal/output'(terminalId: string): { output: string }
  'terminal/wait_for_exit'(terminalId: string): { exitCode: number }
  'terminal/kill'(terminalId: string): void
  'terminal/release'(terminalId: string): void
}
```

#### Reference Implementation

`RAIT-09/obsidian-agent-client` - Obsidian plugin that:
- Implements ACP client
- `vault.adapter.ts` mediates filesystem access
- Supports Claude Code, Gemini CLI, Codex CLI
- Pattern: Interface → Validation → Normalization

If TrumanShell implements ACP:
- Becomes a **universal agent sandbox**
- Any ACP-compatible agent works (Claude, Gemini, Codex, Goose)
- Standardized terminal/file operations
- See: [ACP Terminals Spec](https://agentclientprotocol.com/protocol/terminals)

## Vision: Universal Agent Sandbox

```
┌─────────────────────────────────────────────────────────────┐
│                    TrumanShell TUI                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ Agent Chat   │  │ Command Log  │  │ Artifacts        │  │
│  │              │  │              │  │ (files created)  │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
              │                    │
              │   ACP Protocol     │   PreToolUse Hooks
              │                    │
    ┌─────────┴─────────┐    ┌────┴────┐
    │ Any ACP Agent     │    │ Claude  │
    │ (Gemini, Codex,   │    │ Code    │
    │  Goose, etc.)     │    │         │
    └───────────────────┘    └─────────┘
              │                    │
              └────────┬───────────┘
                       │
              ┌────────┴────────┐
              │  TrumanShell    │
              │  Mediation      │
              │  Layer          │
              └────────┬────────┘
                       │
              ┌────────┴────────┐
              │  Real           │
              │  Filesystem     │
              └─────────────────┘
```

Every agent operation flows through TrumanShell:
- Commands validated against whitelist
- Paths checked against sandbox boundaries
- Destructive ops made reversible
- Everything logged and observable

**The agent lives in a convincing simulation. We control what it sees, what it can do, and what "reality" looks like.**

## Files

- Hook: `.claude/hooks/truman-proxy-experiment.{sh,ts}`
- Config: `.claude/settings.json`
- Core: `lib/truman_shell.ex`
- CLI: `bin/truman-shell`

## References

- [PreToolUse Discovery Memory](/.claude/memories/project/2026-01-24_trumanshell-pretooluse-proxy-discovery.discovery.md)
- [Hook Architecture Doc](/.imaginary/ideas/2026-01-24_0115_trumanshell-hook-proxy-pattern.architecture.md)
- [TUI Vision](/.imaginary/ideas/2026-01-24_0045_unified-canvas-chat-shell-artifacts.vision.md)
- [ACP Research](/.imaginary/ideas/2026-01-24_0100_agent-client-protocol.research.md)

---

*"We accept the reality of the world with which we are presented." — The Truman Show*
