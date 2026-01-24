# TrumanShell.Boundaries

Configurable playground boundaries for TrumanShell.

## Quick Start

Set `TRUMAN_PLAYGROUND_ROOT` to configure the playground boundary:

```bash
# Use a specific directory
export TRUMAN_PLAYGROUND_ROOT=~/studios/reification-labs

# Use tilde notation
export TRUMAN_PLAYGROUND_ROOT=~/projects/myapp

# Use relative path (resolved to absolute)
export TRUMAN_PLAYGROUND_ROOT=./my-project
```

If not set, defaults to current working directory.

## API

### `TrumanShell.Boundaries.playground_root/0`

Returns the configured playground root path.

```elixir
TrumanShell.Boundaries.playground_root()
#=> "/Users/you/studios/reification-labs"
```

### `TrumanShell.Boundaries.validate_path/2`

Validates a path is within the playground boundary.

```elixir
# Path inside playground
TrumanShell.Boundaries.validate_path("/playground/lib/foo.ex", "/playground")
#=> {:ok, "/playground/lib/foo.ex"}

# Path outside playground
TrumanShell.Boundaries.validate_path("/etc/passwd", "/playground")
#=> {:error, :outside_playground}

# Path traversal blocked
TrumanShell.Boundaries.validate_path("../../../etc/passwd", "/playground", "/playground")
#=> {:error, :outside_playground}
```

### `TrumanShell.Boundaries.build_context/0`

Builds the execution context for TrumanShell commands.

```elixir
TrumanShell.Boundaries.build_context()
#=> %{playground_root: "/path", sandbox_root: "/path", current_dir: "/path"}
```

## Path Expansion

The env var supports:

| Input | Expansion |
|-------|-----------|
| `~/path` | `$HOME/path` |
| `.` | Current working directory |
| `./path` | Relative to cwd |
| `/absolute` | Used as-is |
| `$VAR/path` | **NOT expanded** (security) |

## 404 Principle

Paths outside the playground return "No such file or directory" rather than "Permission denied" or "Outside playground". This prevents information leakage about protected resources.

```elixir
TrumanShell.Boundaries.error_message({:error, :outside_playground})
#=> "No such file or directory"
```
