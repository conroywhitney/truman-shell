defmodule TrumanShell.Commands.Wc do
  @moduledoc """
  Handler for the `wc` command - word, line, and character count.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.FileIO

  @doc """
  Counts lines, words, and characters in files.

  Output format matches classic wc: lines words chars filename

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Wc.handle(["mix.exs"], context)
      iex> output =~ "mix.exs"
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Wc.handle(["nonexistent.txt"], context)
      {:error, "wc: nonexistent.txt: No such file or directory\\n"}

  """
  @impl true
  def handle([], _context) do
    {:error, "wc: missing file operand\n"}
  end

  def handle(paths, context) do
    count_files(paths, context)
  end

  defp count_files(paths, context) do
    results =
      Enum.map(paths, fn path ->
        case count_file(path, context) do
          {:ok, counts} -> {:ok, path, counts}
          {:error, msg} -> {:error, path, msg}
        end
      end)

    # Check for any errors
    case Enum.find(results, fn {status, _, _} -> status == :error end) do
      {:error, _path, msg} ->
        {:error, FileIO.format_error("wc", msg)}

      nil ->
        output = format_output(results)
        {:ok, output}
    end
  end

  defp count_file(path, context) do
    case FileIO.read_file(path, context) do
      {:ok, contents} ->
        lines = count_lines(contents)
        words = count_words(contents)
        chars = String.length(contents)
        {:ok, {lines, words, chars}}

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp count_lines(contents) do
    contents
    |> String.split("\n", trim: false)
    |> length()
    |> Kernel.-(1)
    |> max(0)
  end

  defp count_words(contents) do
    contents
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  defp format_output(results) do
    lines =
      Enum.map(results, fn {:ok, path, {lines, words, chars}} ->
        format_line(lines, words, chars, path)
      end)

    output = Enum.join(lines, "\n")

    # Add total line if multiple files
    if length(results) > 1 do
      {total_lines, total_words, total_chars} =
        Enum.reduce(results, {0, 0, 0}, fn {:ok, _, {l, w, c}}, {al, aw, ac} ->
          {al + l, aw + w, ac + c}
        end)

      output <> "\n" <> format_line(total_lines, total_words, total_chars, "total") <> "\n"
    else
      output <> "\n"
    end
  end

  defp format_line(lines, words, chars, name) do
    # Right-align numbers in 8-character columns (like real wc)
    "#{pad(lines)} #{pad(words)} #{pad(chars)} #{name}"
  end

  defp pad(num), do: String.pad_leading(Integer.to_string(num), 8)
end
