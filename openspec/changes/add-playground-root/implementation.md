## Implementation: Playground Root

### Files Modified

#### `lib/truman_shell/support/sandbox.ex`

Enhanced with configurable sandbox root via `TRUMAN_DOME` environment variable.

**Public API:**

| Function | Purpose |
|----------|---------|
| `build_context/0` | Builds execution context with `sandbox_root` and `current_dir` |
| `sandbox_root/0` | Returns configured sandbox root (env var or cwd) |
| `validate_path/2,3` | Validates path is within sandbox boundary (now with symlink detection) |
| `error_message/1` | Converts errors to user-facing messages (404 principle) |

**Key features:**
- Reads `TRUMAN_DOME` env var
- Expands `~`, `.`, relative paths
- Does NOT expand `$VAR` (security)
- Follows symlinks to detect escapes
- 404 principle: outside paths → "No such file or directory"

---

#### `lib/truman_shell.ex`

**Change:** Line 53-61

```diff
- cwd = File.cwd!()
- context = %{sandbox_root: cwd, current_dir: cwd}
+ context = Sandbox.build_context()
```

Now uses `Sandbox.build_context()` instead of hardcoded `sandbox_root`.

**Added alias:**
```elixir
alias TrumanShell.Support.Sandbox
```

---

### Usage

```bash
export TRUMAN_DOME=~/code/my-project
```

"You're not leaving the dome, Truman."
