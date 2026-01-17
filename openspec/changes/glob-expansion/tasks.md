# Glob Expansion Tasks

## 1. Foundation

- [x] 1.1 Create `lib/truman_shell/support/glob.ex` module for pattern matching logic
- [x] 1.2 Add `expand_glob/2` function that takes pattern + context, returns matches
- [x] 1.3 Add `is_glob_pattern?/1` helper to detect if arg contains `*`

## 2. Core Expander Integration

- [x] 2.1 Update `Expander.expand_arg/2` to call glob expansion after tilde expansion
- [x] 2.2 Handle glob returning multiple files (flatten args list in Command)
- [x] 2.3 Add `current_dir` to Expander context (needed for relative glob resolution)

## 3. Glob Matching Logic

- [x] 3.1 Implement basic `*` matching via `Path.wildcard/2`
- [x] 3.2 Implement `**` recursive matching (Path.wildcard supports this)
- [x] 3.3 Add sandbox filtering - exclude matches outside sandbox_root
- [ ] 3.4 Add depth limit for `**` patterns (max 100, consistent with TreeWalker)
- [x] 3.5 Sort results alphabetically
- [x] 3.6 Return original pattern when no matches (nullglob=off behavior)

## 4. Edge Cases

- [x] 4.1 Handle dotfiles (match_dot: false by default, true if pattern starts with `.`)
- [ ] 4.2 Handle filenames with spaces (ensure proper handling through pipeline)
- [x] 4.3 Handle empty directories (return original pattern)
- [x] 4.4 Handle non-existent directories in pattern (return original pattern)

## 5. Unit Tests (TDD)

- [x] 5.1 Test `Glob.expand/2` with `*.md` pattern
- [x] 5.2 Test `Glob.expand/2` with `**/*.md` recursive pattern
- [x] 5.3 Test sandbox boundary enforcement
- [x] 5.4 Test no-match returns original pattern
- [x] 5.5 Test dotfile exclusion/inclusion
- [x] 5.6 Test sorted results
- [ ] 5.7 Test filenames with spaces
- [ ] 5.8 Test multiple wildcards (`*_*_test.exs`, `f*o.*d`)
- [ ] 5.9 Test `**` depth limit (max 100 levels)

## 6. Expander Tests

- [x] 6.1 Test `Expander.expand/2` with glob in args
- [x] 6.2 Test tilde-then-glob expansion (`~/*.md`)
- [ ] 6.3 Test glob in piped commands
- [x] 6.4 Test non-glob args unchanged

## 7. Integration Tests

- [x] 7.1 Test `ls *.md` returns matching files
- [x] 7.2 Test `ls **/*.ex` recursive listing
- [x] 7.3 Test `cat *.txt` concatenates matching files
- [x] 7.4 Test `ls *.nonexistent` returns "No such file or directory"
- [x] 7.5 Test glob cannot escape sandbox
- [ ] 7.6 Test filenames with spaces work end-to-end
