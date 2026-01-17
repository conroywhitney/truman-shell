# Design: Add Executor Commands

## Context

The executor currently has one command handler (`ls`). We need to add 19 more while maintaining:
- Sandbox confinement (all paths validated)
- The 404 principle (protected paths return "not found")
- Soft delete semantics (rm moves to .trash)
- Believable bash-like output

## Goals / Non-Goals

**Goals:**
- Complete command coverage for common shell operations
- Enable file read/write for AI agents
- Support piping for command composition
- Maintain security properties

**Non-Goals:**
- Interactive commands (vim, less, etc.)
- Shell variables and scripting
- Signal handling
- Background processes

## Decisions

### Decision: Executor State via Process Dictionary
- **What**: Track current working directory in Process dictionary
- **Why**: Simple, no GenServer overhead, matches shell semantics
- **Alternative**: GenServer with state — rejected due to complexity for POC

```elixir
defp current_dir do
  Process.get(:truman_cwd, sandbox_root())
end

defp set_current_dir(path) do
  Process.put(:truman_cwd, path)
end
```

### Decision: Piping via Fold Pattern
- **What**: Execute pipes left-to-right, passing output as stdin
- **Why**: Clean functional pattern, handles depth naturally

```elixir
def execute_pipeline([first | rest]) do
  Enum.reduce_while(rest, execute(first), fn cmd, {:ok, prev_output} ->
    case execute_with_stdin(cmd, prev_output) do
      {:ok, output} -> {:cont, {:ok, output}}
      error -> {:halt, error}
    end
  end)
end
```

### Decision: Soft Delete to .trash Directory
- **What**: `rm` moves files to `{sandbox}/.trash/{timestamp}_{filename}`
- **Why**: Reversible operations are core to Truman Shell philosophy
- **Alternative**: Real delete — rejected, violates design principles

### Decision: Output Formatting Module
- **What**: Dedicated module for bash-like output formatting
- **Why**: Consistency across commands, easy to test

```elixir
defmodule TrumanShell.Formatter do
  def error(cmd, msg), do: "#{cmd}: #{msg}\n"
  def not_found(path), do: "No such file or directory"
  def permission_denied, do: "Permission denied"  # Never use! 404 principle
end
```

### Decision: Redirect Handling in Executor
- **What**: Process redirects after command execution, not in individual handlers
- **Why**: DRY, single point for redirect security validation

```elixir
def run(%Command{redirects: redirects} = cmd) do
  with {:ok, output} <- execute_command(cmd),
       :ok <- apply_redirects(output, redirects) do
    {:ok, if(has_stdout_redirect?(redirects), do: "", else: output)}
  end
end
```

## Risks / Trade-offs

| Risk | Impact | Mitigation |
|------|--------|------------|
| Path traversal in redirects | Security | Use Sanitizer.validate_path for all file operations |
| Process dictionary leaks | Correctness | Clear state between agent sessions |
| Large file output | Memory | Keep existing 200-line limit, add 64KB byte limit |
| Symlink escape | Security | Path.safe_relative/2 handles symlinks |

## Migration Plan

No migration needed - pure additive feature.

## Open Questions

1. **stdin redirect (<)**: Support now or defer? Deferred to future version.
2. **stderr redirect (2>)**: Same answer - defer.
3. **Command chaining (&&, ||)**: Defer - parser supports but executor can wait.
