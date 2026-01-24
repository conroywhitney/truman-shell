## Test Plan: Playground Root

Tests written BEFORE implementation (TDD red phase).

## Test File Location

- **Artifact**: `tests/boundaries_test.exs`
- **Runtime location**: `test/truman_shell/boundaries_test.exs`
- **Run with**: `mix test test/truman_shell/boundaries_test.exs`

## Test Cases

### playground_root/0

| Scenario | Given | When | Then |
|----------|-------|------|------|
| Env var set | `TRUMAN_PLAYGROUND_ROOT=/custom` | `playground_root()` | Returns `/custom` |
| Env var not set | No env var | `playground_root()` | Returns `File.cwd!()` |
| Env var empty | `TRUMAN_PLAYGROUND_ROOT=""` | `playground_root()` | Returns `File.cwd!()` |
| Tilde expansion | `TRUMAN_PLAYGROUND_ROOT=~/foo` | `playground_root()` | Returns `$HOME/foo` |
| Dot expansion | `TRUMAN_PLAYGROUND_ROOT=.` | `playground_root()` | Returns `File.cwd!()` |
| Relative expansion | `TRUMAN_PLAYGROUND_ROOT=./proj` | `playground_root()` | Returns `cwd/proj` |
| No $VAR expansion | `TRUMAN_PLAYGROUND_ROOT=$HOME/x` | `playground_root()` | Returns literal `$HOME/x` |
| Trailing slashes | `TRUMAN_PLAYGROUND_ROOT=/foo///` | `playground_root()` | Returns `/foo` |

### validate_path/2

| Scenario | Given | When | Then |
|----------|-------|------|------|
| Path inside | `/playground/lib/foo.ex` | `validate_path(path, root)` | `{:ok, path}` |
| Path outside | `/etc/passwd` | `validate_path(path, root)` | `{:error, :outside_playground}` |
| Traversal attack | `../../../etc/passwd` | `validate_path(path, root)` | `{:error, :outside_playground}` |
| Relative inside | `lib/foo.ex` | `validate_path(path, root, cwd)` | `{:ok, absolute_path}` |
| Relative escapes | `../../etc/passwd` | `validate_path(path, root, cwd)` | `{:error, :outside_playground}` |
| Symlink outside | Link to `/etc` | `validate_path(link, root)` | `{:error, :outside_playground}` |
| Symlink inside | Link to `lib/foo.ex` | `validate_path(link, root)` | `{:ok, resolved_path}` |

### build_context/0

| Scenario | Given | When | Then |
|----------|-------|------|------|
| Context keys | Default setup | `build_context()` | Has `:playground_root`, not `:sandbox_root` |
| Default dirs | Default setup | `build_context()` | `current_dir == playground_root` |

### 404 Principle

| Scenario | Given | When | Then |
|----------|-------|------|------|
| Error message | `:outside_playground` error | `error_message(err)` | `"No such file or directory"` |

## Expected Results (Red Phase)

All tests should **FAIL** initially - no `TrumanShell.Boundaries` module exists yet.

```bash
$ mix test test/truman_shell/boundaries_test.exs
** (UndefinedFunctionError) function TrumanShell.Boundaries.playground_root/0 is undefined
```
