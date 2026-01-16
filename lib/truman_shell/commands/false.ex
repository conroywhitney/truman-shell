defmodule TrumanShell.Commands.False do
  @moduledoc """
  Handler for the `false` command - always fails.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour

  @doc """
  Returns error with empty message.

  ## Examples

      iex> context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}
      iex> TrumanShell.Commands.False.handle([], context)
      {:error, ""}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(_args, _context) do
    {:error, ""}
  end
end
