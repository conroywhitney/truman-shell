# Design: Pipeline Stages Refactor

## Context

The codebase has grown organically from v0.1 (pattern mining) through v0.5 (tilde expansion) without a clear pipeline architecture. This creates several problems:

**Current state:**
```
lib/truman_shell/
├── tokenizer.ex          # Pipeline stage (correct level)
├── parser.ex             # Pipeline stage (correct level)
├── executor.ex           # Does too much (execution + redirects)
├── sanitizer.ex          # Support utility (wrong level)
├── command.ex            # Data structure (correct level)
├── posix/errors.ex       # Support utility (correct level)
└── commands/
    ├── behaviour.ex      # Interface definition
    ├── cd.ex             # Has inline tilde expansion (wrong place)
    ├── file_io.ex        # Support utility (wrong location)
    ├── tree_walker.ex    # Support utility (wrong location)
    └── ...               # Command implementations
```

**Problems:**
1. `executor.ex` handles both command dispatch AND redirect handling (~200 lines mixing concerns)
2. `cd.ex` has tilde expansion logic that should be a pipeline stage
3. `file_io.ex` and `tree_walker.ex` don't implement `Behaviour` but live in `commands/`
4. No clear "pipeline stages" vs "shared utilities" separation
5. Adding glob expansion (v0.6) would further pollute either executor or individual commands

## Goals / Non-Goals

**Goals:**
- Establish clear pipeline architecture: `Tokenizer → Parser → Expander → Executor → Redirector`
- Separate pipeline stages from shared utilities
- Prepare clean extension point for glob expansion (v0.6)
- All 292+ existing tests continue passing
- Zero behavior changes (pure refactor)

**Non-Goals:**
- Implement glob expansion (that's v0.6)
- Add new features or fix bugs
- Change any public API signatures
- Optimize performance

## Decisions

### Decision 1: Three-tier directory structure

```
lib/truman_shell/
├── stages/       # Pipeline stages (input → output transformations)
├── support/      # Shared utilities (used by stages and commands)
└── commands/     # Only Behaviour implementations
```

**Rationale:** Mirrors POSIX shell conceptual model. Each stage has single responsibility. Support modules are explicitly non-pipeline.

**Alternatives considered:**
- Keep flat structure → Rejected: doesn't scale, glob would make it worse
- Nest stages under executor → Rejected: executor is just one stage

### Decision 2: Pipeline stage modules

| Stage | Input | Output | Responsibility |
|-------|-------|--------|----------------|
| `Stages.Tokenizer` | string | tokens | Lexical analysis |
| `Stages.Parser` | tokens | `%Command{}` | Syntactic analysis |
| `Stages.Expander` | `%Command{}` | `%Command{}` | Shell expansions (tilde, glob) |
| `Stages.Executor` | `%Command{}` | `{:ok, output}` | Command dispatch |
| `Stages.Redirector` | output + redirects | final output | I/O redirection |

**Rationale:** Each stage is a pure transformation. Expander is the extension point for glob (v0.6).

**Alternatives considered:**
- Expander as part of Parser → Rejected: parser should be syntax-only, expansions are semantic
- Per-command expansion → Rejected: violates DRY, every command would need to handle `~` and `*`

### Decision 3: Support module placement

Move to `support/`:
- `file_io.ex` - File reading with size limits (used by cat, head, tail, etc.)
- `tree_walker.ex` - Directory traversal (used by ls, find)
- `sanitizer.ex` - Path sanitization (used by all commands)

**Rationale:** These are shared utilities, not pipeline stages or commands. The `commands/` directory should only contain modules implementing `Behaviour`.

### Decision 4: Expander extracts tilde logic from cd.ex

Current `cd.ex` lines 44-49:
```elixir
def handle(["~"], context), do: go_home(context)
def handle(["~/"], context), do: go_home(context)
def handle(["~/" <> subpath], context) do
  # Expand ~/subdir to sandbox_root/subdir
```

This becomes `Stages.Expander.expand_tilde/2` which runs BEFORE executor:
```elixir
# In pipeline
command
|> Stages.Expander.expand(context)  # ~/ → sandbox_root/
|> Stages.Executor.run(context)
```

**Rationale:** Tilde expansion is a shell expansion, not cd-specific. When we add glob expansion, it goes in the same place.

### Decision 5: Redirector extracts from executor.ex

Current `executor.ex` has `apply_redirects/3` (~40 lines) mixed with execution logic. Extract to `Stages.Redirector` module.

**Rationale:** Separation of concerns. Executor dispatches commands; Redirector handles I/O.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Import path changes break tests | TDD approach: move one module, fix all imports, verify tests pass |
| Subtle behavior change in refactor | Comprehensive existing test suite (292 tests) catches regressions |
| Merge conflicts with glob branch | Complete refactor before rebasing glob branch |
| Module alias confusion during transition | Clear naming: `Stages.Executor` vs old `TrumanShell.Executor` |

## Migration Plan

**Phase 1: Support modules** (lowest risk)
1. Create `support/` directory
2. Move `sanitizer.ex` → `support/sanitizer.ex`
3. Move `commands/file_io.ex` → `support/file_io.ex`
4. Move `commands/tree_walker.ex` → `support/tree_walker.ex`
5. Update all imports, run tests

**Phase 2: Stage modules** (medium risk)
1. Create `stages/` directory
2. Move `tokenizer.ex` → `stages/tokenizer.ex`
3. Move `parser.ex` → `stages/parser.ex`
4. Move `executor.ex` → `stages/executor.ex`
5. Update all imports, run tests

**Phase 3: Extract Redirector** (surgical)
1. Create `stages/redirector.ex` with redirect logic from executor
2. Update executor to call redirector
3. Run tests

**Phase 4: Create Expander** (surgical)
1. Create `stages/expander.ex` with tilde expansion
2. Move tilde logic from `cd.ex` to expander
3. Wire expander into pipeline in `truman_shell.ex`
4. Update `cd.ex` to expect pre-expanded paths
5. Run tests

**Phase 5: Wire pipeline** (integration)
1. Update `truman_shell.ex` main API to use full pipeline
2. Verify end-to-end behavior
3. Run full test suite

**Rollback:** Each phase is a separate commit. Revert individual commits if needed.

## Open Questions

- **Versioning:** Should this be v0.5.1 (internal refactor) or part of v0.6.0 (with glob)?
  - Recommendation: v0.5.1 for refactor, v0.6.0 for glob. Keeps changes atomic.
