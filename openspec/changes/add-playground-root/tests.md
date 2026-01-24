## Tests: Playground Root

**Location:** `test/truman_shell/boundaries_test.exs`

**Run:** `mix test test/truman_shell/boundaries_test.exs`

**Status:** 18 tests, 0 failures

---

### Test Suites

#### `playground_root/0` (9 tests)

| Test | Scenario |
|------|----------|
| env var set | `TRUMAN_PLAYGROUND_ROOT=/custom` → returns `/custom` |
| env var not set | No env var → returns `File.cwd!()` |
| env var empty | `""` → returns `File.cwd!()` |
| tilde expansion | `~/foo` → `$HOME/foo` |
| dot expansion | `.` → `File.cwd!()` |
| relative expansion | `./proj` → `cwd/proj` |
| no $VAR expansion | `$HOME/x` → literal `$HOME/x` (security) |
| trailing slashes | `/foo///` → `/foo` |

#### `validate_path/2,3` (7 tests)

| Test | Scenario |
|------|----------|
| path inside | `/playground/lib/foo.ex` → `{:ok, path}` |
| path outside | `/etc/passwd` → `{:error, :outside_playground}` |
| traversal attack | `../../../etc/passwd` → blocked |
| relative inside | `lib/foo.ex` → resolved to absolute |
| relative escapes | `../../etc/passwd` → blocked |
| symlink outside | link → `/etc` → blocked |
| symlink inside | link → `lib/foo.ex` → allowed |

#### `build_context/0` (2 tests)

| Test | Scenario |
|------|----------|
| has playground_root | Context map includes `:playground_root` |
| current_dir matches | `current_dir == playground_root` |

#### `error_message/1` (1 test)

| Test | Scenario |
|------|----------|
| 404 principle | `:outside_playground` → "No such file or directory" |
