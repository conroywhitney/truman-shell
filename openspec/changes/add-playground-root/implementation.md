## Implementation: Playground Root

### Files Created

#### `lib/truman_shell/boundaries.ex`

New module for playground boundary management.

**Public API:**

| Function | Purpose |
|----------|---------|
| `build_context/0` | Builds execution context with `playground_root` and `current_dir` |
| `playground_root/0` | Returns configured playground root (env var or cwd) |
| `validate_path/2,3` | Validates path is within playground boundary |
| `error_message/1` | Converts errors to user-facing messages (404 principle) |

**Key features:**
- Reads `TRUMAN_PLAYGROUND_ROOT` env var
- Expands `~`, `.`, relative paths
- Does NOT expand `$VAR` (security)
- Follows symlinks to detect escapes
- 404 principle: outside paths → "No such file or directory"

---

### Files Modified

#### `lib/truman_shell.ex`

**Change:** Line 53-61

```diff
- cwd = File.cwd!()
- context = %{sandbox_root: cwd, current_dir: cwd}
+ context = Boundaries.build_context()
```

Now uses `Boundaries.build_context()` instead of hardcoded `sandbox_root`.

**Added alias:**
```elixir
alias TrumanShell.Boundaries
```

---

### Backwards Compatibility

`build_context/0` returns both keys during transition:
```elixir
%{
  playground_root: "/path",
  sandbox_root: "/path",    # For existing commands
  current_dir: "/path"
}
```

Full rename of `sandbox_root` → `playground_root` planned for follow-up PR.
