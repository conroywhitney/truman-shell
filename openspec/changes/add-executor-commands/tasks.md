# Tasks: Add Executor Commands

> **Before Starting Implementation:**
> 1. Read `AGENTS.md` and `CLAUDE.md` to understand the how/what/why of this project
> 2. Pick the next incomplete Phase and **stick to that Phase only**
> 3. Use `/tdd` to enter test-driven development mode
> 4. **Stop when Phase is complete** — allow HITL to review and engage in collaborative feedback before creating a handoff and clearing context for the next phase

## Implementation Checklist

### Phase 1: Infrastructure ✅ (partial)
- [x] 1.1 Add sandbox state tracking (current directory via Process dictionary)
- [ ] 1.2 Implement redirect handling infrastructure → **moved to Phase 4**
- [ ] 1.3 Create `.trash` directory support for soft deletes → **needed for Phase 5**
- [x] 1.4 Add output formatting utilities (`Commands.Helpers.format_error/2`)

**Emergent Architecture: Command Pattern**
- Created `TrumanShell.Commands.Behaviour` with `@callback handle(args, context)`
- Created `TrumanShell.Commands.Helpers` for shared utilities (`read_file/2`, `format_error/2`)
- Executor uses `@command_modules` map for dispatch (~120 lines, down from ~340)
- Side effects return tagged tuples: `{:ok, output, set_cwd: path}`

### Phase 2: Navigation Commands ✅
- [x] 2.1 Write failing test: `pwd` returns current sandbox path
- [x] 2.2 Implement `cmd_pwd` handler → `Commands.Pwd`
- [x] 2.3 Write failing test: `cd subdir` changes working directory
- [x] 2.4 Implement `cmd_cd` handler with path validation → `Commands.Cd`
- [x] 2.5 Write failing test: `cd ..` works within sandbox bounds
- [x] 2.6 Write failing test: `cd /etc` blocked (404 principle)

### Phase 3: File Reading Commands ✅
- [x] 3.1 Write failing test: `cat file.txt` returns file contents
- [x] 3.2 Implement `cmd_cat` handler with multi-file support → `Commands.Cat`
- [x] 3.3 Write failing test: `head -n 5 file.txt` returns first 5 lines
- [x] 3.4 Implement `cmd_head` handler with `-n` flag → `Commands.Head`
- [x] 3.5 Write failing test: `tail -n 5 file.txt` returns last 5 lines
- [x] 3.6 Implement `cmd_tail` handler with `-n` flag → `Commands.Tail`
- [x] 3.7 Write failing test: `cat missing.txt` returns "No such file"
- [x] 3.8 Integer validation: `head -n foobar` returns error (not crash)

### Phase 4: Echo and Redirects ✅
- [x] 4.1 Write failing test: `echo hello` returns "hello\n"
- [x] 4.2 Implement `cmd_echo` handler → `Commands.Echo`
- [x] 4.3 Write failing test: `echo hello > file.txt` creates file
- [x] 4.4 Implement stdout redirect (`>`) in executor
- [x] 4.5 Write failing test: `echo more >> file.txt` appends
- [x] 4.6 Implement append redirect (`>>`)
- [x] 4.7 Write failing test: redirect to path outside sandbox blocked (404 principle)

**Redirect Architecture:**
- `apply_redirects/2` processes redirects after command execution
- `write_redirect/4` handles both `>` and `>>` with two-stage path validation
- Original path validated first (catches `/etc/passwd`), then resolved path

### Phase 5: File Writing Commands ✅
- [x] 5.1 Write failing test: `mkdir newdir` creates directory
- [x] 5.2 Implement `cmd_mkdir` handler with `-p` flag
- [x] 5.3 Write failing test: `touch file.txt` creates empty file
- [x] 5.4 Implement `cmd_touch` handler
- [x] 5.5 Write failing test: `rm file.txt` moves to .trash
- [x] 5.6 Implement `cmd_rm` handler with soft delete → **CRITICAL: Soft delete to `.trash/{timestamp}_{filename}`**
- [x] 5.7 Write failing test: `mv old.txt new.txt` renames file
- [x] 5.8 Implement `cmd_mv` handler
- [x] 5.9 Write failing test: `cp src.txt dst.txt` copies file
- [x] 5.10 Implement `cmd_cp` handler

