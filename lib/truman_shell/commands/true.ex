defmodule TrumanShell.Commands.True do
  @moduledoc """
  Handler for the `true` command - always succeeds.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour

  @doc """
  Returns success with empty output.

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}
      iex> ctx = %Context{current_path: "/sandbox", sandbox_config: config}
      iex> TrumanShell.Commands.True.handle([], ctx)
      {:ok, ""}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(_args, _context) do
    {:ok, ""}
  end
end
