defmodule TrumanShell do
  @moduledoc """
  TrumanShell - A simulated shell environment for AI agents.

  Named after "The Truman Show" - the agent lives in a convincing
  simulation without knowing it.

  ## Key Properties

  1. **Convincing simulation** - Implements enough Unix commands that agents don't question it
  2. **Reversible operations** - `rm` moves to `.trash`, not permanent delete
  3. **Pattern-matched security** - Elixir pattern matching blocks unauthorized paths
  4. **The 404 Principle** - Protected paths return "not found" not "permission denied"

  ## Example

      iex> TrumanShell.parse("ls -la /tmp")
      {:ok, %TrumanShell.Command{
        name: :cmd_ls,
        args: ["-la", "/tmp"],
        pipes: [],
        redirects: []
      }}

  """

  alias TrumanShell.Parser

  @doc """
  Parse a shell command string into a structured Command.

  Returns `{:ok, command}` on success or `{:error, reason}` on failure.

  ## Simple Commands

      iex> TrumanShell.parse("pwd")
      {:ok, %TrumanShell.Command{name: :cmd_pwd, args: []}}

      iex> TrumanShell.parse("ls -la /tmp")
      {:ok, %TrumanShell.Command{name: :cmd_ls, args: ["-la", "/tmp"]}}

      iex> TrumanShell.parse("cd ~")
      {:ok, %TrumanShell.Command{name: :cmd_cd, args: ["~"]}}

  ## Pipes

      iex> {:ok, cmd} = TrumanShell.parse("cat file.txt | grep pattern")
      iex> cmd.name
      :cmd_cat
      iex> cmd.args
      ["file.txt"]
      iex> length(cmd.pipes)
      1
      iex> hd(cmd.pipes).name
      :cmd_grep

      iex> {:ok, cmd} = TrumanShell.parse("ls | grep foo | head -5")
      iex> cmd.name
      :cmd_ls
      iex> length(cmd.pipes)
      2

  ## Redirects

      iex> {:ok, cmd} = TrumanShell.parse("echo hello > output.txt")
      iex> cmd.redirects
      [{:stdout, "output.txt"}]

      iex> {:ok, cmd} = TrumanShell.parse("echo more >> log.txt")
      iex> cmd.redirects
      [{:stdout_append, "log.txt"}]

      iex> {:ok, cmd} = TrumanShell.parse("make 2> errors.log")
      iex> cmd.redirects
      [{:stderr, "errors.log"}]

  ## Quoted Strings

      iex> {:ok, cmd} = TrumanShell.parse("echo \\"hello world\\"")
      iex> cmd.args
      ["hello world"]

      iex> {:ok, cmd} = TrumanShell.parse("grep 'pattern with spaces' file.txt")
      iex> cmd.args
      ["pattern with spaces", "file.txt"]

  ## Error Cases

      iex> TrumanShell.parse("")
      {:error, "Empty command"}

      iex> TrumanShell.parse("   ")
      {:error, "Empty command"}

  """
  defdelegate parse(input), to: Parser
end
