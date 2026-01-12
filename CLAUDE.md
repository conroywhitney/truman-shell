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
| v0.2 | ✅ Done | Minimal parser (tokenizer + parser + 84 tests) |
| v0.3 | 🎯 Next | Proof of concept loop (integrate with agent, implement `ls`) |
| v0.4 | Planned | Read operations (ls, cat, head, tail, pwd, cd) |
| v0.5 | Planned | Search operations (grep, find, wc) |
| v0.6 | Planned | Write operations (mkdir, touch, rm, mv, cp, echo) |
| v0.7 | Planned | Piping & composition |
| v0.8 | Planned | Safety (404 principle, permissions) |
| v0.9 | Planned | WASM script sandboxing |

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
mix test              # Run 110 tests (88 unit + 22 doctests)
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
- **Unit tests** (88): Derived from real Claude Code session analysis (CSV fixtures)
- **Doctests** (22): Executable documentation for public API
- **Total**: 110 tests

## Design Decisions

### Pipes are flat lists (not nested)
`cmd1 | cmd2 | cmd3` becomes:
```elixir
%Command{name: :cmd1, pipes: [%Command{name: :cmd2}, %Command{name: :cmd3}]}
```
Memory grows O(n), parser uses iterative functions (no stack overflow risk).

### Depth limits belong in executor, not parser
Parser faithfully parses any valid syntax. Executor enforces:
- Max pipe depth (e.g., 10)
- Max command length
- Allowed paths

## For v0.3: Use /openspec:proposal

When starting v0.3, use the OpenSpec workflow to capture requirements before implementation.
