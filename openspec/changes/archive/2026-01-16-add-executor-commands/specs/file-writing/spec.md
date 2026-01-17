# File Writing Capability

## ADDED Requirements

### Requirement: Echo Command
The executor SHALL implement the `echo` command to output text.

#### Scenario: Simple echo
- **WHEN** executing `echo hello world`
- **THEN** return `hello world\n`

#### Scenario: Quoted string
- **WHEN** executing `echo "hello world"`
- **THEN** return `hello world\n`

#### Scenario: Empty echo
- **WHEN** executing `echo` with no arguments
- **THEN** return `\n` (empty line)

### Requirement: Stdout Redirect
The executor SHALL support the `>` redirect operator to write command output to a file.

#### Scenario: Create new file
- **WHEN** executing `echo hello > file.txt` where file does not exist
- **THEN** create file.txt containing `hello\n`
- **AND** return empty output (stdout captured)

#### Scenario: Overwrite existing file
- **WHEN** executing `echo new > file.txt` where file.txt exists
- **THEN** replace file.txt contents with `new\n`

#### Scenario: Redirect outside sandbox blocked
- **WHEN** executing `echo hack > /etc/passwd`
- **THEN** return error `bash: /etc/passwd: No such file or directory` (404 principle)

### Requirement: Append Redirect
The executor SHALL support the `>>` redirect operator to append to a file.

#### Scenario: Append to existing file
- **WHEN** executing `echo line2 >> file.txt` where file.txt contains `line1\n`
- **THEN** file.txt contains `line1\nline2\n`

#### Scenario: Create if not exists
- **WHEN** executing `echo first >> new.txt` where new.txt does not exist
- **THEN** create new.txt containing `first\n`

### Requirement: Mkdir Command
The executor SHALL implement the `mkdir` command to create directories.

#### Scenario: Create single directory
- **WHEN** executing `mkdir newdir`
- **THEN** create directory `newdir` in current location

#### Scenario: Create nested directories
- **WHEN** executing `mkdir -p path/to/deep/dir`
- **THEN** create all intermediate directories as needed

#### Scenario: Directory already exists
- **WHEN** executing `mkdir existing` where `existing/` exists
- **THEN** return error `mkdir: existing: File exists`

### Requirement: Touch Command
The executor SHALL implement the `touch` command to create empty files or update timestamps.

#### Scenario: Create new file
- **WHEN** executing `touch newfile.txt` where file does not exist
- **THEN** create empty file `newfile.txt`

#### Scenario: Update existing file
- **WHEN** executing `touch existing.txt` where file exists
- **THEN** update file modification timestamp (no content change)

### Requirement: Rm Command with Soft Delete
The executor SHALL implement the `rm` command using soft delete semantics.

#### Scenario: Delete file (soft)
- **WHEN** executing `rm file.txt`
- **THEN** move file.txt to `.trash/{timestamp}_file.txt`
- **AND** return no output

#### Scenario: Delete directory
- **WHEN** executing `rm -r dir/`
- **THEN** move entire directory to `.trash/{timestamp}_dir/`

#### Scenario: File not found
- **WHEN** executing `rm missing.txt`
- **THEN** return error `rm: missing.txt: No such file or directory`

#### Scenario: Force flag suppresses errors
- **WHEN** executing `rm -f missing.txt`
- **THEN** return no output (no error for missing file)

### Requirement: Mv Command
The executor SHALL implement the `mv` command to move/rename files.

#### Scenario: Rename file
- **WHEN** executing `mv old.txt new.txt`
- **THEN** rename file from old.txt to new.txt

#### Scenario: Move to directory
- **WHEN** executing `mv file.txt dir/`
- **THEN** move file.txt into dir/

#### Scenario: Source not found
- **WHEN** executing `mv missing.txt new.txt`
- **THEN** return error `mv: missing.txt: No such file or directory`

### Requirement: Cp Command
The executor SHALL implement the `cp` command to copy files.

#### Scenario: Copy file
- **WHEN** executing `cp src.txt dst.txt`
- **THEN** create dst.txt with same contents as src.txt
- **AND** src.txt remains unchanged

#### Scenario: Copy to directory
- **WHEN** executing `cp file.txt dir/`
- **THEN** create dir/file.txt with same contents

#### Scenario: Copy directory
- **WHEN** executing `cp -r srcdir/ dstdir/`
- **THEN** recursively copy srcdir to dstdir

#### Scenario: Source not found
- **WHEN** executing `cp missing.txt dst.txt`
- **THEN** return error `cp: missing.txt: No such file or directory`
