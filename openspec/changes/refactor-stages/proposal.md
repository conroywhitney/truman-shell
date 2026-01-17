# Proposal: Refactor Pipeline Stages

## Why

The codebase has grown organically and now violates separation of concerns:
- `executor.ex` handles both execution AND redirects (too much responsibility)
- `commands/cd.ex` has tilde expansion inline (should be a pipeline stage)
- `commands/file_io.ex` and `commands/tree_walker.ex` don't implement `Behaviour` (wrong location)
- No clear pipeline architecture matching POSIX shell processing model

This refactor establishes clean pipeline stages before adding glob expansion (v0.6).

## What Changes

### Directory Structure

```
lib/truman_shell/
├── stages/                    # Pipeline stages
│   ├── tokenizer.ex          # moved from top-level
│   ├── parser.ex             # moved from top-level
│   ├── expander.ex           # NEW - tilde expansion (glob added in v0.6)
│   ├── executor.ex           # moved, slimmed down
│   └── redirector.ex         # extracted from executor
├── support/                   # Shared resources
│   ├── file_io.ex            # moved from commands/
│   ├── tree_walker.ex        # moved from commands/
│   └── sanitizer.ex          # moved from top-level
├── commands/                  # Only Behaviour implementations
│   ├── behaviour.ex
│   ├── cd.ex                 # tilde logic removed (expander handles it)
│   └── ...
└── truman_shell.ex           # Main API (delegates to stages)
```

### Pipeline Flow

```
Input → Tokenizer → Parser → Expander → Executor → Redirector → Output
```

## Capabilities

### New Capabilities

- `expander`: New stage for shell expansions (tilde now, glob later)
- `redirector`: Extracted redirect handling from executor

### Modified Capabilities

- `executor`: Remove redirect handling (moved to Redirector), remove tilde expansion (moved to Expander)

## Impact

**Code moves (no logic changes):**
- `tokenizer.ex` → `stages/tokenizer.ex`
- `parser.ex` → `stages/parser.ex`
- `executor.ex` → `stages/executor.ex`
- `sanitizer.ex` → `support/sanitizer.ex`
- `commands/file_io.ex` → `support/file_io.ex`
- `commands/tree_walker.ex` → `support/tree_walker.ex`

**Code extractions:**
- Redirect logic from `executor.ex` → `stages/redirector.ex`
- Tilde expansion from `commands/cd.ex` → `stages/expander.ex`

**Test impact:**
- All existing tests must continue passing
- New tests for Expander and Redirector stages
- Update imports/aliases throughout

## TDD Phases

1. **Move support modules** - file_io, tree_walker, sanitizer → `support/`
2. **Move stages** - tokenizer, parser, executor → `stages/`
3. **Extract Redirector** - redirect logic from executor → `stages/redirector.ex`
4. **Create Expander** - tilde expansion from cd.ex → `stages/expander.ex`
5. **Wire pipeline** - update `truman_shell.ex` to use full pipeline
