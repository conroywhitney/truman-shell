# redirector Specification Delta

## ADDED Requirements

### Requirement: Handle stdout redirection

The system SHALL handle stdout redirection to files as a separate pipeline stage.

#### Scenario: Write redirect creates file

- **WHEN** command output is "hello\n" and redirect is `{:write, "file.txt"}`
- **THEN** `file.txt` is created with content "hello\n"
- **AND** command returns empty string (output went to file)

#### Scenario: Append redirect adds to file

- **WHEN** command output is "more\n" and redirect is `{:append, "file.txt"}`
- **THEN** "more\n" is appended to existing `file.txt` content

#### Scenario: Redirect to path outside sandbox blocked

- **WHEN** redirect target is outside sandbox (e.g., `/etc/passwd`)
- **THEN** it returns `{:error, "No such file or directory"}`
- **AND** no file is created or modified

### Requirement: Redirector runs after executor

The system SHALL run redirect handling as a pipeline stage AFTER executor.

#### Scenario: Redirector stage position

- **WHEN** pipeline processes a command with redirects
- **THEN** order is: `Executor → Redirector`
- **AND** Redirector receives executor output and redirect list

#### Scenario: No redirects passes through

- **WHEN** command has no redirects (`redirects: []`)
- **THEN** Redirector returns executor output unchanged

### Requirement: Sandbox path validation

The system SHALL validate redirect paths against sandbox boundaries.

#### Scenario: Redirect within sandbox allowed

- **WHEN** redirect target resolves to path within `sandbox_root`
- **THEN** redirect is allowed to proceed

#### Scenario: Redirect traversal attack blocked

- **WHEN** redirect target is `../../etc/passwd`
- **THEN** it returns error with "No such file or directory"
- **AND** error does NOT mention "permission" or "denied"
