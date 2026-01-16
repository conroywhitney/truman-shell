defmodule TrumanShell.Commands.Which do
  @moduledoc """
  Handler for the `which` command - show command info.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour

  @known_commands ~w(cat cd cp echo find grep head ls mkdir mv pwd rm tail touch wc which date true false)

  @doc """
  Returns info about the specified command(s).

  ## Examples

      iex> context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}
      iex> TrumanShell.Commands.Which.handle(["ls"], context)
      {:ok, "ls: TrumanShell builtin\\n"}

      iex> context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}
      iex> TrumanShell.Commands.Which.handle(["notreal"], context)
      {:ok, "notreal not found\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle([], _context) do
    {:error, "usage: which command ...\n"}
  end

  def handle(args, _context) do
    output = Enum.map_join(args, "", &command_info/1)

    {:ok, output}
  end

  defp command_info(name) when name in @known_commands do
    "#{name}: TrumanShell builtin\n"
  end

  defp command_info(name) do
    "#{name} not found\n"
  end
end
