defmodule TrumanShell.Commands.Tail do
  @moduledoc """
  Handler for the `tail` command - display last n lines of a file.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Support.FileIO

  @doc """
  Returns the last n lines of a file (default: 10).

  Supports `-n NUM` and `-NUM` flag formats.

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> {:ok, output} = TrumanShell.Commands.Tail.handle(["-n", "1", "mix.exs"], ctx)
      iex> output
      "end\\n"

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> {:ok, output} = TrumanShell.Commands.Tail.handle(["-2", "mix.exs"], ctx)
      iex> output =~ "end"
      true

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> TrumanShell.Commands.Tail.handle(["nonexistent.txt"], ctx)
      {:error, "tail: nonexistent.txt: No such file or directory\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(args, context) do
    case FileIO.parse_line_count_args(args) do
      {:ok, n, path} ->
        case get_contents(path, context) do
          {:ok, contents} ->
            lines = String.split(contents, "\n", trim: true)
            result = lines |> Enum.take(-n) |> Enum.join("\n")
            {:ok, if(result == "", do: "", else: result <> "\n")}

          {:error, msg} ->
            {:error, FileIO.format_error("tail", msg)}
        end

      {:error, msg} ->
        {:error, FileIO.format_error("tail", msg)}
    end
  end

  # Use stdin only when no file path provided (path is "-")
  # Unix behavior: explicit file argument takes precedence over stdin
  defp get_contents("-", %{stdin: stdin}) when is_binary(stdin), do: {:ok, stdin}
  defp get_contents("-", _context), do: {:error, "missing file operand"}
  defp get_contents(path, context), do: FileIO.read_file(path, context)
end
