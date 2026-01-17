# Git Safety Rules

**IMPORTANT: These rules are NON-NEGOTIABLE.**

## NEVER Do These Without Explicit User Request

### Merging
- **NEVER merge PRs** - not via `gh pr merge`, not via GitHub UI suggestions
- Wait for the user to merge manually or explicitly ask you to

### Tagging
- **NEVER create tags** - no `git tag`, no release tags
- Wait for the user to tag manually or explicitly ask you to

### Force Operations
- **NEVER force push** - no `git push --force`, no `git push -f`
- **NEVER force delete** - no `git branch -D` (use `-d` if needed)
- **NEVER hard reset** - no `git reset --hard` on shared branches

### Destructive Operations
- **NEVER amend pushed commits** without explicit request
- **NEVER rebase pushed branches** without explicit request
- **NEVER delete remote branches** without explicit request

## What You CAN Do

- Create commits (when asked)
- Push to feature branches
- Create PRs
- Read git status, log, diff
- Create local branches
- Soft operations that are easily reversible

## Why This Matters

These operations are irreversible or affect shared history. The user should always be in control of:
1. When code ships to main
2. When releases are tagged
3. Any operation that rewrites history
