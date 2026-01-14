defmodule TrumanShell.Commands.Find do
  @moduledoc """
  Handler for the `find` command - search for files in a directory hierarchy.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Sanitizer

  @default_opts %{
    name_pattern: nil,
    type: nil,
    maxdepth: nil
  }

  @doc """
  Finds files matching criteria in a directory tree.

  Supported flags:
  - `-name PATTERN` - Match filename against glob pattern
  - `-type f` - Match only files
  - `-type d` - Match only directories
  - `-maxdepth N` - Descend at most N levels

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Find.handle([".", "-name", "*.exs"], context)
      iex> output =~ "mix.exs"
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Find.handle(["/etc", "-name", "*.conf"], context)
      {:error, "find: /etc: No such file or directory\\n"}

  """
  @impl true
  def handle(args, context) do
    case parse_args(args) do
      {:ok, path, opts} ->
        find_files(path, opts, context)

      {:error, msg} ->
        {:error, msg}
    end
  end

  # Parse arguments
  defp parse_args([]), do: {:error, "find: missing path argument\n"}

  defp parse_args([path | rest]) do
    parse_opts(rest, path, @default_opts)
  end

  defp parse_opts([], path, opts), do: {:ok, path, opts}

  defp parse_opts(["-name", pattern | rest], path, opts) do
    parse_opts(rest, path, %{opts | name_pattern: pattern})
  end

  defp parse_opts(["-name"], _path, _opts) do
    {:error, "find: missing argument to '-name'\n"}
  end

  defp parse_opts(["-type", type | rest], path, opts) when type in ["f", "d"] do
    parse_opts(rest, path, %{opts | type: type})
  end

  defp parse_opts(["-type", invalid | _rest], _path, _opts) do
    {:error, "find: Unknown argument to -type: #{invalid}\n"}
  end

  defp parse_opts(["-type"], _path, _opts) do
    {:error, "find: missing argument to '-type'\n"}
  end

  defp parse_opts(["-maxdepth", n | rest], path, opts) do
    case Integer.parse(n) do
      {num, ""} when num >= 0 -> parse_opts(rest, path, %{opts | maxdepth: num})
      _ -> {:error, "find: Invalid argument '#{n}' to -maxdepth\n"}
    end
  end

  defp parse_opts(["-maxdepth"], _path, _opts) do
    {:error, "find: missing argument to '-maxdepth'\n"}
  end

  defp parse_opts([unknown | _rest], _path, _opts) do
    {:error, "find: unknown predicate '#{unknown}'\n"}
  end

  defp find_files(path, opts, context) do
    case Sanitizer.validate_path(path, context.sandbox_root) do
      {:ok, safe_path} ->
        if File.dir?(safe_path) do
          entries = walk_tree(safe_path, opts, 0)
          filtered = apply_filters(entries, opts)
          output = format_output(filtered, safe_path, path)
          {:ok, output}
        else
          {:error, "find: #{path}: Not a directory\n"}
        end

      {:error, :outside_sandbox} ->
        {:error, "find: #{path}: No such file or directory\n"}
    end
  end

  # Walk tree with depth tracking
  defp walk_tree(dir, opts, current_depth) do
    # Check maxdepth before recursing
    if opts.maxdepth && current_depth >= opts.maxdepth do
      []
    else
      dir
      |> File.ls!()
      |> Enum.flat_map(fn entry ->
        full_path = Path.join(dir, entry)
        is_dir = File.dir?(full_path)

        cond do
          is_dir ->
            [{full_path, :dir} | walk_tree(full_path, opts, current_depth + 1)]

          File.regular?(full_path) ->
            [{full_path, :file}]

          true ->
            []
        end
      end)
    end
  end

  defp apply_filters(entries, opts) do
    entries
    |> filter_by_type(opts.type)
    |> filter_by_name(opts.name_pattern)
    |> Enum.map(fn {path, _type} -> path end)
    |> Enum.sort()
  end

  defp filter_by_type(entries, nil), do: entries
  defp filter_by_type(entries, "f"), do: Enum.filter(entries, fn {_, type} -> type == :file end)
  defp filter_by_type(entries, "d"), do: Enum.filter(entries, fn {_, type} -> type == :dir end)

  defp filter_by_name(entries, nil), do: entries

  defp filter_by_name(entries, pattern) do
    Enum.filter(entries, fn {path, _type} -> matches_pattern?(path, pattern) end)
  end

  defp matches_pattern?(path, pattern) do
    filename = Path.basename(path)

    regex_pattern =
      pattern
      |> Regex.escape()
      |> String.replace("\\*", ".*")
      |> String.replace("\\?", ".")

    Regex.match?(~r/^#{regex_pattern}$/, filename)
  end

  defp format_output([], _base_path, _original_path), do: "\n"

  defp format_output(files, base_path, original_path) do
    output =
      Enum.map_join(files, "\n", fn file ->
        relative = Path.relative_to(file, base_path)

        if original_path == "." do
          "./#{relative}"
        else
          Path.join(original_path, relative)
        end
      end)

    output <> "\n"
  end
end
