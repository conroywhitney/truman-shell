# Agent Development Guide

> Best practices for AI agents working on Truman Shell

## Development Workflow

### Starting New Work

1. **Use `/openspec:proposal`** to capture requirements before implementation
   - Don't just start coding — spec it first
   - This creates traceable artifacts linking intent → implementation

2. **After merging**, use `/openspec:archive` to incorporate completed work
   - Links the spec to the actual implementation
   - Builds project history

### Test-Driven Development (TDD)

**Always follow Red-Green-Refactor:**

1. **Red** — Write a failing test that describes the desired behavior
2. **Green** — Write the minimum code to make it pass
3. **Refactor** — Clean up while keeping tests green

```elixir
# Example TDD flow for v0.3 executor

# 1. RED: Write failing test
test "executes ls command and returns file listing" do
  {:ok, command} = TrumanShell.parse("ls")
  assert {:ok, output} = TrumanShell.Executor.run(command)
  assert is_binary(output)
end

# 2. GREEN: Minimal implementation
def run(%Command{name: :cmd_ls}), do: {:ok, "file.txt\n"}

# 3. REFACTOR: Real implementation with proper structure
```

### Doctests for Public APIs

Use doctests where they serve as **living documentation**:

```elixir
@doc """
Executes a parsed command in the sandbox.

## Examples

    iex> {:ok, cmd} = TrumanShell.parse("ls")
    iex> {:ok, output} = TrumanShell.Executor.run(cmd)
    iex> is_binary(output)
    true

"""
def run(%Command{} = command), do: # ...
```

**When to use doctests:**
- Public API functions that benefit from usage examples
- Contract enforcement (if the API changes, doctests fail)
- Simple, deterministic outputs

**When NOT to use doctests:**
- Complex setup required
- Non-deterministic outputs (timestamps, random data)
- Internal/private functions

## Git Practices

### Commit Early and Often

**Atomic commits > big batches**

- Each commit = one logical unit of work
- Provenance and understandability are paramount
- We use **squash merges** to main, so messy feature branches are fine

### Before Every Commit

```bash
mix format && mix test && mix credo
```

If any fail, fix before committing.

### Never Force Push

**Do NOT use `--force-push`**

If history rewriting seems necessary:
1. Ask the HITL (Human In The Loop)
2. Let them decide and execute if appropriate
3. Prefer a messy double-commit over rewritten history

### Commit Message Format

```
<type>: <short description>

<optional body explaining why, not what>
```

Types: `feat`, `fix`, `test`, `docs`, `refactor`, `chore`

## Decision Points

### When Uncertain, Ask

**Speed is good when confident. But...**

Making a choice and reverting later costs more time/energy/tokens than pausing to collaborate.

**Ask the HITL when:**
- Multiple valid approaches exist
- The choice affects architecture
- You're about to delete/rewrite significant code
- The requirement is ambiguous

**Just do it when:**
- The path is clear and well-defined
- It's easily reversible
- Tests will catch any mistakes

## Commands Reference

```bash
# Development
mix test              # Run all tests
mix test --only focus # Run focused tests
mix format            # Format code
mix credo             # Static analysis

# Git
git status            # Check state before commit
git add -p            # Stage interactively (atomic commits)
git commit            # Commit (never --amend without asking)
git push              # Push (never --force)
```

## The Prime Directive

> Have fun with it :)

This is an experimental project exploring AI sandboxing. Creativity and exploration are encouraged. When in doubt, write a test and try it out.
