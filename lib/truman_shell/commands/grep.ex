defmodule TrumanShell.Commands.Grep do
  @moduledoc """
  Handler for the `grep` command - search for patterns in files.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Commands.Context
  alias TrumanShell.DomePath
  alias TrumanShell.Support.FileIO
  alias TrumanShell.Support.Sandbox
  alias TrumanShell.Support.TreeWalker

  @default_opts %{
    recursive: false,
    line_numbers: false,
    case_insensitive: false,
    invert: false,
    after_context: 0,
    before_context: 0
  }

  @doc """
  Searches for lines matching a pattern in files.

  Supported flags:
  - `-r` - Recursive search in directories
  - `-n` - Show line numbers
  - `-i` - Case insensitive matching
  - `-v` - Invert match (show non-matching lines)
  - `-A N` - Show N lines after each match
  - `-B N` - Show N lines before each match
  - `-C N` - Show N lines of context (before and after)

  ## Examples

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> {:ok, output} = TrumanShell.Commands.Grep.handle(["defmodule", "mix.exs"], ctx)
      iex> output =~ "defmodule TrumanShell.MixProject"
      true

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> TrumanShell.Commands.Grep.handle(["pattern", "nonexistent.txt"], ctx)
      {:error, "grep: nonexistent.txt: No such file or directory\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(args, ctx) do
    case parse_args(args) do
      {:ok, opts, pattern, paths} when paths != [] ->
        do_search(opts, pattern, paths, ctx)

      {:ok, opts, pattern, []} ->
        # No paths - check for stdin (piped input)
        case ctx do
          %Context{stdin: stdin} when is_binary(stdin) ->
            result = search_content(opts, pattern, stdin, "(standard input)", false)
            {:ok, result}

          _ ->
            {:error, "grep: missing pattern or file operand\n"}
        end

      {:error, msg} ->
        {:error, msg}
    end
  end

  # Parse arguments into options, pattern, and paths
  defp parse_args(args) do
    parse_args(args, @default_opts, nil, [])
  end

  defp parse_args([], opts, pattern, paths) do
    if pattern do
      {:ok, opts, pattern, Enum.reverse(paths)}
    else
      {:error, "grep: missing pattern or file operand\n"}
    end
  end

  defp parse_args(["-r" | rest], opts, pattern, paths) do
    parse_args(rest, %{opts | recursive: true}, pattern, paths)
  end

  defp parse_args(["-n" | rest], opts, pattern, paths) do
    parse_args(rest, %{opts | line_numbers: true}, pattern, paths)
  end

  defp parse_args(["-i" | rest], opts, pattern, paths) do
    parse_args(rest, %{opts | case_insensitive: true}, pattern, paths)
  end

  defp parse_args(["-v" | rest], opts, pattern, paths) do
    parse_args(rest, %{opts | invert: true}, pattern, paths)
  end

  defp parse_args(["-A", n | rest], opts, pattern, paths) do
    case Integer.parse(n) do
      {num, ""} when num >= 0 ->
        parse_args(rest, %{opts | after_context: num}, pattern, paths)

      _ ->
        {:error, "grep: invalid context length argument\n"}
    end
  end

  defp parse_args(["-B", n | rest], opts, pattern, paths) do
    case Integer.parse(n) do
      {num, ""} when num >= 0 ->
        parse_args(rest, %{opts | before_context: num}, pattern, paths)

      _ ->
        {:error, "grep: invalid context length argument\n"}
    end
  end

  defp parse_args(["-C", n | rest], opts, pattern, paths) do
    case Integer.parse(n) do
      {num, ""} when num >= 0 ->
        parse_args(rest, %{opts | before_context: num, after_context: num}, pattern, paths)

      _ ->
        {:error, "grep: invalid context length argument\n"}
    end
  end

  defp parse_args([arg | rest], opts, nil, paths) do
    # First non-flag argument is the pattern
    parse_args(rest, opts, arg, paths)
  end

  defp parse_args([arg | rest], opts, pattern, paths) do
    # Subsequent non-flag arguments are paths
    parse_args(rest, opts, pattern, [arg | paths])
  end

  # Main search dispatcher
  defp do_search(%{recursive: true} = opts, pattern, [path], ctx) do
    search_recursive(opts, pattern, path, ctx)
  end

  defp do_search(opts, pattern, paths, ctx) do
    show_filename = length(paths) > 1
    search_files(opts, pattern, paths, ctx, show_filename)
  end

  # Recursive search in directory
  defp search_recursive(opts, pattern, path, ctx) do
    case Sandbox.validate_path(path, ctx) do
      {:ok, safe_path} ->
        if File.dir?(safe_path) do
          files = collect_files(safe_path)
          search_files_with_prefix(opts, pattern, files, safe_path, path, ctx)
        else
          search_files(opts, pattern, [path], ctx, _show_filename = true)
        end

      {:error, :outside_sandbox} ->
        {:error, FileIO.format_error("grep", "#{path}: No such file or directory")}
    end
  end

  # Collect all regular files recursively using TreeWalker
  defp collect_files(dir) do
    dir
    |> TreeWalker.walk(type: :file)
    |> Enum.map(fn {path, _type} -> path end)
    |> Enum.sort()
  end

  # Search files and prefix with relative path (for -r)
  defp search_files_with_prefix(opts, pattern, files, base_path, original_path, ctx) do
    results =
      Enum.map(files, fn file ->
        relative = DomePath.relative_to(file, base_path)

        display_path =
          if original_path == "." do
            relative
          else
            DomePath.join(original_path, relative)
          end

        case FileIO.read_file(file, ctx) do
          {:ok, contents} ->
            {:ok, search_content(opts, pattern, contents, display_path, true)}

          {:error, _msg} ->
            {:ok, ""}
        end
      end)

    combined = Enum.map_join(results, fn {:ok, m} -> m end)
    {:ok, combined}
  end

  defp search_files(opts, pattern, paths, ctx, show_filename) do
    Enum.reduce_while(paths, {:ok, ""}, fn path, {:ok, acc} ->
      case FileIO.read_file(path, ctx) do
        {:ok, contents} ->
          result = search_content(opts, pattern, contents, path, show_filename)
          {:cont, {:ok, acc <> result}}

        {:error, msg} ->
          {:halt, {:error, FileIO.format_error("grep", msg)}}
      end
    end)
  end

  # Core search logic with all options
  defp search_content(opts, pattern, contents, path, show_filename) do
    lines = String.split(contents, "\n", trim: false)
    # Remove trailing empty line from split
    lines = if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines
    indexed_lines = Enum.with_index(lines, 1)

    # Find matching line indices
    matching_indices =
      indexed_lines
      |> Enum.filter(fn {line, _idx} -> matches?(line, pattern, opts) end)
      |> MapSet.new(fn {_line, idx} -> idx end)

    # Expand with context
    lines_to_show = expand_context(matching_indices, opts, length(lines))

    # Build output
    indexed_lines
    |> Enum.filter(fn {_line, idx} -> MapSet.member?(lines_to_show, idx) end)
    |> Enum.map_join(fn {line, idx} ->
      format_line(line, idx, path, show_filename, opts)
    end)
  end

  defp matches?(line, pattern, %{case_insensitive: true, invert: invert}) do
    result = String.downcase(line) =~ String.downcase(pattern)
    if invert, do: !result, else: result
  end

  defp matches?(line, pattern, %{invert: invert}) do
    result = String.contains?(line, pattern)
    if invert, do: !result, else: result
  end

  defp expand_context(matching_indices, opts, max_line) do
    %{before_context: before, after_context: after_ctx} = opts

    Enum.reduce(matching_indices, matching_indices, fn idx, acc ->
      before_range = max(1, idx - before)..idx
      after_range = idx..min(max_line, idx + after_ctx)

      acc
      |> add_range(before_range)
      |> add_range(after_range)
    end)
  end

  defp add_range(set, range) do
    Enum.reduce(range, set, &MapSet.put(&2, &1))
  end

  defp format_line(line, idx, path, show_filename, opts) do
    prefix =
      cond do
        show_filename && opts.line_numbers -> "#{path}:#{idx}:"
        show_filename -> "#{path}:"
        opts.line_numbers -> "#{idx}:"
        true -> ""
      end

    "#{prefix}#{line}\n"
  end
end