**Phase 5 Notes:**
- All file writing commands follow TDD with comprehensive tests
- `rm` uses soft delete - files moved to `.trash/` with timestamp prefix
- All commands enforce sandbox boundaries (404 principle)
- Test count: 162 → 185 tests (+23), 49 → 54 doctests (+5)

### Phase 6: Search Commands ✅
- [x] 6.1 Write failing test: `grep pattern file.txt` finds matches
- [x] 6.2 Implement `cmd_grep` handler with basic pattern matching
- [x] 6.3 Write failing test: `grep -r pattern dir/` recursive search
- [x] 6.4 Implement recursive grep with `-r` flag
- [x] 6.5 Write failing test: `find . -name "*.ex"` finds files
- [x] 6.6 Implement `cmd_find` handler with `-name` support
- [x] 6.7 Write failing test: `wc file.txt` returns line/word/char counts
- [x] 6.8 Implement `cmd_wc` handler

**Phase 6 Notes:**
- All search commands implemented with TDD (27 tests)
- `grep` supports 7 flags: `-r`, `-n`, `-i`, `-v`, `-A`, `-B`, `-C`
- `find` supports `-name`, `-type`, `-maxdepth`
- `wc` supports `-l`, `-w`, `-c` flags
- All commands enforce sandbox boundaries (404 principle)

### Phase 7: Piping
- [ ] 7.1 Write failing test: `cat file.txt | head -5` returns first 5 lines
- [ ] 7.2 Implement pipe executor (chain command outputs)
- [ ] 7.3 Write failing test: `ls | grep pattern` filters output
- [ ] 7.4 Write failing test: 3-stage pipe `cat | grep | head`
- [ ] 7.5 Implement pipe depth validation (max 10)

### Phase 8: Utility Commands
- [ ] 8.1 Write failing test: `which ls` returns command info
- [ ] 8.2 Implement `cmd_which` handler
- [ ] 8.3 Write failing test: `date` returns current timestamp
- [ ] 8.4 Implement `cmd_date` handler
- [ ] 8.5 Implement `cmd_true` (exit 0) and `cmd_false` (exit 1)

### Validation
- [ ] All tests pass (`mix test`)
- [ ] Code formatted (`mix format`)
- [ ] Static analysis clean (`mix credo`)
- [ ] Documentation updated
- [ ] README roadmap updated to show v0.4 complete

## Dependencies

- Phase 2 (navigation) should come first (cd affects other commands)
- Phase 4 (redirects) needed before Phase 5 (file writing)
- Phase 7 (piping) can run after Phases 3-6

## Notes

- Follow TDD strictly: write failing test -> implement -> refactor
- Each checkbox = one atomic commit opportunity
- Use Sanitizer.validate_path/2 for all path operations
- rm MUST use soft delete (move to .trash, not File.rm!)
- Output should match real bash closely for agent believability

### Pattern for New Commands (established Phase 3)
```
1. Create lib/truman_shell/commands/<name>.ex with handle/2
2. Add :cmd_<name> => Commands.<Name> to @command_modules in executor.ex
3. Create test/truman_shell/commands/<name>_test.exs
4. Add dispatch smoke test to executor_test.exs
5. Add doctest to doctest_test.exs
```

### Intentional Design Decisions (vs real bash)

| Feature | Bash Behavior | Truman Shell | Reason |
|---------|---------------|--------------|--------|
| `ls -l`, `-la` | Long format listing | Rejected | MVP - simple listing sufficient |
| Glob patterns | Expanded by shell | Not implemented | Future enhancement |
| `cd ~` | Expands to $HOME | Not implemented | Future enhancement |
| `cd /etc` | Permission denied | "No such file" | 404 principle - no info leak |
| `cd mix.exs` | "Not a directory" | "Not a directory" | OK for files inside sandbox |
| Exit codes | Various (0, 1, 127...) | Only success/error | Simplified error model |

**Key principle**: The 404 principle overrides bash compatibility for paths outside sandbox.
- Inside sandbox: Match bash behavior
- Outside sandbox: Always "No such file or directory"
