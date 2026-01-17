# Search Capability

## ADDED Requirements

### Requirement: Grep Command
The executor SHALL implement the `grep` command to search for patterns in files.

#### Scenario: Search single file
- **WHEN** executing `grep pattern file.txt` where file contains matching lines
- **THEN** return all lines containing "pattern"

#### Scenario: No matches
- **WHEN** executing `grep nomatch file.txt` where no lines match
- **THEN** return empty output (exit normally)

#### Scenario: Search multiple files
- **WHEN** executing `grep pattern *.txt` matching multiple files
- **THEN** return matches prefixed with filename `file1.txt:matching line`

#### Scenario: Case insensitive search
- **WHEN** executing `grep -i PATTERN file.txt`
- **THEN** match "pattern", "Pattern", "PATTERN" etc.

#### Scenario: Recursive search
- **WHEN** executing `grep -r pattern dir/`
- **THEN** search all files in dir/ recursively

#### Scenario: File not found
- **WHEN** executing `grep pattern missing.txt`
- **THEN** return error `grep: missing.txt: No such file or directory`

### Requirement: Find Command
The executor SHALL implement the `find` command to locate files by name.

#### Scenario: Find by name
- **WHEN** executing `find . -name "*.ex"`
- **THEN** return all .ex files under current directory

#### Scenario: Find in subdirectory
- **WHEN** executing `find lib -name "*.ex"`
- **THEN** return all .ex files under lib/

#### Scenario: No matches
- **WHEN** executing `find . -name "*.xyz"` with no matching files
- **THEN** return empty output

#### Scenario: Find type file
- **WHEN** executing `find . -type f`
- **THEN** return all regular files (not directories)

#### Scenario: Find type directory
- **WHEN** executing `find . -type d`
- **THEN** return all directories

### Requirement: Wc Command
The executor SHALL implement the `wc` command to count lines, words, and characters.

#### Scenario: Count all
- **WHEN** executing `wc file.txt`
- **THEN** return `  <lines>  <words> <chars> file.txt` format

#### Scenario: Lines only
- **WHEN** executing `wc -l file.txt`
- **THEN** return `  <lines> file.txt`

#### Scenario: Words only
- **WHEN** executing `wc -w file.txt`
- **THEN** return `  <words> file.txt`

#### Scenario: Characters only
- **WHEN** executing `wc -c file.txt`
- **THEN** return `  <chars> file.txt`

#### Scenario: Multiple files
- **WHEN** executing `wc file1.txt file2.txt`
- **THEN** return counts for each file plus total line

#### Scenario: File not found
- **WHEN** executing `wc missing.txt`
- **THEN** return error `wc: missing.txt: No such file or directory`
