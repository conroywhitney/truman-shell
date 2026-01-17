# Piping Capability

## ADDED Requirements

### Requirement: Pipe Execution
The executor SHALL support piping output from one command as input to another using the `|` operator.

#### Scenario: Two-stage pipe
- **WHEN** executing `cat file.txt | head -5`
- **THEN** return first 5 lines of file.txt

#### Scenario: Three-stage pipe
- **WHEN** executing `cat file.txt | grep pattern | head -5`
- **THEN** return first 5 matching lines from file.txt

#### Scenario: Pipe with ls
- **WHEN** executing `ls | grep test`
- **THEN** return directory entries matching "test"

#### Scenario: First command fails
- **WHEN** executing `cat missing.txt | head -5`
- **THEN** return error from cat command (pipeline stops)

#### Scenario: Middle command has no output
- **WHEN** executing `cat file.txt | grep nomatch | head -5`
- **THEN** return empty output (no error)

### Requirement: Pipe Depth Limit
The executor SHALL enforce a maximum pipe depth to prevent resource exhaustion.

#### Scenario: Within limit
- **WHEN** executing a pipeline with 10 stages
- **THEN** execute normally

#### Scenario: Exceeds limit
- **WHEN** executing a pipeline with more than 10 stages
- **THEN** return error `pipe depth exceeded (max 10)`

### Requirement: Commands Accept Stdin
Commands that support piping SHALL accept input from the previous command in the pipeline.

#### Scenario: Grep from pipe
- **WHEN** `grep pattern` receives piped input
- **THEN** search the piped content for pattern

#### Scenario: Head from pipe
- **WHEN** `head -5` receives piped input
- **THEN** return first 5 lines of piped content

#### Scenario: Tail from pipe
- **WHEN** `tail -5` receives piped input
- **THEN** return last 5 lines of piped content

#### Scenario: Wc from pipe
- **WHEN** `wc -l` receives piped input
- **THEN** count lines in piped content
