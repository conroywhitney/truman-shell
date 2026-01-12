# Tasks: Add Executor POC

## Implementation Checklist

### Phase 1: Executor Foundation
- [x] Create `lib/truman_shell/executor.ex` module stub
- [x] Write failing test: `Executor.run/1` returns `{:ok, output}` for valid command
- [x] Implement `run/1` with basic dispatch
- [x] Write failing test: unknown commands return `{:error, "command not found"}`
- [x] Implement unknown command handler

### Phase 2: ls Handler
- [x] Write failing test: `ls` on current directory returns file listing
- [x] Implement `handle(:cmd_ls, [])` — list current directory
- [x] Write failing test: `ls` on specific path returns that directory's contents
- [x] Implement `handle(:cmd_ls, [path])` — list specific directory
- [x] Write failing test: `ls` on non-existent path returns error
- [x] Implement error case for missing paths

### Phase 3: Depth Limits
- [x] Write failing test: command with >10 pipes returns error
- [x] Implement `validate_depth/1` check in `run/1`
- [x] Add configuration option for max depth (default 10)

### Phase 4: Public API
- [x] Write failing test: `TrumanShell.execute/1` parses and runs
- [x] Implement `execute/1` in main module
- [x] Add doctests for `execute/1`
- [x] Update module documentation

### Phase 5: Integration Verification
- [x] Verify IExReAct can call `TrumanShell.execute/1`
- [x] Test in IEx: agent sends command, receives output
- [x] Document integration point in README or CLAUDE.md

### Validation
- [x] All tests pass (`mix test`)
- [x] Code formatted (`mix format`)
- [x] Static analysis clean (`mix credo`)
- [x] Commit and push

## Dependencies

- Phase 2 depends on Phase 1
- Phase 3 can run parallel to Phase 2
- Phase 4 depends on Phase 1
- Phase 5 depends on Phase 4

## Notes

- Follow TDD strictly: write failing test → implement → refactor
- Each checkbox = one atomic commit opportunity
- Ask HITL if uncertain about design choices
