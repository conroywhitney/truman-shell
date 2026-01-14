defmodule TrumanShell.Commands.Head do
  @moduledoc """
  Handler for the `head` command - display first n lines of a file.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Helpers

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
  @impl true
  def handle(args, context) do
    case parse_args(args) do
      {:ok, n, path} ->
        case Helpers.read_file(path, context) do
          {:ok, contents} ->
            lines = String.split(contents, "\n")
            result = lines |> Enum.take(n) |> Enum.join("\n")
            {:ok, if(result == "", do: "", else: result <> "\n")}

          {:error, msg} ->
            {:error, Helpers.format_error("head", msg)}
        end

      {:error, msg} ->
        {:error, Helpers.format_error("head", msg)}
    end
  end

  # Parse head arguments: -n NUM or -NUM or just file
  defp parse_args(["-n", n_str | rest]) do
    case parse_int(n_str) do
      {:ok, n} -> {:ok, n, List.first(rest) || "-"}
      :error -> {:error, "invalid number of lines: '#{n_str}'"}
    end
  end

  defp parse_args(["-" <> n_str | rest]) when n_str != "" do
    case parse_int(n_str) do
      {:ok, n} -> {:ok, n, List.first(rest) || "-"}
      :error -> {:error, "invalid number of lines: '-#{n_str}'"}
    end
  end

  defp parse_args([path]) do
    {:ok, 10, path}
  end

  defp parse_args([]) do
    {:ok, 10, "-"}
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end
end
