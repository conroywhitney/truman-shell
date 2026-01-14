defmodule TrumanShell.Commands.Tail do
  @moduledoc """
  Handler for the `tail` command - display last n lines of a file.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Helpers

  @doc """
  Returns the last n lines of a file (default: 10).

  Supports `-n NUM` and `-NUM` flag formats.

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Tail.handle(["-n", "1", "mix.exs"], context)
      iex> output
      "end\\n"

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Tail.handle(["-2", "mix.exs"], context)
      iex> output =~ "end"
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Tail.handle(["nonexistent.txt"], context)
      {:error, "tail: nonexistent.txt: No such file or directory\\n"}

  """
  @impl true
  def handle(args, context) do
    {n, path} = parse_args(args)

    case Helpers.read_file(path, context) do
      {:ok, contents} ->
        lines = String.split(contents, "\n", trim: true)
        result = lines |> Enum.take(-n) |> Enum.join("\n")
        {:ok, if(result == "", do: "", else: result <> "\n")}

      {:error, msg} ->
        {:error, Helpers.format_error("tail", msg)}
    end
  end

  # Parse tail arguments: -n NUM or -NUM or just file
  defp parse_args(["-n", n_str | rest]) do
    n = String.to_integer(n_str)
    path = List.first(rest) || "-"
    {n, path}
  end

  defp parse_args(["-" <> n_str | rest]) when n_str != "" do
    n = String.to_integer(n_str)
    path = List.first(rest) || "-"
    {n, path}
  end

  defp parse_args([path]) do
    {10, path}
  end

  defp parse_args([]) do
    {10, "-"}
  end
end
