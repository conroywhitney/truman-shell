# Tasks: Add Executor POC

## Implementation Checklist

### Phase 1: Executor Foundation
- [ ] Create `lib/truman_shell/executor.ex` module stub
- [ ] Write failing test: `Executor.run/1` returns `{:ok, output}` for valid command
- [ ] Implement `run/1` with basic dispatch
- [ ] Write failing test: unknown commands return `{:error, "command not found"}`
- [ ] Implement unknown command handler

### Phase 2: ls Handler
- [ ] Write failing test: `ls` on current directory returns file listing
- [ ] Implement `handle(:cmd_ls, [])` — list current directory
- [ ] Write failing test: `ls` on specific path returns that directory's contents
- [ ] Implement `handle(:cmd_ls, [path])` — list specific directory
- [ ] Write failing test: `ls` on non-existent path returns error
- [ ] Implement error case for missing paths

### Phase 3: Depth Limits
- [ ] Write failing test: command with >10 pipes returns error
- [ ] Implement `validate_depth/1` check in `run/1`
- [ ] Add configuration option for max depth (default 10)

### Phase 4: Public API
- [ ] Write failing test: `TrumanShell.execute/1` parses and runs
- [ ] Implement `execute/1` in main module
- [ ] Add doctests for `execute/1`
- [ ] Update module documentation

### Phase 5: Integration Verification
- [ ] Verify IExReAct can call `TrumanShell.execute/1`
- [ ] Test in IEx: agent sends command, receives output
- [ ] Document integration point in README or CLAUDE.md

### Validation
- [ ] All tests pass (`mix test`)
- [ ] Code formatted (`mix format`)
- [ ] Static analysis clean (`mix credo`)
- [ ] Commit and push

## Dependencies

- Phase 2 depends on Phase 1
- Phase 3 can run parallel to Phase 2
- Phase 4 depends on Phase 1
- Phase 5 depends on Phase 4

## Notes

- Follow TDD strictly: write failing test → implement → refactor
- Each checkbox = one atomic commit opportunity
- Ask HITL if uncertain about design choices
