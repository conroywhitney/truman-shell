<!-- OPENSPEC:START -->
# OpenSpec Instructions

These instructions are for AI assistants working in this project.

Always open `@/openspec/AGENTS.md` when the request:
- Mentions planning or proposals (words like proposal, spec, change, plan)
- Introduces new capabilities, breaking changes, architecture shifts, or big performance/security work
- Sounds ambiguous and you need the authoritative spec before coding

Use `@/openspec/AGENTS.md` to learn:
- How to create and apply change proposals
- Spec format and conventions
- Project structure and guidelines

Keep this managed block so 'openspec update' can refresh the instructions.

<!-- OPENSPEC:END -->

# Truman Shell - Claude Context

> "We accept the reality of the world with which we are presented." — The Truman Show

## What Is This?

A simulated shell environment for AI agents. The agent believes it's operating on a real filesystem, but all operations are mediated, reversible, and sandboxed.

## Key Concepts

### The 404 Principle
Protected paths return "No such file or directory" NOT "Permission denied" — prevents probing attacks.

### Core Insight
**Helpful agents are more dangerous than malicious ones.** Claude escaped ClaudeBox by wanting to run Elixir — not by being adversarial.

## Architecture

```
Agent sends: "grep -r TODO . | head -5"
                    │
                    ▼
         ┌─────────────────────┐
         │   Plug.Logger       │ → log command
         ├─────────────────────┤
         │   Plug.Sanitizer    │ → normalize, detect injection
         ├─────────────────────┤
         │   Plug.Permissions  │ → check paths allowed
         ├─────────────────────┤
         │   Plug.Filesystem   │ → route to handler
         ├─────────────────────┤
         │   Plug.Responder    │ → format like real shell
         └─────────────────────┘
```

## Roadmap

| Version | Status | Description |
|---------|--------|-------------|
| v0.1 | ✅ Done | Pattern mining (3,330 commands from Claude sessions) |
| v0.2 | ✅ Merged | Minimal parser (tokenizer + parser + 120 tests) — PR #1 merged 2026-01-12 |
| v0.3 | 🎯 Active | Proof of concept loop (integrate with IExReAct, implement `ls` executor) |
| v0.4 | Planned | Read operations (ls, cat, head, tail, pwd, cd) |
| v0.5 | Planned | Search operations (grep, find, wc) |
| v0.6 | Planned | Write operations (mkdir, touch, rm, mv, cp, echo) |
| v0.7 | Planned | Piping & composition |
| v0.8 | Planned | Safety (404 principle, permissions) |
| v0.9 | Planned | WASM script sandboxing |

## Related Projects

- **IExReAct** (`../IExReAct`) — The agent loop that will consume Truman Shell
  - Added as path dep: `{:truman_shell, path: "../truman-shell"}`

## Key Files

```
lib/truman_shell.ex           # Public API: TrumanShell.parse/1
lib/truman_shell/command.ex   # %Command{name, args, pipes, redirects}
lib/truman_shell/tokenizer.ex # String → tokens
lib/truman_shell/parser.ex    # Tokens → %Command{}
```

## Research Location

Pattern mining research, TDD fixtures, and ideation documents live in:
`/Users/conroywhitney/code/reification-labs/.imaginary/`

Key files:
- `.imaginary/research/2026-01-11_shell-patterns.md` - Command frequency analysis
- `.imaginary/research/2026-01-11_shell-errors.md` - Error message formats
- `.imaginary/research/2026-01-11_shell-tdd-fixtures.csv` - 140 TDD test cases
- `.imaginary/ideas/2026-01-11_1745_truman-shell-roadmap.thought.md` - Full roadmap

## Commands

```bash
mix test              # Run 120 tests (96 unit + 24 doctests)
mix deps.get          # Fetch dependencies
mix format            # Format code
```

## Testing Philosophy

### Doctests = Living Documentation
Doctests serve dual purposes:
1. **Documentation** — Users see real, working examples in the docs
2. **Regression tests** — If the API changes, doctests fail immediately

### Test Private Functions Through Public API
- Elixir culture: if it's private (`defp`), it's an implementation detail
- If a private function needs its own tests, it should be its own module
- The CSV fixtures test private functions through `TrumanShell.parse/1`

### Test Coverage
- **Unit tests** (96): Derived from real Claude Code session analysis (CSV fixtures)
- **Doctests** (24): Executable documentation for public API
- **Total**: 120 tests

## Design Decisions

### Command names use `cmd_` prefix
All command atoms use a `cmd_` prefix for namespace clarity:
```elixir
%Command{name: :cmd_ls, args: ["-la"]}
%Command{name: :cmd_grep, args: ["pattern", "file.txt"]}
```

**Why?** Three reasons:
1. **Atom DoS prevention** - Only allowlisted atoms are created (no `String.to_atom/1` on untrusted input)
2. **Falsy footgun prevention** - `:cmd_true`/`:cmd_false` aren't falsy like `true`/`false`
3. **Namespace clarity** - `:cmd_type` is unambiguous (`:type` is overloaded in Elixir)

### Pipes are flat lists (not nested)
`cmd1 | cmd2 | cmd3` becomes:
```elixir
%Command{name: :cmd_cat, pipes: [%Command{name: :cmd_grep}, %Command{name: :cmd_head}]}
```
Memory grows O(n), parser uses iterative functions (no stack overflow risk).

### Depth limits belong in executor, not parser
Parser faithfully parses any valid syntax. Executor enforces:
- Max pipe depth (e.g., 10)
- Max command length
- Allowed paths

## Current Work: v0.3

**Goal**: One working command end-to-end: `ls`

```
Agent (IExReAct) sends: "ls -la"
      ↓
TrumanShell.parse/1 → %Command{name: :cmd_ls, args: ["-la"]}
      ↓
Executor.run/1 → Actually list files (sandboxed)
      ↓
Agent receives: "total 64\ndrwxr-xr-x  5 user..."
```

**See**: `AGENT.md` for development workflow and best practices.
