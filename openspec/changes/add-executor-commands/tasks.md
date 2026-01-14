# Tasks: Add Executor Commands

> **Before Starting Implementation:**
> 1. Read `AGENTS.md` and `CLAUDE.md` to understand the how/what/why of this project
> 2. Pick the next incomplete Phase and **stick to that Phase only**
> 3. Use `/tdd` to enter test-driven development mode
> 4. **Stop when Phase is complete** — allow HITL to review and engage in collaborative feedback before creating a handoff and clearing context for the next phase

## Implementation Checklist

### Phase 1: Infrastructure
- [ ] 1.1 Add sandbox state tracking (current directory)
- [ ] 1.2 Implement redirect handling infrastructure
- [ ] 1.3 Create `.trash` directory support for soft deletes
- [ ] 1.4 Add output formatting utilities

### Phase 2: Navigation Commands
- [ ] 2.1 Write failing test: `pwd` returns current sandbox path
- [ ] 2.2 Implement `cmd_pwd` handler
- [ ] 2.3 Write failing test: `cd subdir` changes working directory
- [ ] 2.4 Implement `cmd_cd` handler with path validation
- [ ] 2.5 Write failing test: `cd ..` works within sandbox bounds
- [ ] 2.6 Write failing test: `cd /etc` blocked (404 principle)

### Phase 3: File Reading Commands
- [ ] 3.1 Write failing test: `cat file.txt` returns file contents
- [ ] 3.2 Implement `cmd_cat` handler with multi-file support
- [ ] 3.3 Write failing test: `head -n 5 file.txt` returns first 5 lines
- [ ] 3.4 Implement `cmd_head` handler with `-n` flag
- [ ] 3.5 Write failing test: `tail -n 5 file.txt` returns last 5 lines
- [ ] 3.6 Implement `cmd_tail` handler with `-n` flag
- [ ] 3.7 Write failing test: `cat missing.txt` returns "No such file"

### Phase 4: Echo and Redirects
- [ ] 4.1 Write failing test: `echo hello` returns "hello\n"
- [ ] 4.2 Implement `cmd_echo` handler
- [ ] 4.3 Write failing test: `echo hello > file.txt` creates file
- [ ] 4.4 Implement stdout redirect (`>`) in executor
- [ ] 4.5 Write failing test: `echo more >> file.txt` appends
- [ ] 4.6 Implement append redirect (`>>`)
- [ ] 4.7 Write failing test: redirect to path outside sandbox blocked

### Phase 5: File Writing Commands
- [ ] 5.1 Write failing test: `mkdir newdir` creates directory
- [ ] 5.2 Implement `cmd_mkdir` handler with `-p` flag
- [ ] 5.3 Write failing test: `touch file.txt` creates empty file
- [ ] 5.4 Implement `cmd_touch` handler
- [ ] 5.5 Write failing test: `rm file.txt` moves to .trash
- [ ] 5.6 Implement `cmd_rm` handler with soft delete
- [ ] 5.7 Write failing test: `mv old.txt new.txt` renames file
- [ ] 5.8 Implement `cmd_mv` handler
- [ ] 5.9 Write failing test: `cp src.txt dst.txt` copies file
- [ ] 5.10 Implement `cmd_cp` handler

### Phase 6: Search Commands
- [ ] 6.1 Write failing test: `grep pattern file.txt` finds matches
- [ ] 6.2 Implement `cmd_grep` handler with basic pattern matching
- [ ] 6.3 Write failing test: `grep -r pattern dir/` recursive search
- [ ] 6.4 Implement recursive grep with `-r` flag
- [ ] 6.5 Write failing test: `find . -name "*.ex"` finds files
- [ ] 6.6 Implement `cmd_find` handler with `-name` support
- [ ] 6.7 Write failing test: `wc file.txt` returns line/word/char counts
- [ ] 6.8 Implement `cmd_wc` handler

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
