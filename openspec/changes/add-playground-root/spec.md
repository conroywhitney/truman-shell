## Feature: Playground Root Configuration

TrumanShell's execution context is configurable via environment variable, enabling the playground boundary to be set externally rather than defaulting to the current working directory.

> "Playground, not sandbox" — We're both Trumans in here. Co-creating, not containing.

## Requirements

### Requirement: Environment variable configuration

The system SHALL read the playground root from the `TRUMAN_PLAYGROUND_ROOT` environment variable.

#### Scenario: Environment variable is set
- **WHEN** `TRUMAN_PLAYGROUND_ROOT` is set to `/path/to/project`
- **THEN** the context's `playground_root` is `/path/to/project`

#### Scenario: Environment variable is not set
- **WHEN** `TRUMAN_PLAYGROUND_ROOT` is not set
- **THEN** the context's `playground_root` defaults to `File.cwd!()`

#### Scenario: Environment variable is empty string
- **WHEN** `TRUMAN_PLAYGROUND_ROOT` is set to `""`
- **THEN** the context's `playground_root` defaults to `File.cwd!()`

### Requirement: Path expansion in env var

The system SHALL expand special path notations in `TRUMAN_PLAYGROUND_ROOT`.

#### Scenario: Tilde expands to home directory
- **WHEN** `TRUMAN_PLAYGROUND_ROOT` is set to `~/studios/reification-labs`
- **THEN** the context's `playground_root` is `$HOME/studios/reification-labs`

#### Scenario: Dot expands to current directory
- **WHEN** `TRUMAN_PLAYGROUND_ROOT` is set to `.`
- **THEN** the context's `playground_root` is `File.cwd!()`

#### Scenario: Relative path expands to absolute
- **WHEN** `TRUMAN_PLAYGROUND_ROOT` is set to `./my-project`
- **THEN** the context's `playground_root` is `File.cwd!()/my-project`

#### Scenario: Dollar-sign env vars are NOT expanded
- **WHEN** `TRUMAN_PLAYGROUND_ROOT` is set to `$HOME/projects`
- **THEN** the context's `playground_root` is literally `$HOME/projects` (not expanded)
- **REASON** Expanding arbitrary env var references is a security risk

#### Scenario: Trailing slashes are normalized
- **WHEN** `TRUMAN_PLAYGROUND_ROOT` is set to `/custom/playground///`
- **THEN** the context's `playground_root` is `/custom/playground`

### Requirement: Terminology transition

The system SHALL begin transition from `sandbox_root` to `playground_root`.

#### Scenario: Context struct includes both keys (transition period)
- **WHEN** creating an execution context via `Boundaries.build_context()`
- **THEN** the map includes both `playground_root` and `sandbox_root` (for backwards compatibility)
- **AND** both keys have the same value

#### Scenario: New code uses playground_root
- **WHEN** writing new boundary-related code
- **THEN** use `playground_root` as the preferred key

**Note**: Full rename of `sandbox_root` to `playground_root` across all existing code is deferred to a future PR.

### Requirement: Path validation helper

The system SHALL provide a function to validate whether a path is within the playground boundary.

#### Scenario: Path within playground
- **WHEN** checking `/projects/myapp/lib/foo.ex` against playground root `/projects/myapp`
- **THEN** returns `{:ok, "/projects/myapp/lib/foo.ex"}`

#### Scenario: Path outside playground (absolute)
- **WHEN** checking `/etc/passwd` against playground root `/projects/myapp`
- **THEN** returns `{:error, :outside_playground}`

#### Scenario: Path escape attempt via traversal
- **WHEN** checking `/projects/myapp/../../../etc/passwd` against playground root `/projects/myapp`
- **THEN** returns `{:error, :outside_playground}` (path is expanded before check)

#### Scenario: Relative path within playground
- **WHEN** checking `lib/foo.ex` against playground root `/projects/myapp` with current_dir `/projects/myapp`
- **THEN** returns `{:ok, "/projects/myapp/lib/foo.ex"}` (resolved to absolute)

#### Scenario: Symlink escape attempt
- **WHEN** checking a symlink that points outside the playground
- **THEN** returns `{:error, :outside_playground}` (realpath is checked)

### Requirement: 404 Principle for outside paths

The system SHALL NOT reveal that a path exists outside the playground boundary.

#### Scenario: Outside path returns not found
- **WHEN** a command references a path outside the playground
- **THEN** returns "No such file or directory" (not "Permission denied" or "Outside playground")

## Acceptance Criteria

- [ ] `TRUMAN_PLAYGROUND_ROOT` env var configures the playground boundary
- [ ] All references to `sandbox_root` renamed to `playground_root`
- [ ] `TrumanShell.Boundaries.validate_path/2` function exists and handles all scenarios
- [ ] Symlink resolution prevents escape via symbolic links
- [ ] Path traversal (`../`) cannot escape the playground
- [ ] Error messages follow the 404 Principle (no information leakage)
