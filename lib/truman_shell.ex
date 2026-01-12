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
        name: :ls,
        args: ["-la", "/tmp"],
        pipes: [],
        redirects: []
      }}

  """

  alias TrumanShell.Parser

  @doc """
  Parse a shell command string into a structured Command.

  Returns `{:ok, command}` on success or `{:error, reason}` on failure.
  """
  defdelegate parse(input), to: Parser
end
