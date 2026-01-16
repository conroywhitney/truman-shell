defmodule TrumanShell.Commands.Which do
  @moduledoc """
  Handler for the `which` command - show command info.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Executor

  @doc """
  Returns info about the specified command(s).

  Returns `{:ok, output}` if all commands are found, `{:error, output}` if any
  command is not found (matching Unix `which` exit code behavior for chaining).

  ## Examples

      iex> context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}
      iex> TrumanShell.Commands.Which.handle(["ls"], context)
      {:ok, "ls: TrumanShell builtin\\n"}

      iex> context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}
      iex> TrumanShell.Commands.Which.handle(["notreal"], context)
      {:error, "notreal not found\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle([], _context) do
    {:error, "usage: which command ...\n"}
  end

  def handle(args, _context) do
    known = Executor.supported_commands()
    results = Enum.map(args, &command_info(&1, known))

    output = Enum.map_join(results, "", fn {_, msg} -> msg end)
    all_found? = Enum.all?(results, fn {found?, _} -> found? end)

    if all_found?, do: {:ok, output}, else: {:error, output}
  end

  defp command_info(name, known) do
    if name in known do
      {true, "#{name}: TrumanShell builtin\n"}
    else
      {false, "#{name} not found\n"}
    end
  end
end
