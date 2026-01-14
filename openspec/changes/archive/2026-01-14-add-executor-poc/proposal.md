# Proposal: Add Executor POC

## Change ID
`add-executor-poc`

## Summary

Implement the Executor module to run parsed commands in a sandboxed environment, completing the v0.3 "Proof of Concept Loop". This enables an agent to send a bash command, have it parsed, executed, and receive realistic shell output.

## Motivation

v0.2 delivered the parser — we can turn `"ls -la"` into `%Command{name: :cmd_ls, args: ["-la"]}`. But the agent can't *do* anything with it yet. v0.3 closes the loop by:

1. Adding an `Executor` module that runs commands
2. Implementing the `ls` command handler as proof of concept
3. Integrating with IExReAct so agents can use Truman Shell

## Scope

### In Scope
- `TrumanShell.Executor` module with `run/1` function
- `ls` command handler (basic implementation, no flags initially)
- Public API: `TrumanShell.execute/1` that parses and runs
- Integration point for IExReAct consumption
- Depth limit enforcement (max pipe depth)

### Out of Scope (Future versions)
- Other commands (cat, grep, cd, etc.) — v0.4+
- Pipe execution between commands — v0.7
- Path permissions / 404 principle — v0.8
- WASM sandboxing — v0.9

## Success Criteria

1. `TrumanShell.execute("ls")` returns `{:ok, "file1.txt\nfile2.txt\n..."}`
2. Agent in IExReAct can run `ls` and receive realistic output
3. Unknown commands return `{:error, "bash: xyz: command not found\n"}`
4. Tests pass with TDD approach (red-green-refactor)

## Related

- **Roadmap**: v0.3 in `CLAUDE.md`
- **Consumer**: IExReAct (`../IExReAct`)
- **Prior art**: v0.2 parser in `lib/truman_shell/parser.ex`
