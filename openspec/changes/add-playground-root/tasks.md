## Tasks: Playground Root (LLM Review Round 1)

**Source:** `.pr-reviews/conroywhitney:truman-shell/pr-11_feat:agent-mediation/rounds/01_67a2f77_8cc6be9/reviews.md`

---

### P0 - Security Blockers

- [x] **Fix symlink intermediate directory escape** ✓ d308a1d
  - `resolve_real_path/1` only checks final path, not parent symlinks
  - Attack: `ln -s /etc /sandbox/escape` → `validate_path("escape/passwd")` passes
  - Fix: Recursively resolve symlinks for each path component
  - File: `lib/truman_shell/support/sandbox.ex:198-223`
  - Flagged by: Gemini, GPT, Claude

- [x] **Fix command injection in bin/truman-shell** ✓ 47a7d0e
  - Shell script passes user input directly without escaping single quotes
  - Attack: `truman-shell execute "'; evil_code; '"`
  - Fix: Pass command via env var, not shell interpolation
  - File: `bin/truman-shell:47-48`
  - Flagged by: Claude
  - Note: Original code was actually safe (argv), but env var is clearer

### P1 - Issues

- [x] **Update openspec to use TRUMAN_DOME** ✓
  - Spec says `TRUMAN_PLAYGROUND_ROOT` / `playground_root`
  - Code uses `TRUMAN_DOME` / `sandbox_root`
  - File: `openspec/changes/add-playground-root/spec.md`
  - Flagged by: GPT, Grok

- [x] **Fix test isolation (async + env vars)** ✓ 4c068ab
  - Tests mutate `TRUMAN_DOME` via `System.put_env/2` with `async: true`
  - Fix: Changed to `async: false` with comment explaining why
  - File: `test/truman_shell/support/sandbox_test.exs:1-80`
  - Flagged by: GPT, Claude

- [x] **Document TOCTOU limitation** ✓ 4c068ab
  - Between `validate_path` and file ops, symlink could be modified
  - Inherent to userspace sandboxing
  - Added "Security Limitations" section to moduledoc
  - File: `lib/truman_shell/support/sandbox.ex` (moduledoc)
  - Flagged by: Grok, Claude

### P2 - Suggestions

- [ ] **Validate TRUMAN_DOME exists and is directory**
  - Currently returns non-existent paths without error
  - File: `lib/truman_shell/support/sandbox.ex:68-74`
  - Flagged by: Claude

- [ ] **Handle embedded $VAR in paths**
  - `expand_relative/1` only checks if path *starts* with `$`
  - Embedded variables like `/safe/$HOME/escape` pass through
  - File: `lib/truman_shell/support/sandbox.ex:175-185`
  - Flagged by: GPT, Claude

- [x] **Add symlink depth limit** ✓ d308a1d
  - Prevent infinite loops with deep/recursive symlinks
  - Added `@max_symlink_depth 10` with `:eloop` error
  - File: `lib/truman_shell/support/sandbox.ex:198-223`
  - Flagged by: Grok
  - Note: Implemented as part of P0 symlink fix

---

*Generated from LLM Review Round 1 (2026-01-24)*
