# Expander Glob Expansion Spec

## MODIFIED Requirements

### Requirement: Expander expands shell syntax in arguments

The Expander stage SHALL expand glob patterns (`*` and `**`) in command arguments to matching file paths, in addition to existing tilde expansion.

Expansion order:
1. Tilde expansion (`~` → sandbox_root)
2. Glob expansion (`*`, `**` → matching files)

#### Scenario: Single asterisk matches files in current directory
- **WHEN** command has argument `*.md`
- **AND** current directory contains `README.md` and `CHANGELOG.md`
- **THEN** argument expands to `["README.md", "CHANGELOG.md"]` (sorted)

#### Scenario: Glob with prefix matches files starting with pattern
- **WHEN** command has argument `test_*.ex`
- **AND** current directory contains `test_foo.ex`, `test_bar.ex`, `other.ex`
- **THEN** argument expands to `["test_bar.ex", "test_foo.ex"]` (sorted)

#### Scenario: Glob with suffix matches files ending with pattern
- **WHEN** command has argument `*_test.exs`
- **AND** current directory contains `foo_test.exs`, `bar_test.exs`, `foo.exs`
- **THEN** argument expands to `["bar_test.exs", "foo_test.exs"]` (sorted)

#### Scenario: Directory glob matches files in subdirectory
- **WHEN** command has argument `lib/*.ex`
- **AND** `lib/` contains `foo.ex` and `bar.ex`
- **THEN** argument expands to `["lib/bar.ex", "lib/foo.ex"]` (sorted)

#### Scenario: Multiple wildcards in pattern
- **WHEN** command has argument `*_*_test.exs`
- **AND** directory contains `foo_bar_test.exs`, `a_b_test.exs`, `single_test.exs`
- **THEN** argument expands to `["a_b_test.exs", "foo_bar_test.exs"]` (matches with 2+ underscores)

#### Scenario: Wildcards in both name and extension
- **WHEN** command has argument `f*o.*d`
- **AND** directory contains `foo.md`, `filo.txt`, `franco.bad`
- **THEN** argument expands to `["foo.md", "franco.bad"]` (filo.txt excluded - no 'd')

#### Scenario: Tilde then glob expands correctly
- **WHEN** command has argument `~/*.md`
- **AND** sandbox_root contains `README.md`
- **THEN** argument expands to `["/sandbox/README.md"]`

## ADDED Requirements

### Requirement: Expander supports recursive glob patterns

The Expander SHALL expand `**` patterns to match files recursively across directories.

#### Scenario: Double asterisk matches files recursively
- **WHEN** command has argument `**/*.md`
- **AND** directory structure has `README.md`, `docs/guide.md`, `docs/api/ref.md`
- **THEN** argument expands to `["README.md", "docs/api/ref.md", "docs/guide.md"]` (sorted)

#### Scenario: Recursive glob in subdirectory
- **WHEN** command has argument `src/**/*.ex`
- **AND** `src/` contains `app.ex`, `lib/foo.ex`, `lib/utils/bar.ex`
- **THEN** argument expands to `["src/app.ex", "src/lib/foo.ex", "src/lib/utils/bar.ex"]` (sorted)

#### Scenario: Recursive glob respects max depth limit
- **WHEN** command has argument `**/*.md`
- **AND** directory structure has files at depths 1, 50, 100, and 105
- **THEN** files at depths 1, 50, and 100 are matched
- **AND** file at depth 105 is excluded (exceeds max depth of 100)

### Requirement: Glob expansion respects sandbox boundaries

The Expander SHALL NOT expand glob patterns to match files outside the sandbox root.

#### Scenario: Glob cannot escape sandbox via parent traversal
- **WHEN** command has argument `../*.md`
- **AND** pattern would match files outside sandbox
- **THEN** those files are excluded from expansion results

#### Scenario: Glob results filtered to sandbox
- **WHEN** glob pattern matches files both inside and outside sandbox
- **THEN** only files inside sandbox are included in expansion

### Requirement: No-match glob returns original pattern

The Expander SHALL return the original pattern unchanged when no files match.

#### Scenario: No matching files returns literal pattern
- **WHEN** command has argument `*.nonexistent`
- **AND** no files match the pattern
- **THEN** argument remains as literal string `"*.nonexistent"`

#### Scenario: Empty directory returns literal pattern
- **WHEN** command has argument `empty_dir/*.md`
- **AND** `empty_dir/` exists but contains no `.md` files
- **THEN** argument remains as literal string `"empty_dir/*.md"`

### Requirement: Glob expansion ignores dotfiles by default

The Expander SHALL NOT match dotfiles unless the pattern explicitly starts with a dot.

#### Scenario: Star pattern skips dotfiles
- **WHEN** command has argument `*`
- **AND** directory contains `file.txt`, `.hidden`, `.config`
- **THEN** argument expands to `["file.txt"]` only

#### Scenario: Explicit dot pattern matches dotfiles
- **WHEN** command has argument `.*`
- **AND** directory contains `file.txt`, `.hidden`, `.config`
- **THEN** argument expands to `[".config", ".hidden"]` (sorted, excludes regular files)

### Requirement: Glob expansion returns sorted results

The Expander SHALL return glob matches in alphabetical order for deterministic behavior.

#### Scenario: Results are alphabetically sorted
- **WHEN** command has argument `*.txt`
- **AND** directory contains `zebra.txt`, `apple.txt`, `mango.txt`
- **THEN** argument expands to `["apple.txt", "mango.txt", "zebra.txt"]`

### Requirement: Non-glob arguments pass through unchanged

The Expander SHALL only attempt glob expansion on arguments containing `*`.

#### Scenario: Regular argument unchanged
- **WHEN** command has argument `file.txt`
- **THEN** argument remains as `"file.txt"`

#### Scenario: Argument with no glob characters unchanged
- **WHEN** command has argument `path/to/specific/file.md`
- **THEN** argument remains as `"path/to/specific/file.md"`
