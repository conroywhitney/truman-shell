# Design: Glob Expansion

## Context

TrumanShell's Expander stage currently handles tilde expansion (`~` → sandbox_root). The v0.5.1 refactor established a clean pipeline: `Tokenizer → Parser → Expander → Executor → Redirector`.

AI agents frequently use glob patterns (`*.md`, `src/*.ts`) which currently pass through as literal strings, causing "file not found" errors. This is one of the most common gaps vs real bash.

**Current state:**
- `ls *.md` → "ls: *.md: No such file or directory" (pattern passed literally)
- Expander only handles tilde, not globs

**Stakeholders:** AI agents (Claude Code), developers testing TrumanShell

## Goals / Non-Goals

**Goals:**
- Expand `*` patterns to matching files within sandbox
- Match bash behavior for no-match case (return literal pattern or error depending on command)
- Keep expansion sandboxed (no matches outside sandbox_root)
- Support common patterns: `*.ext`, `prefix*`, `*suffix`, `dir/*.ext`
- Support `**` recursive globbing (e.g., `**/*.md`, `src/**/*.ts`)

**Non-Goals:**
- `?` single-character matching (defer to later)
- `[abc]` character classes (defer to later)
- Brace expansion `{a,b}` (defer to later)
- Glob in redirect targets (e.g., `> *.txt` is undefined behavior in bash anyway)

## Decisions

### 1. Expand in Expander stage (not Executor)

**Decision:** Add glob expansion to `Expander.expand_arg/2`

**Rationale:**
- Follows POSIX shell model: expansions happen before command execution
- Expander already handles tilde, so expansions are co-located
- Commands receive expanded file list, don't need glob awareness
- LLM reviewers (Gemini, Grok, Claude) confirmed this in PR #9 review

**Alternatives considered:**
- Per-command glob handling → rejected: duplicates logic, commands shouldn't know about globs

### 2. Use Path.wildcard/2 with sandbox constraint and depth limit

**Decision:** Use `Path.wildcard(pattern, match_dot: false)` then filter to sandbox. For `**` patterns, enforce max depth of 100 (consistent with TreeWalker).

**Rationale:**
- Elixir's Path.wildcard handles `*` and `**` matching correctly
- `match_dot: false` matches bash default (ignore dotfiles unless pattern starts with `.`)
- Post-filter ensures no matches outside sandbox (defense in depth)
- Depth limit of 100 prevents runaway recursion (matches TreeWalker's `@max_depth_limit`)

**Depth limiting strategy:**
- Count path segments relative to glob base directory
- Filter out results exceeding 100 levels deep
- Consistent with `find` command and TreeWalker behavior

**Alternatives considered:**
- Custom pattern matching → rejected: reinventing the wheel, Path.wildcard is battle-tested
- Pre-filter pattern to sandbox path → rejected: still need post-filter for symlink edge cases
- No depth limit → rejected: inconsistent with TreeWalker, potential DoS vector

### 3. Resolve pattern relative to current_dir

**Decision:** Glob patterns resolve relative to `context.current_dir`, not sandbox_root

**Rationale:**
- Matches bash behavior: `ls *.md` looks in current directory
- Tilde already expanded before glob, so `~/*.md` works correctly
- `dir/*.md` expands relative to current_dir

**Implementation:**
```elixir
def expand_glob(pattern, context) do
  full_pattern = Path.join(context.current_dir, pattern)
  Path.wildcard(full_pattern, match_dot: false)
  |> Enum.filter(&in_sandbox?(&1, context.sandbox_root))
end
```

### 4. No-match behavior: return original pattern

**Decision:** If glob matches nothing, return the original pattern unchanged

**Rationale:**
- Matches bash default behavior (nullglob off)
- Lets commands handle "file not found" naturally
- `ls *.nonexistent` → ls receives literal `*.nonexistent` → "No such file or directory"

**Alternatives considered:**
- Return empty list → rejected: breaks `cat *.md` semantics (would output nothing, not error)
- Raise error → rejected: doesn't match bash behavior

### 5. Only expand if pattern contains glob characters

**Decision:** Only attempt expansion if arg contains `*` (covers both `*` and `**`)

**Rationale:**
- Avoids unnecessary Path.wildcard calls for normal args
- Simple check: `String.contains?(arg, "*")`
- `**` is detected by the same check (contains `*`)
- Future versions can add `?` and `[` checks

### 6. Return sorted matches

**Decision:** Sort glob matches alphabetically

**Rationale:**
- Matches bash behavior
- Deterministic output for testing
- `Path.wildcard` already returns sorted, but explicit sort for safety

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Symlinks escaping sandbox | Post-filter all matches through `Sandbox.validate_path/2` |
| Performance with many files | Glob is O(n) directory scan; acceptable for sandbox size |
| `**` recursive traversal | Sandbox is bounded; Path.wildcard handles efficiently |
| Glob in quoted strings | Parser should preserve quotes; only expand unquoted args (verify in tests) |
| Ambiguous patterns like `a*b*c` | Path.wildcard handles correctly; add test case |

## Open Questions

1. **Quoted glob preservation**: Does the parser already preserve `"*.md"` as a literal? Need to verify.
2. **Order of expansion**: Should glob run before or after tilde? (Probably after, so `~/*.md` works)
3. **Empty dir edge case**: What if current_dir doesn't exist? Path.wildcard returns `[]` → pattern unchanged.
