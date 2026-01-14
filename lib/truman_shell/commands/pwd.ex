defmodule TrumanShell.Commands.Pwd do
  @moduledoc """
  Handler for the `pwd` command - print working directory.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour

  @doc """
  Returns the current working directory with a trailing newline.

  ## Examples

      iex> context = %{sandbox_root: "/sandbox", current_dir: "/sandbox/project"}
      iex> TrumanShell.Commands.Pwd.handle([], context)
      {:ok, "/sandbox/project\\n"}

      iex> context = %{sandbox_root: "/home/user", current_dir: "/home/user"}
      iex> TrumanShell.Commands.Pwd.handle([], context)
      {:ok, "/home/user\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(_args, context) do
    {:ok, context.current_dir <> "\n"}
  end
end
