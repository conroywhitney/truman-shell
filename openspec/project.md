# Project Context

## Purpose

Truman Shell is a simulated shell environment for AI agents. The agent believes it's operating on a real filesystem, but all operations are mediated, reversible, and sandboxed.

> "We accept the reality of the world with which we are presented." — The Truman Show

**Core insight**: Helpful agents are more dangerous than malicious ones. Claude escaped ClaudeBox by wanting to run Elixir — not by being adversarial.

## Tech Stack

- **Elixir 1.17+** / OTP 27
- **Mix** for build tooling
- No external dependencies (pure Elixir)
- **ExUnit** for testing
- **Credo** for static analysis

## Project Conventions

### Code Style

- `mix format` for all Elixir files
- Pattern matching preferred over conditionals
- Atoms use `cmd_` prefix for commands (e.g., `:cmd_ls`, `:cmd_grep`)
- Unknown commands return `{:unknown, "name"}` tuples (not atoms - prevents DoS)

### Architecture Patterns

```
Agent sends: "ls -la | head -5"
      ↓
TrumanShell.parse/1 → %Command{} struct
      ↓
Executor.run/1 → Execute in sandbox
      ↓
Responder.format/1 → Format like real shell
      ↓
Agent receives: "file1.txt\nfile2.txt\n..."
```

**Key patterns:**
- Parser is pure and faithful (no policy enforcement)
- Executor enforces policy (depth limits, allowed paths)
- Pipes stored as flat lists (O(n) memory, no stack overflow)

### Testing Strategy

- **TDD**: Red-Green-Refactor, always
- **Doctests**: Living documentation for public APIs
- **CSV fixtures**: Real commands mined from Claude Code sessions
- **Unit tests**: Test private functions through public API

### Git Workflow

- Feature branches: `feature/v0.X-description`
- Atomic commits, early and often
- Squash merge to main
- Never force-push (ask HITL if needed)
- Run `mix format && mix test && mix credo` before commit

## Domain Context

### The 404 Principle

Protected paths return "No such file or directory" NOT "Permission denied" — prevents probing attacks. The agent cannot learn what it's not allowed to see.

### Security Model

- **Atom DoS prevention**: Only allowlisted atoms created via `Command.parse_name/1`
- **Depth limits**: Enforced in executor, not parser
- **Path sanitization**: Planned for v0.8

## Important Constraints

- Must feel like real bash to the LLM
- All operations reversible (soft delete to .trash)
- No information leakage about protected resources
- Performance: Handle piped commands without stack overflow

## External Dependencies

- **IExReAct** (`../IExReAct`) — The agent loop that consumes Truman Shell
- **Jido AI** — Powers the agent (via IExReAct)

## Roadmap Reference

| Version | Status | Description |
|---------|--------|-------------|
| v0.1 | Done | Pattern mining |
| v0.2 | Merged | Minimal parser (120 tests) |
| v0.3 | Active | Proof of concept loop (executor + ls) |
| v0.4+ | Planned | Read ops, search, write, piping, safety, WASM |

See `CLAUDE.md` for full roadmap details.
