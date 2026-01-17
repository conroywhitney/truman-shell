# executor Specification Delta

## MODIFIED Requirements

### Requirement: Tilde expansion

The system MUST expand `~` to sandbox root via Expander stage (before Executor).

#### Scenario: cd with tilde

- **WHEN** command `cd ~` or `cd ~/subdir` enters pipeline
- **THEN** Expander stage expands `~` to `sandbox_root`
- **AND** Executor receives pre-expanded path

#### Scenario: Invalid tilde syntax

- **WHEN** command `cd ~user` enters pipeline
- **THEN** Expander passes through unchanged
- **AND** Executor returns "No such file or directory" (path doesn't exist)

### Requirement: Support redirects

The system MUST handle stdout redirection to files via Redirector stage (after Executor).

#### Scenario: Write redirect

- **WHEN** command `echo hello > file.txt` enters pipeline
- **THEN** Executor produces output "hello\n"
- **AND** Redirector writes output to `file.txt`

#### Scenario: Append redirect

- **WHEN** command `echo more >> file.txt` enters pipeline
- **THEN** Executor produces output "more\n"
- **AND** Redirector appends output to `file.txt`

#### Scenario: Redirect outside sandbox blocked

- **WHEN** command `echo pwned > /etc/passwd` enters pipeline
- **THEN** Redirector validates path against sandbox
- **AND** returns error with "No such file or directory"
