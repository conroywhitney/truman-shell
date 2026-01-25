defmodule TrumanShell.Commands.Find do
  @moduledoc """
  Handler for the `find` command - search for files in a directory hierarchy.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Commands.Context
  alias TrumanShell.DomePath
  alias TrumanShell.Support.Sandbox
  alias TrumanShell.Support.TreeWalker

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

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> {:ok, output} = TrumanShell.Commands.Find.handle([".", "-name", "*.exs"], ctx)
      iex> output =~ "mix.exs"
      true

      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> TrumanShell.Commands.Find.handle(["/etc", "-name", "*.conf"], ctx)
      {:error, "find: /etc: No such file or directory\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(args, ctx) do
    case parse_args(args) do
      {:ok, path, opts} ->
        find_files(path, opts, ctx)

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

  defp find_files(path, opts, %Context{} = ctx) do
    # Expand relative paths against current_path (not home_path)
    expanded = DomePath.expand(path, ctx.current_path)

    case Sandbox.validate_path(expanded, ctx.sandbox_config) do
      {:ok, safe_path} ->
        if File.dir?(safe_path) do
          do_find(safe_path, path, opts)
        else
          {:error, "find: #{path}: Not a directory\n"}
        end

      {:error, :outside_sandbox} ->
        {:error, "find: #{path}: No such file or directory\n"}
    end
  end

  defp do_find(safe_path, original_path, opts) do
    walker_opts = build_walker_opts(opts)
    entries = TreeWalker.walk(safe_path, walker_opts)

    # GNU find always includes the start point - add it as first entry
    start_entry = {safe_path, :dir}
    all_entries = [start_entry | entries]

    filtered = apply_filters(all_entries, opts)
    output = format_output(filtered, safe_path, original_path)
    {:ok, output}
  end

  defp build_walker_opts(%{maxdepth: nil}), do: []
  defp build_walker_opts(%{maxdepth: depth}), do: [maxdepth: depth]

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
    filename = DomePath.basename(path)

    regex_pattern =
      pattern
      |> Regex.escape()
      |> String.replace("\\*", ".*")
      |> String.replace("\\?", ".")

    Regex.match?(~r/^#{regex_pattern}$/, filename)
  end

  defp format_output([], _base_path, _original_path), do: "\n"

  defp format_output(files, base_path, original_path) do
    output = Enum.map_join(files, "\n", &format_entry(&1, base_path, original_path))
    output <> "\n"
  end

  # Start point is always displayed as-is
  defp format_entry(file, base_path, original_path) when file == base_path, do: original_path

  defp format_entry(file, base_path, original_path) do
    relative = DomePath.relative_to(file, base_path)
    if original_path == ".", do: "./#{relative}", else: DomePath.join(original_path, relative)
  end
end
