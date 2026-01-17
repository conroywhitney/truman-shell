defmodule TrumanShell.Support.TreeWalker do
  @moduledoc """
  Shared utility for walking directory trees.

  Used by `find` and `grep -r` commands to recursively traverse directories
  while handling permission errors gracefully.

  ## Security

  Uses `File.lstat/1` (not `File.stat/1`) to determine entry types. This is
  critical for sandbox security: symlinks are detected and skipped rather than
  followed, preventing directory traversal attacks via symlinks pointing outside
  the sandbox.

  ## Safety Limits

  Hard maximum depth of 100 levels is enforced to prevent stack overflow on
  maliciously deep directory structures. The `:maxdepth` option can set a lower
  limit but cannot exceed this safety ceiling.
  """

  # Hard maximum depth to prevent stack overflow
  @max_depth_limit 100

  @type entry :: {String.t(), :file | :dir}
  @type option :: {:maxdepth, pos_integer()} | {:type, :file | :dir}

  @doc """
  Walks a directory tree, returning a list of `{path, type}` tuples.

  - `path` is the full path to the entry
  - `type` is `:file` or `:dir`

  ## Options

  - `:maxdepth` - Maximum depth to traverse (1 = immediate children only)
  - `:type` - Filter results by type (`:file` or `:dir`)

  Handles permission errors gracefully by skipping inaccessible directories.

  ## Examples

      iex> entries = TrumanShell.Support.TreeWalker.walk(File.cwd!())
      iex> Enum.any?(entries, fn {path, _} -> path =~ "mix.exs" end)
      true

  """
  @spec walk(String.t(), [option()]) :: [entry()]
  def walk(dir, opts \\ []) do
    maxdepth = Keyword.get(opts, :maxdepth)
    type_filter = Keyword.get(opts, :type)
    do_walk(dir, maxdepth, type_filter, 0)
  end

  defp do_walk(dir, maxdepth, type_filter, current_depth) do
    # Check depth limits before descending:
    # - User's maxdepth option (if provided)
    # - Hard safety limit to prevent stack overflow
    effective_limit = if maxdepth, do: min(maxdepth, @max_depth_limit), else: @max_depth_limit

    if current_depth >= effective_limit do
      []
    else
      case File.ls(dir) do
        {:ok, entries} ->
          Enum.flat_map(entries, &process_entry(&1, dir, maxdepth, type_filter, current_depth))

        {:error, _reason} ->
          # Permission denied or other errors - skip gracefully
          []
      end
    end
  end

  # Uses lstat (not stat) to prevent symlink traversal attacks.
  # File.dir?/File.regular? follow symlinks; lstat does not.
  defp process_entry(entry, dir, maxdepth, type_filter, current_depth) do
    full_path = Path.join(dir, entry)

    case File.lstat(full_path) do
      {:ok, %File.Stat{type: :directory}} ->
        # Real directory - safe to recurse
        children = do_walk(full_path, maxdepth, type_filter, current_depth + 1)
        if include_type?(:dir, type_filter), do: [{full_path, :dir} | children], else: children

      {:ok, %File.Stat{type: :regular}} ->
        # Real file
        if include_type?(:file, type_filter), do: [{full_path, :file}], else: []

      {:ok, %File.Stat{type: :symlink}} ->
        # SECURITY: Skip symlinks entirely to prevent sandbox escape
        []

      {:ok, _other} ->
        # Devices, sockets, etc. - skip
        []

      {:error, _reason} ->
        # Permission denied, vanished file, etc. - skip gracefully
        []
    end
  end

  defp include_type?(_type, nil), do: true
  defp include_type?(type, type), do: true
  defp include_type?(_type, _filter), do: false
end
