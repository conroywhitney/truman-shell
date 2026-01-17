# File Reading Capability

## ADDED Requirements

### Requirement: Cat Command
The executor SHALL implement the `cat` command to display file contents within the sandbox.

#### Scenario: Read single file
- **WHEN** executing `cat file.txt` where file exists in sandbox
- **THEN** return the complete file contents

#### Scenario: Read multiple files
- **WHEN** executing `cat file1.txt file2.txt`
- **THEN** return contents of both files concatenated

#### Scenario: File not found
- **WHEN** executing `cat missing.txt` where file does not exist
- **THEN** return error `cat: missing.txt: No such file or directory`

#### Scenario: Path outside sandbox
- **WHEN** executing `cat /etc/passwd`
- **THEN** return error `cat: /etc/passwd: No such file or directory` (404 principle)

### Requirement: Head Command
The executor SHALL implement the `head` command to display the first N lines of a file.

#### Scenario: Default line count
- **WHEN** executing `head file.txt` without `-n` flag
- **THEN** return first 10 lines of file

#### Scenario: Custom line count
- **WHEN** executing `head -n 5 file.txt`
- **THEN** return first 5 lines of file

#### Scenario: File shorter than requested
- **WHEN** executing `head -n 100 short.txt` on a 3-line file
- **THEN** return all 3 lines without error

### Requirement: Tail Command
The executor SHALL implement the `tail` command to display the last N lines of a file.

#### Scenario: Default line count
- **WHEN** executing `tail file.txt` without `-n` flag
- **THEN** return last 10 lines of file

#### Scenario: Custom line count
- **WHEN** executing `tail -n 5 file.txt`
- **THEN** return last 5 lines of file

#### Scenario: File shorter than requested
- **WHEN** executing `tail -n 100 short.txt` on a 3-line file
- **THEN** return all 3 lines without error
