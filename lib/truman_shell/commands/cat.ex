defmodule TrumanShell.Commands.Cat do
  @moduledoc """
  Handler for the `cat` command - concatenate and display files.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Support.FileIO

  @doc """
  Concatenates and displays file contents.

  Multiple files are concatenated in order. Stops on first error.

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> {:ok, output} = TrumanShell.Commands.Cat.handle(["mix.exs"], ctx)
      iex> output =~ "defmodule TrumanShell.MixProject"
      true

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> TrumanShell.Commands.Cat.handle(["nonexistent.txt"], ctx)
      {:error, "cat: nonexistent.txt: No such file or directory\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle([], %{stdin: stdin}) when is_binary(stdin) do
    # Unix behavior: `cat` with no args reads from stdin (including empty stdin)
    {:ok, stdin}
  end

  def handle([], _context) do
    # No files and no stdin context - nothing to output
    {:ok, ""}
  end

  def handle(paths, context) do
    # When file paths provided, ignore stdin (Unix behavior)
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
