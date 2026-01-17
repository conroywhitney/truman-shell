# expander Specification Delta

## ADDED Requirements

### Requirement: Expand tilde in command arguments

The system SHALL expand `~` to sandbox root in all command arguments before execution.

#### Scenario: Tilde alone expands to sandbox root

- **WHEN** command contains argument `~`
- **THEN** it is expanded to `sandbox_root`

#### Scenario: Tilde with path expands correctly

- **WHEN** command contains argument `~/subdir`
- **THEN** it is expanded to `sandbox_root/subdir`

#### Scenario: Tilde with multiple slashes normalized

- **WHEN** command contains argument `~//lib` or `~///lib`
- **THEN** extra slashes are stripped and it expands to `sandbox_root/lib`

#### Scenario: Invalid tilde syntax unchanged

- **WHEN** command contains argument `~user`
- **THEN** it is NOT expanded (passed through unchanged)
- **AND** downstream command handles the error

### Requirement: Expansion runs before execution

The system SHALL run expansion as a pipeline stage BEFORE executor.

#### Scenario: Expansion stage position

- **WHEN** pipeline processes a command
- **THEN** order is: `Tokenizer → Parser → Expander → Executor → Redirector`

#### Scenario: Expander transforms Command struct

- **WHEN** `%Command{args: ["~", "~/lib"]}` is passed to Expander
- **THEN** output is `%Command{args: ["sandbox_root", "sandbox_root/lib"]}`
- **AND** all other Command fields are unchanged
