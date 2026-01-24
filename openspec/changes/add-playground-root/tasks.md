## Tasks: TRUMAN_DOME Sandbox Configuration

**PR:** #11 feat/agent-mediation
**Reviews:** `.pr-reviews/conroywhitney:truman-shell/pr-11_feat:agent-mediation/`

---

### P0 - Security Blockers (Round 1)

- [x] **Fix symlink intermediate directory escape** ✓ d308a1d
  - `resolve_real_path/1` only checks final path, not parent symlinks
  - Attack: `ln -s /etc /sandbox/escape` → `validate_path("escape/passwd")` passes
  - Fix: Recursively resolve symlinks for each path component
  - Flagged by: Gemini, GPT, Claude

- [x] **Fix command injection in bin/truman-shell** ✓ 47a7d0e
  - Shell script passes user input directly without escaping
  - Fix: Pass command via TRUMAN_CMD env var
  - Flagged by: Claude
  - Note: Original code was actually safe (argv), but env var is clearer

### P1 - Issues (Round 1)

- [x] **Update openspec to use TRUMAN_DOME** ✓ 5d836b6
  - Changed `TRUMAN_PLAYGROUND_ROOT` → `TRUMAN_DOME`
  - Changed `playground_root` → `sandbox_root`
  - Flagged by: GPT, Grok

- [x] **Fix test isolation (async + env vars)** ✓ 4c068ab
  - Tests mutate `TRUMAN_DOME` with `async: true` causing race conditions
  - Fix: Changed to `async: false` with setup/on_exit cleanup
  - Flagged by: GPT, Claude

- [x] **Document TOCTOU limitation** ✓ 4c068ab
  - Added "Security Limitations" section to Sandbox moduledoc
  - Recommends OS-level isolation for untrusted environments
  - Flagged by: Grok, Claude

### P1 - Issues (Round 2)

- [x] **Add :eloop error message** ✓ 5f510bb
  - `error_message({:error, :eloop})` returns "Too many levels of symbolic links"
  - Flagged by: GPT, Claude

- [x] **Add symlink depth limit tests** ✓ 5f510bb
  - Test for self-referential symlinks (`loop -> loop`)
  - Test for deeply nested chains (15 links, exceeds depth 10)
  - Flagged by: GPT, Claude

- [x] **Reject embedded $VAR in paths** ✓ 5f510bb
  - Paths like `safe/$HOME/escape` now rejected
  - Flagged by: GPT, Claude

- [x] **Validate current_dir is within sandbox** ✓ 5f510bb
  - If caller passes current_dir outside sandbox, returns error
  - Resolves current_dir to handle macOS /var -> /private/var symlink
  - Flagged by: GPT

- [x] **Rename current_path to parent_dir** ✓ 5f510bb
  - Clarifies semantics in `resolve_symlink_target/4`
  - Flagged by: Claude

- [x] **Fix symlink depth tracking bug** ✓ 5f510bb
  - `validate_resolved_path` was catching :eloop and falling back to Path.expand
  - Now properly propagates :eloop error
  - Discovered during TDD

### P2 - Suggestions (Deferred)

- [ ] **Validate TRUMAN_DOME exists and is directory**
  - Currently returns non-existent paths without error
  - Deferred: Would break tests that use mock paths
  - Flagged by: Claude

---

*Last updated: 2026-01-24 (Round 3)*
