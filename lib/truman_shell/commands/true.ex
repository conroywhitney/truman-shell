defmodule TrumanShell.Commands.True do
  @moduledoc """
  Handler for the `true` command - always succeeds.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour

  @doc """
  Returns success with empty output.

  ## Examples

      iex> context = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}
      iex> TrumanShell.Commands.True.handle([], context)
      {:ok, ""}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(_args, _context) do
    {:ok, ""}
  end
end
