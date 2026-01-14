# Executor Capability

## Overview

The Executor module runs parsed commands in a sandboxed environment and returns shell-like output.

## ADDED Requirements

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

### Requirement: Enforce depth limits

The system MUST reject commands that exceed maximum pipe depth.

#### Scenario: Command within depth limit

**Given** a command with 3 pipes (depth = 4)
**And** max depth is 10
**When** `Executor.run/1` is called
**Then** it executes normally

#### Scenario: Command exceeds depth limit

**Given** a command with 15 pipes (depth = 16)
**And** max depth is 10
**When** `Executor.run/1` is called
**Then** it returns `{:error, "pipe depth exceeded (max 10)\n"}`

---

### Requirement: Handle ls command

The system MUST list directory contents for the `ls` command.

#### Scenario: List current directory

**Given** command `%Command{name: :cmd_ls, args: []}`
**And** current directory contains `["file.txt", "dir/"]`
**When** `Executor.run/1` is called
**Then** it returns `{:ok, "dir/\nfile.txt\n"}` (sorted, dirs have trailing /)

#### Scenario: List specific directory

**Given** command `%Command{name: :cmd_ls, args: ["src"]}`
**And** `src/` contains `["main.ex", "helper.ex"]`
**When** `Executor.run/1` is called
**Then** it returns `{:ok, "helper.ex\nmain.ex\n"}` (sorted)

#### Scenario: List non-existent directory

**Given** command `%Command{name: :cmd_ls, args: ["nonexistent"]}`
**When** `Executor.run/1` is called
**Then** it returns `{:error, "ls: nonexistent: No such file or directory\n"}`

---

### Requirement: Provide convenient execute API

The main module MUST provide a single function to parse and execute.

#### Scenario: Execute from string

**Given** command string `"ls"`
**When** `TrumanShell.execute/1` is called
**Then** it parses the string and executes, returning `{:ok, output}`

#### Scenario: Execute invalid syntax

**Given** command string `"ls | | grep"` (invalid: empty pipe segment)
**When** `TrumanShell.execute/1` is called
**Then** it returns `{:error, reason}` from the parser

## Cross-References

- Depends on: Parser capability (v0.2)
- Consumed by: IExReAct agent loop
- Future: Pipes capability (v0.7) will extend this
