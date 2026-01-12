# Truman Shell 🎬

> "We accept the reality of the world with which we are presented." — The Truman Show

A simulated shell environment for AI agents. Named after "The Truman Show" — the agent lives in a convincing simulation without knowing it.

## Key Properties

1. **Convincing simulation** - Implements enough Unix commands that agents don't question it
2. **Reversible operations** - `rm` moves to `.trash`, not permanent delete
3. **Pattern-matched security** - Elixir pattern matching blocks unauthorized paths
4. **The 404 Principle** - Protected paths return "not found" not "permission denied"

## Installation

Add `truman_shell` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:truman_shell, "~> 0.3.2"}
  ]
end
```

## Usage

### Execute Commands

```elixir
# Execute a shell command (sandboxed)
{:ok, output} = TrumanShell.execute("ls lib")
# => "truman_shell.ex\ntruman_shell/\n"

# Unknown commands return bash-like errors
{:error, msg} = TrumanShell.execute("fake_command")
# => "bash: fake_command: command not found\n"

# Path traversal is blocked (404 principle)
{:error, msg} = TrumanShell.execute("ls /etc")
# => "ls: /etc: No such file or directory\n"
```

### Parse Commands

```elixir
# Simple command
{:ok, cmd} = TrumanShell.parse("ls -la /tmp")
# => %TrumanShell.Command{name: :ls, args: ["-la", "/tmp"], pipes: [], redirects: []}

# With pipes
{:ok, cmd} = TrumanShell.parse("cat file.txt | grep pattern | head -5")
# => %TrumanShell.Command{
#      name: :cat,
#      args: ["file.txt"],
#      pipes: [
#        %TrumanShell.Command{name: :grep, args: ["pattern"]},
#        %TrumanShell.Command{name: :head, args: ["-5"]}
#      ]
#    }

# With redirects
{:ok, cmd} = TrumanShell.parse("echo hello > output.txt")
# => %TrumanShell.Command{
#      name: :echo,
#      args: ["hello"],
#      redirects: [{:stdout, "output.txt"}]
#    }
```

## Roadmap

### v0.1 - Pattern Mining ✅
- Extracted 3,330 shell commands from Claude Code sessions
- Identified top 15 commands covering 90%+ of real usage
- Created 140 TDD test cases

### v0.2 - Minimal Parser ✅
- Tokenize command strings
- Parse into `%Command{}` structs
- Handle pipes, redirects, chains

### v0.3 - Executor POC ✅ (Current)
- `TrumanShell.execute/1` - parse and run in one call
- `ls` command with sandbox enforcement
- Path traversal protection (404 principle)
- Output truncation (max 200 lines)
- 145 tests passing

### v0.4 - Read Operations (Next)
- Read operations: `ls`, `cat`, `head`, `tail`, `pwd`, `cd`
- Search operations: `grep`, `find`, `wc`
- Write operations: `mkdir`, `touch`, `rm`, `mv`, `cp`, `echo`
- Piping & composition

### v0.8+ - Safety & Deception
- The 404 Principle: protected paths return "not found"
- WASM script sandboxing

## The 404 Principle

Protected paths MUST return "No such file or directory" NOT "Permission denied" to prevent probing attacks:

```
# Bad (reveals protected paths exist)
$ ls ~/.ssh
ls: /home/user/.ssh: Permission denied

# Good (security through obscurity)
$ ls ~/.ssh
ls: /home/user/.ssh: No such file or directory
```

## Architecture

```
Agent sends: "grep -r TODO . | head -5"
                    │
                    ▼
         ┌─────────────────────┐
         │   Plug.Logger       │ → log command
         ├─────────────────────┤
         │   Plug.Sanitizer    │ → normalize, detect injection
         ├─────────────────────┤
         │   Plug.Permissions  │ → check paths allowed
         ├─────────────────────┤
         │   Plug.Filesystem   │ → route to handler
         ├─────────────────────┤
         │   Plug.Responder    │ → format like real shell
         └─────────────────────┘
                    │
                    ▼
Agent receives: "src/main.ex:42:  # TODO: fix this\n..."
```

## Core Insight

**Helpful agents are more dangerous than malicious ones.** Claude escaped ClaudeBox by wanting to run Elixir — not by being adversarial. The Truman Shell must be convincing enough that helpful behavior stays within bounds.

## License

MIT
