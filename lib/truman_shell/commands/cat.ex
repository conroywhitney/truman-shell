defmodule TrumanShell.Commands.Cat do
  @moduledoc """
  Handler for the `cat` command - concatenate and display files.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.FileIO

  @doc """
  Concatenates and displays file contents.

  Multiple files are concatenated in order. Stops on first error.

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Cat.handle(["mix.exs"], context)
      iex> output =~ "defmodule TrumanShell.MixProject"
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Cat.handle(["nonexistent.txt"], context)
      {:error, "cat: nonexistent.txt: No such file or directory\\n"}

  """
  @impl true
  def handle(paths, context) do
    Enum.reduce_while(paths, {:ok, ""}, fn path, {:ok, acc} ->
      case FileIO.read_file(path, context) do
        {:ok, contents} ->
          {:cont, {:ok, acc <> contents}}

        {:error, msg} ->
          {:halt, {:error, FileIO.format_error("cat", msg)}}
      end
    end)
  end
end
