# Navigation Capability

## ADDED Requirements

### Requirement: Pwd Command
The executor SHALL implement the `pwd` command to display the current working directory.

#### Scenario: Show current directory
- **WHEN** executing `pwd`
- **THEN** return the current working directory path within the sandbox

#### Scenario: After cd command
- **WHEN** executing `cd subdir` followed by `pwd`
- **THEN** return the updated path including `subdir`

### Requirement: Cd Command
The executor SHALL implement the `cd` command to change the current working directory within the sandbox.

#### Scenario: Change to subdirectory
- **WHEN** executing `cd lib` where `lib/` exists in current directory
- **THEN** current directory is updated to include `lib`
- **AND** subsequent commands operate relative to new directory

#### Scenario: Change to parent directory
- **WHEN** executing `cd ..` from a subdirectory within sandbox
- **THEN** current directory moves up one level

#### Scenario: Cannot escape sandbox
- **WHEN** executing `cd ..` from sandbox root
- **THEN** current directory remains at sandbox root (no error, silent bound)

#### Scenario: Directory not found
- **WHEN** executing `cd nonexistent`
- **THEN** return error `cd: nonexistent: No such file or directory`

#### Scenario: Path outside sandbox
- **WHEN** executing `cd /etc`
- **THEN** return error `cd: /etc: No such file or directory` (404 principle)

#### Scenario: Home directory shortcut
- **WHEN** executing `cd ~`
- **THEN** return to sandbox root directory

#### Scenario: No argument
- **WHEN** executing `cd` with no arguments
- **THEN** return to sandbox root directory
