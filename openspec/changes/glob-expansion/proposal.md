# Proposal: Glob Expansion

## Why

AI agents (especially Claude Code) frequently use glob patterns like `ls *.md` and `cat src/*.ts` to work with multiple files. Currently these patterns are passed as literal strings, causing "file not found" errors. This is one of the most common gaps between TrumanShell and real bash behavior.

## What Changes

- Expand `*` patterns to matching files within sandbox
- Return appropriate error when no files match (bash-like behavior)
- Support glob patterns in file argument positions for applicable commands

**Supported patterns (v0.6):**
- `*` - matches any characters (e.g., `*.md`, `file*`, `*test*`)
- `**` - recursive globbing (e.g., `**/*.md`, `src/**/*.ts`)
- `dir/*.ext` - glob within subdirectory

**Deferred to later:**
- `?` single character match
- `[abc]` character classes

## Capabilities

### New Capabilities

_None - glob expansion enhances existing Expander stage (created in refactor-stages)._

### Modified Capabilities

- `executor`: Add glob pattern expansion to Expander stage

## Impact

**Code changes:**
- `lib/truman_shell/stages/expander.ex` - Add glob expansion logic
- Possibly new `lib/truman_shell/support/glob.ex` for pattern matching

**Behavior changes:**
- `ls *.md` → lists matching files (currently errors)
- `cat src/*.ts` → concatenates matching files (currently errors)
- `ls *.nonexistent` → "No such file or directory" (matches bash)

**Security:**
- Glob expansion MUST respect sandbox boundaries (404 principle)
- Patterns cannot match files outside sandbox root

**Test cases from real Claude Code logs:**
```
ls *.md              → README.md\nCHANGELOG.md
ls *.nonexistent     → ls: *.nonexistent: No such file or directory
cat src/*.ts         → concatenated ts files
ls **/*.md           → finds .md files in all subdirectories
cat src/**/*.ex      → concatenates all .ex files recursively
```

## Dependencies

- **Requires:** `refactor-stages` change (creates Expander stage)
