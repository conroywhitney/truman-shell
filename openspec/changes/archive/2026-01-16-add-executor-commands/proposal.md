# Proposal: Add Executor Commands

## Change ID
`add-executor-commands`

## Summary

Implement the remaining executor command handlers to make Truman Shell a fully functional sandboxed shell environment. This delivers v0.4's goal of "Read Operations" plus foundational write, search, and piping capabilities.

## Motivation

v0.3 delivered the executor with only `ls` implemented. The parser recognizes 20 commands, but agents can only list directories. The recent IExReAct header experiment revealed this gap: when Claude tried `echo hello > files.txt`, it failed because the executor doesn't support `echo` or redirects.

**Key finding from experiment**: The surveillance header variant uniquely triggered Truman Shell awareness (`::stage` command), but couldn't write files. Completing the executor unblocks AI-driven file operations.

## Scope

### In Scope
- **File reading**: `cat`, `head`, `tail`
- **Navigation**: `pwd`, `cd` (directory tracking)
- **File writing**: `echo` (with redirect support), `mkdir`, `touch`, `rm` (soft delete to .trash), `mv`, `cp`
- **Search**: `grep`, `find`, `wc`
- **Piping**: Execute command pipelines (`cat file | grep pattern | head -5`)
- **Redirects**: `>`, `>>`, `2>`, `<` operators

### Out of Scope (Future versions)
- The 404 principle enhancements (v0.8)
- WASM sandboxing (v0.9)
- Complex shell features (variables, loops, conditionals)
- Interactive commands (less, vim, etc.)

## Success Criteria

1. Agent can read files: `cat README.md` returns file contents
2. Agent can write files: `echo "hello" > test.txt` creates file
3. Agent can search: `grep TODO lib/*.ex` finds matches
4. Pipes work: `cat file.txt | head -5` returns first 5 lines
5. All 20 allowlisted commands have handlers (or explicit "not supported" messages)
6. Tests pass with TDD approach
7. rm uses soft delete (.trash directory)

## Related

- **Roadmap**: v0.4 in `README.md`
- **Consumer**: IExReAct (`../IExReAct`)
- **Prior art**: v0.3 executor in `lib/truman_shell/executor.ex`
- **Experiment**: Header A/B test showed file writing gap
