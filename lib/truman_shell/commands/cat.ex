defmodule TrumanShell.Commands.Cat do
  @moduledoc """
  Handler for the `cat` command - concatenate and display files.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Helpers

  @impl true
  def handle(paths, context) do
    Enum.reduce_while(paths, {:ok, ""}, fn path, {:ok, acc} ->
      case Helpers.read_file(path, context) do
        {:ok, contents} ->
          {:cont, {:ok, acc <> contents}}

        {:error, msg} ->
          {:halt, {:error, Helpers.format_error("cat", msg)}}
      end
    end)
  end
end
