## Feature: Configurable Sandbox Root via TRUMAN_DOME

TrumanShell's execution context is configurable via environment variable, enabling the sandbox boundary to be set externally rather than defaulting to the current working directory.

> "You're not leaving the dome, Truman."

## Requirements

### Requirement: Environment variable configuration

The system SHALL read the sandbox root from the `TRUMAN_DOME` environment variable.

#### Scenario: Environment variable is set
- **WHEN** `TRUMAN_DOME` is set to `/path/to/project`
- **THEN** the context's `sandbox_root` is `/path/to/project`

#### Scenario: Environment variable is not set
- **WHEN** `TRUMAN_DOME` is not set
- **THEN** the context's `sandbox_root` defaults to `File.cwd!()`

#### Scenario: Environment variable is empty string
- **WHEN** `TRUMAN_DOME` is set to `""`
- **THEN** the context's `sandbox_root` defaults to `File.cwd!()`

### Requirement: Path expansion in env var

The system SHALL expand special path notations in `TRUMAN_DOME`.

#### Scenario: Tilde expands to home directory
- **WHEN** `TRUMAN_DOME` is set to `~/studios/reification-labs`
- **THEN** the context's `sandbox_root` is `$HOME/studios/reification-labs`

#### Scenario: Dot expands to current directory
- **WHEN** `TRUMAN_DOME` is set to `.`
- **THEN** the context's `sandbox_root` is `File.cwd!()`

#### Scenario: Relative path expands to absolute
- **WHEN** `TRUMAN_DOME` is set to `./my-project`
- **THEN** the context's `sandbox_root` is `File.cwd!()/my-project`

#### Scenario: Dollar-sign env vars are NOT expanded
- **WHEN** `TRUMAN_DOME` is set to `$HOME/projects`
- **THEN** the context's `sandbox_root` is literally `$HOME/projects` (not expanded)
- **REASON** Expanding arbitrary env var references is a security risk

#### Scenario: Trailing slashes are normalized
- **WHEN** `TRUMAN_DOME` is set to `/custom/dome///`
- **THEN** the context's `sandbox_root` is `/custom/dome`

### Requirement: Path validation with symlink resolution

The system SHALL provide a function to validate whether a path is within the sandbox boundary, including recursive symlink resolution.

#### Scenario: Path within sandbox
- **WHEN** checking `/projects/myapp/lib/foo.ex` against sandbox root `/projects/myapp`
- **THEN** returns `{:ok, "/projects/myapp/lib/foo.ex"}`

#### Scenario: Path outside sandbox (absolute)
- **WHEN** checking `/etc/passwd` against sandbox root `/projects/myapp`
- **THEN** returns `{:error, :outside_sandbox}`

#### Scenario: Path escape attempt via traversal
- **WHEN** checking `/projects/myapp/../../../etc/passwd` against sandbox root `/projects/myapp`
- **THEN** returns `{:error, :outside_sandbox}` (path is expanded before check)

#### Scenario: Relative path within sandbox
- **WHEN** checking `lib/foo.ex` against sandbox root `/projects/myapp` with current_dir `/projects/myapp`
- **THEN** returns `{:ok, "/projects/myapp/lib/foo.ex"}` (resolved to absolute)

#### Scenario: Symlink escape attempt (final component)
- **WHEN** checking a symlink that points outside the sandbox
- **THEN** returns `{:error, :outside_sandbox}` (symlink target is resolved)

#### Scenario: Symlink escape attempt (intermediate directory)
- **WHEN** checking a path through a directory symlink that points outside
- **GIVEN** `/sandbox/escape` is a symlink to `/etc`
- **WHEN** checking `escape/passwd` against sandbox root `/sandbox`
- **THEN** returns `{:error, :outside_sandbox}` (all path components resolved)

#### Scenario: Chained symlink escape
- **WHEN** checking a path that traverses multiple symlinks
- **GIVEN** `/sandbox/link1` → `/sandbox/link2` → `/etc/passwd`
- **THEN** returns `{:error, :outside_sandbox}` (entire chain resolved)

#### Scenario: Symlink depth limit
- **WHEN** following a chain of symlinks that exceeds 10 levels
- **THEN** returns `{:error, :eloop}` (prevents infinite loops)

### Requirement: 404 Principle for outside paths

The system SHALL NOT reveal that a path exists outside the sandbox boundary.

#### Scenario: Outside path returns not found
- **WHEN** a command references a path outside the sandbox
- **THEN** returns "No such file or directory" (not "Permission denied" or "Outside sandbox")

## Acceptance Criteria

- [x] `TRUMAN_DOME` env var configures the sandbox boundary
- [x] `TrumanShell.Support.Sandbox.validate_path/2,3` handles all scenarios
- [x] Symlink resolution prevents escape via symbolic links (all path components)
- [x] Path traversal (`../`) cannot escape the sandbox
- [x] Error messages follow the 404 Principle (no information leakage)
- [x] Depth limit (10) prevents infinite symlink loops
