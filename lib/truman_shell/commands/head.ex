defmodule TrumanShell.Commands.Head do
  @moduledoc """
  Handler for the `head` command - display first n lines of a file.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Commands.FileIO

  @doc """
  Returns the first n lines of a file (default: 10).

  Supports `-n NUM` and `-NUM` flag formats.

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Head.handle(["-n", "1", "mix.exs"], context)
      iex> output
      "defmodule TrumanShell.MixProject do\\n"

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Head.handle(["-2", "mix.exs"], context)
      iex> output =~ "defmodule TrumanShell.MixProject"
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Head.handle(["nonexistent.txt"], context)
      {:error, "head: nonexistent.txt: No such file or directory\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(args, context) do
    case FileIO.parse_line_count_args(args) do
      {:ok, n, path} ->
        case get_contents(path, context) do
          {:ok, contents} ->
            lines = String.split(contents, "\n")
            result = lines |> Enum.take(n) |> Enum.join("\n")
            {:ok, if(result == "", do: "", else: result <> "\n")}

          {:error, msg} ->
            {:error, FileIO.format_error("head", msg)}
        end

      {:error, msg} ->
        {:error, FileIO.format_error("head", msg)}
    end
  end

  # Use stdin only when no file path provided (path is "-")
  # Unix behavior: explicit file argument takes precedence over stdin
  defp get_contents("-", %{stdin: stdin}) when is_binary(stdin), do: {:ok, stdin}
  defp get_contents("-", _context), do: {:error, "missing file operand"}
  defp get_contents(path, context), do: FileIO.read_file(path, context)
end
