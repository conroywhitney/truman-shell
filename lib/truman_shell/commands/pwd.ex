defmodule TrumanShell.Commands.Pwd do
  @moduledoc """
  Handler for the `pwd` command - print working directory.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour

  @doc """
  Returns the current working directory with a trailing newline.

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}
      iex> ctx = %Context{current_path: "/sandbox/project", sandbox_config: config}
      iex> TrumanShell.Commands.Pwd.handle([], ctx)
      {:ok, "/sandbox/project\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(_args, ctx) do
    {:ok, ctx.current_path <> "\n"}
  end
end
