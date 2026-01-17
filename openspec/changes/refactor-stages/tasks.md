# Tasks: Pipeline Stages Refactor

## 1. Move Support Modules

- [x] 1.1 Create `lib/truman_shell/support/` directory
- [x] 1.2 Move `sanitizer.ex` → `support/sanitizer.ex`, update module name to `TrumanShell.Support.Sanitizer`
- [x] 1.3 Update all imports of `TrumanShell.Sanitizer` across codebase
- [x] 1.4 Move `commands/file_io.ex` → `support/file_io.ex`, update module name to `TrumanShell.Support.FileIO`
- [x] 1.5 Update all imports of `TrumanShell.Commands.FileIO` across codebase
- [x] 1.6 Move `commands/tree_walker.ex` → `support/tree_walker.ex`, update module name to `TrumanShell.Support.TreeWalker`
- [x] 1.7 Update all imports of `TrumanShell.Commands.TreeWalker` across codebase
- [x] 1.8 Run `mix test` - all 292 tests must pass

## 2. Move Stage Modules

- [ ] 2.1 Create `lib/truman_shell/stages/` directory
- [ ] 2.2 Move `tokenizer.ex` → `stages/tokenizer.ex`, update module name to `TrumanShell.Stages.Tokenizer`
- [ ] 2.3 Update all imports of `TrumanShell.Tokenizer` across codebase
- [ ] 2.4 Move `parser.ex` → `stages/parser.ex`, update module name to `TrumanShell.Stages.Parser`
- [ ] 2.5 Update all imports of `TrumanShell.Parser` across codebase
- [ ] 2.6 Move `executor.ex` → `stages/executor.ex`, update module name to `TrumanShell.Stages.Executor`
- [ ] 2.7 Update all imports of `TrumanShell.Executor` across codebase
- [ ] 2.8 Run `mix test` - all 292 tests must pass

## 3. Extract Redirector Stage

- [ ] 3.1 Create `stages/redirector.ex` with `TrumanShell.Stages.Redirector` module
- [ ] 3.2 Write tests for Redirector: write redirect, append redirect, sandbox validation
- [ ] 3.3 Extract `apply_redirects/3` logic from `Stages.Executor` to `Stages.Redirector`
- [ ] 3.4 Update `Stages.Executor` to call `Stages.Redirector.apply/3` after execution
- [ ] 3.5 Run `mix test` - all tests must pass

## 4. Create Expander Stage

- [ ] 4.1 Create `stages/expander.ex` with `TrumanShell.Stages.Expander` module
- [ ] 4.2 Write tests for Expander: `~`, `~/path`, `~//path`, `~user` (unchanged)
- [ ] 4.3 Implement `expand/2` function that transforms `%Command{}` args
- [ ] 4.4 Remove tilde expansion logic from `commands/cd.ex` (lines 44-49)
- [ ] 4.5 Wire Expander into pipeline: call before Executor in `truman_shell.ex`
- [ ] 4.6 Run `mix test` - all tests must pass (tilde tests still work via Expander)

## 5. Wire Full Pipeline

- [ ] 5.1 Update `TrumanShell.run/2` to use explicit pipeline: `Tokenizer → Parser → Expander → Executor → Redirector`
- [ ] 5.2 Add integration tests for full pipeline flow
- [ ] 5.3 Run `mix format && mix test && mix credo`
- [ ] 5.4 Verify 292+ tests pass
- [ ] 5.5 Commit with message "refactor: pipeline stages architecture"
