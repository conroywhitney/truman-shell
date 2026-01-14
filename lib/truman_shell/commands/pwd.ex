defmodule TrumanShell.Commands.Pwd do
  @moduledoc """
  Handler for the `pwd` command - print working directory.
  """

  @behaviour TrumanShell.Commands.Behaviour

  @impl true
  def handle(_args, context) do
    {:ok, context.current_dir <> "\n"}
  end
end
