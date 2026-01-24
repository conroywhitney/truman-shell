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

- [ ] **Fix test isolation (async + env vars)**
  - Tests mutate `TRUMAN_DOME` via `System.put_env/2` with `async: true`
  - Fix: Remove `async: true` or add proper cleanup in `setup`/`on_exit`
  - File: `test/truman_shell/support/sandbox_test.exs:1-80`
  - Flagged by: GPT, Claude

- [ ] **Document TOCTOU limitation**
  - Between `validate_path` and file ops, symlink could be modified
  - Inherent to userspace sandboxing
  - Add clear documentation recommending OS-level sandboxing for untrusted envs
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

- [ ] **Add symlink depth limit**
  - Prevent infinite loops with deep/recursive symlinks
  - Add configurable limit (e.g., 10 levels)
  - File: `lib/truman_shell/support/sandbox.ex:140-180`
  - Flagged by: Grok

---

*Generated from LLM Review Round 1 (2026-01-24)*
