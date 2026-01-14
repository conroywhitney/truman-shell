defmodule TrumanShell.Commands.Grep do
  @moduledoc """
  Handler for the `grep` command - search for patterns in files.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.FileIO

  @doc """
  Searches for lines matching a pattern in files.

  Returns lines containing the pattern, one per line.

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Grep.handle(["defmodule", "mix.exs"], context)
      iex> output =~ "defmodule TrumanShell.MixProject"
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Grep.handle(["pattern", "nonexistent.txt"], context)
      {:error, "grep: nonexistent.txt: No such file or directory\\n"}

  """
  @impl true
  def handle([pattern | paths], context) when paths != [] do
    case search_files(pattern, paths, context) do
      {:ok, matches} -> {:ok, matches}
      {:error, msg} -> {:error, msg}
    end
  end

  def handle(_, _context) do
    {:error, "grep: missing pattern or file operand\n"}
  end

  defp search_files(pattern, paths, context) do
    Enum.reduce_while(paths, {:ok, ""}, fn path, {:ok, acc} ->
      case search_file(pattern, path, context) do
        {:ok, matches} ->
          {:cont, {:ok, acc <> matches}}

        {:error, msg} ->
          {:halt, {:error, FileIO.format_error("grep", msg)}}
      end
    end)
  end

  defp search_file(pattern, path, context) do
    case FileIO.read_file(path, context) do
      {:ok, contents} ->
        matches =
          contents
          |> String.split("\n")
          |> Enum.filter(&String.contains?(&1, pattern))
          |> Enum.map_join(&(&1 <> "\n"))

        {:ok, matches}

      {:error, msg} ->
        {:error, msg}
    end
  end
end
