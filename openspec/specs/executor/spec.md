# executor Specification

## Purpose

Execute parsed shell commands in a sandboxed environment that appears authentic to AI agents while enforcing security boundaries via the 404 principle.

## Status

**v0.5** - Core executor complete with 18 commands, piping, and redirects.

## Implemented Commands

| Category | Commands | Flags |
|----------|----------|-------|
| Navigation | `cd`, `pwd` | `cd ~`, `cd ~/subdir` |
| Read | `cat`, `head`, `tail` | `-n` |
| Search | `grep`, `find`, `wc` | `-rinvABC`, `-name/-type/-maxdepth`, `-lwc` |
| Write | `mkdir`, `touch`, `rm`, `mv`, `cp`, `echo` | `-p`, soft delete |
| Utility | `ls`, `which`, `date`, `true`, `false` | `-laR` |

## Requirements

### Requirement: Execute parsed commands

The system MUST execute a parsed `%Command{}` struct and return output.

#### Scenario: Execute valid command

**Given** a parsed command `%Command{name: :cmd_ls, args: []}`
**When** `Executor.run/1` is called
**Then** it returns `{:ok, output}` where `output` is a string

#### Scenario: Execute unknown command

**Given** a parsed command `%Command{name: {:unknown, "xyz"}, args: []}`
**When** `Executor.run/1` is called
**Then** it returns `{:error, "bash: xyz: command not found\n"}`

---

### Requirement: Enforce sandbox boundaries (404 principle)

The system MUST block access outside the sandbox WITHOUT revealing what exists.

#### Scenario: Access path outside sandbox

**Given** command `ls /etc`
**When** `Executor.run/1` is called
**Then** it returns `{:error, "ls: /etc: No such file or directory\n"}`
**And** the error does NOT mention "permission" or "denied"

#### Scenario: Traversal attack blocked

**Given** command `cd ~/../../etc`
**When** `Executor.run/1` is called
**Then** it returns `{:error, "cd: ~/../../etc: No such file or directory\n"}`

---

### Requirement: Enforce pipe depth limits

The system MUST reject commands that exceed maximum pipe depth (10).

#### Scenario: Command within depth limit

**Given** a command with 3 pipes (depth = 4)
**When** `Executor.run/1` is called
**Then** it executes normally

#### Scenario: Command exceeds depth limit

**Given** a command with 15 pipes (depth = 16)
**When** `Executor.run/1` is called
**Then** it returns `{:error, "pipe depth exceeded (max 10)\n"}`

---

### Requirement: Support piping between commands

The system MUST chain command outputs through pipes.

#### Scenario: Two-stage pipe

**Given** command `cat file.txt | head -5`
**When** `Executor.run/1` is called
**Then** `cat` output is passed as stdin to `head`
**And** final output is first 5 lines

#### Scenario: Commands supporting stdin

**Given** commands `head`, `tail`, `grep`, `wc`
**When** receiving piped input via `context[:stdin]`
**Then** they process stdin instead of requiring file argument

---

### Requirement: Support redirects

The system MUST handle stdout redirection to files.

#### Scenario: Write redirect

**Given** command `echo hello > file.txt`
**When** `Executor.run/1` is called
**Then** `file.txt` is created with content "hello\n"

#### Scenario: Append redirect

**Given** command `echo more >> file.txt`
**When** `Executor.run/1` is called
**Then** "more\n" is appended to `file.txt`

#### Scenario: Redirect outside sandbox blocked

**Given** command `echo pwned > /etc/passwd`
**When** `Executor.run/1` is called
**Then** it returns error with "No such file or directory"

---

### Requirement: Soft delete for rm

The system MUST move deleted files to `.trash/` instead of permanent deletion.

#### Scenario: Remove file

**Given** command `rm file.txt`
**When** `Executor.run/1` is called
**Then** `file.txt` is moved to `.trash/{timestamp}_file.txt`
**And** original file no longer exists at original path

---

### Requirement: Tilde expansion

The system MUST expand `~` to sandbox root in `cd` command.

#### Scenario: cd with tilde

**Given** command `cd ~` or `cd ~/subdir`
**When** `Executor.run/1` is called
**Then** `~` expands to `sandbox_root`

#### Scenario: Invalid tilde syntax

**Given** command `cd ~user`
**When** `Executor.run/1` is called
**Then** it returns "No such file or directory" (not supported)

---

## Not Yet Implemented

| Feature | Target |
|---------|--------|
| Glob expansion (`*.ex`, `**/*.md`) | v0.6 |
| Virtual FS (ETS-backed) | v1.x |
| WASM script sandboxing | v1.x |

---

## History

- **v0.3** (2026-01-14): Initial POC with `ls` command
- **v0.4** (2026-01-15): 18 commands, piping, redirects (280 tests)
- **v0.5** (2026-01-16): Tilde expansion, security hardening (292 tests)
