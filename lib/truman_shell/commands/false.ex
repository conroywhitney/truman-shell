defmodule TrumanShell.Commands.False do
  @moduledoc """
  Handler for the `false` command - always fails.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour

  @doc """
  Returns error with empty message.

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}
      iex> ctx = %Context{current_path: "/sandbox", sandbox_config: config}
      iex> TrumanShell.Commands.False.handle([], ctx)
      {:error, ""}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(_args, _context) do
    {:error, ""}
  end
end
