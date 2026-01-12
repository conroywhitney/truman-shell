# Design: Add Executor POC

## Overview

The Executor is the bridge between parsed commands and actual execution. It routes `%Command{}` structs to appropriate handlers and returns shell-like output.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    TrumanShell                          │
├─────────────────────────────────────────────────────────┤
│  parse/1          │  execute/1 (NEW)                    │
│  ↓                │  ↓                                  │
│  Parser.parse/1   │  parse/1 → Executor.run/1           │
│  ↓                │                                     │
│  %Command{}       │                                     │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│                   Executor (NEW)                         │
├─────────────────────────────────────────────────────────┤
│  run/1                                                   │
│  ├── validate_depth/1  (enforce max pipe depth)         │
│  ├── execute/1        (dispatch to handlers)               │
│  └── validate_ls_args/1 (arg validation)       │
├─────────────────────────────────────────────────────────┤
│  Handlers (pattern matched on command name)              │
│  ├── execute(%Command{name: :cmd_ls})    → list files              │
│  ├── execute(%Command{name: {:unknown}}) → "command not found"     │
│  └── handle_ls/1                    → list files          │
└─────────────────────────────────────────────────────────┘
```

## Key Decisions

### Decision 1: Executor enforces policy, not parser

**Choice**: Policy (depth limits, path restrictions) lives in Executor, not Parser.

**Rationale**:
- Parser is pure and testable — it faithfully parses any valid syntax
- Executor is the policy layer — it decides what's *allowed*
- Future: Different executors could have different policies (dev vs prod)

**Alternatives considered**:
- Parser rejects deep pipes → Couples parsing with policy
- Middleware chain → Overengineered for v0.3 POC

### Decision 2: Handlers via pattern matching

**Choice**: Use function head pattern matching for command dispatch.

```elixir
defp execute(%Command{name: :cmd_ls, args: args}), do: # ...
defp execute(%Command{name: {:unknown, name}}), do: # ...
```

**Rationale**:
- Idiomatic Elixir
- Easy to add new commands (just add a function head)
- Compile-time exhaustiveness checking

### Decision 3: Return tuples, not exceptions

**Choice**: `{:ok, output}` / `{:error, message}` for all results.

**Rationale**:
- Matches parser convention (`TrumanShell.parse/1`)
- Explicit error handling in caller
- No surprise crashes for unknown commands

### Decision 4: Shell-like output formatting

**Choice**: Output mimics real shell as closely as possible.

```elixir
# ls output looks like:
"file1.txt\nfile2.txt\ndir/\n"

# Error output looks like:
"bash: xyz: command not found\n"
```

**Rationale**:
- Agent shouldn't be able to tell it's in a sandbox
- Consistent with "Truman Show" philosophy

## Integration with IExReAct

IExReAct consumes Truman Shell as a path dependency:

```elixir
# IExReAct/mix.exs
{:truman_shell, path: "../truman-shell"}
```

Integration point (to be built in IExReAct):

```elixir
# IExReAct could wrap Truman Shell like:
defmodule IExReAct.ShellTool do
  def run(command_string) do
    case TrumanShell.execute(command_string) do
      {:ok, output} -> output
      {:error, msg} -> msg
    end
  end
end
```

## Depth Limit

**Default**: 10 pipes maximum

```elixir
# Rejected:
"cat file | grep x | sort | uniq | head | tail | wc | ... (>10)"

# Allowed:
"cat file | grep pattern | head -5"
```

Configurable via options in future versions.

## Testing Strategy

1. **Unit tests**: Test `Executor.run/1` with various `%Command{}` inputs
2. **Integration tests**: Test `TrumanShell.execute/1` end-to-end
3. **Doctests**: Document public API behavior
4. **TDD**: Write failing tests first, then implement

## Future Considerations

- **v0.4**: Add more handlers (cat, head, tail, pwd, cd)
- **v0.7**: Pipe execution (output of one → input of next)
- **v0.8**: Path sandboxing with 404 principle
- **v0.9**: WASM for script execution
