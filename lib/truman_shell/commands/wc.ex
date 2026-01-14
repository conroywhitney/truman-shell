defmodule TrumanShell.Commands.Wc do
  @moduledoc """
  Handler for the `wc` command - word, line, and character count.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Commands.FileIO

  @default_opts %{
    lines: false,
    words: false,
    chars: false
  }

  @doc """
  Counts lines, words, and characters in files.

  Supported flags:
  - `-l` - Show only line count
  - `-w` - Show only word count
  - `-c` - Show only byte/character count

  Without flags, shows all counts. Flags can be combined.

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Wc.handle(["mix.exs"], context)
      iex> output =~ "mix.exs"
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Wc.handle(["nonexistent.txt"], context)
      {:error, "wc: nonexistent.txt: No such file or directory\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(args, context) do
    case parse_args(args) do
      {:ok, opts, paths} when paths != [] ->
        count_files(opts, paths, context)

      {:ok, _opts, []} ->
        {:error, "wc: missing file operand\n"}
    end
  end

  defp parse_args(args) do
    parse_args(args, @default_opts, [])
  end

  defp parse_args([], opts, paths) do
    # If no specific flags, show all
    opts =
      if !opts.lines && !opts.words && !opts.chars do
        %{opts | lines: true, words: true, chars: true}
      else
        opts
      end

    {:ok, opts, Enum.reverse(paths)}
  end

  defp parse_args(["-l" | rest], opts, paths) do
    parse_args(rest, %{opts | lines: true}, paths)
  end

  defp parse_args(["-w" | rest], opts, paths) do
    parse_args(rest, %{opts | words: true}, paths)
  end

  defp parse_args(["-c" | rest], opts, paths) do
    parse_args(rest, %{opts | chars: true}, paths)
  end

  defp parse_args([path | rest], opts, paths) do
    parse_args(rest, opts, [path | paths])
  end

  defp count_files(opts, paths, context) do
    results =
      Enum.map(paths, fn path ->
        case count_file(path, context) do
          {:ok, counts} -> {:ok, path, counts}
          {:error, msg} -> {:error, path, msg}
        end
      end)

    case Enum.find(results, fn {status, _, _} -> status == :error end) do
      {:error, _path, msg} ->
        {:error, FileIO.format_error("wc", msg)}

      nil ->
        output = format_output(results, opts)
        {:ok, output}
    end
  end

  defp count_file(path, context) do
    case FileIO.read_file(path, context) do
      {:ok, contents} ->
        lines = count_lines(contents)
        words = count_words(contents)
        # wc -c counts BYTES, not graphemes (matches GNU wc behavior)
        bytes = byte_size(contents)
        {:ok, {lines, words, bytes}}

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

  defp format_output(results, opts) do
    lines =
      Enum.map(results, fn {:ok, path, counts} ->
        format_line(counts, path, opts)
      end)

    output = Enum.join(lines, "\n")

    if length(results) > 1 do
      {total_lines, total_words, total_chars} =
        Enum.reduce(results, {0, 0, 0}, fn {:ok, _, {l, w, c}}, {al, aw, ac} ->
          {al + l, aw + w, ac + c}
        end)

      output <> "\n" <> format_line({total_lines, total_words, total_chars}, "total", opts) <> "\n"
    else
      output <> "\n"
    end
  end

  defp format_line({lines, words, chars}, name, opts) do
    parts =
      []
      |> maybe_add(opts.lines, lines)
      |> maybe_add(opts.words, words)
      |> maybe_add(opts.chars, chars)
      |> Enum.reverse()

    Enum.join(parts, " ") <> " #{name}"
  end

  defp maybe_add(list, true, value), do: [pad(value) | list]
  defp maybe_add(list, false, _value), do: list

  defp pad(num), do: String.pad_leading(Integer.to_string(num), 8)
end
