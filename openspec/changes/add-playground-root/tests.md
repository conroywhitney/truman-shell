## Tests: Playground Root

**Location:** `test/truman_shell/support/sandbox_test.exs`

**Run:** `mix test test/truman_shell/support/sandbox_test.exs`

**Status:** All tests pass (integrated into existing Sandbox tests)

---

### New Test Suites

#### `sandbox_root/0` (8 tests)

| Test | Scenario |
|------|----------|
| env var set | `TRUMAN_DOME=/custom` → returns `/custom` |
| env var not set | No env var → returns `File.cwd!()` |
| env var empty | `""` → returns `File.cwd!()` |
| tilde expansion | `~/foo` → `$HOME/foo` |
| dot expansion | `.` → `File.cwd!()` |
| relative expansion | `./proj` → `cwd/proj` |
| no $VAR expansion | `$HOME/x` → literal `$HOME/x` (security) |
| trailing slashes | `/foo///` → `/foo` |

#### `validate_path/3` with current_dir (4 tests)

| Test | Scenario |
|------|----------|
| relative inside | `lib/foo.ex` with current_dir → resolved |
| relative escapes | `../../etc/passwd` → blocked |
| symlink outside | link → `/etc` → blocked |
| symlink inside | link → `lib/foo.ex` → allowed |

#### `build_context/0` (2 tests)

| Test | Scenario |
|------|----------|
| has sandbox_root | Context map includes `:sandbox_root` |
| current_dir matches | `current_dir == sandbox_root` |

#### `error_message/1` (2 tests)

| Test | Scenario |
|------|----------|
| outside_sandbox | `:outside_sandbox` → "No such file or directory" |
| enoent | `:enoent` → "No such file or directory" |
