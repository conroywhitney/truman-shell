defmodule TrumanShell.Commands.TreeWalker do
  @moduledoc """
  Shared utility for walking directory trees.

  Used by `find` and `grep -r` commands to recursively traverse directories
  while handling permission errors gracefully.
  """

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

      iex> entries = TrumanShell.Commands.TreeWalker.walk(File.cwd!())
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
    # Check depth limit before descending
    if maxdepth && current_depth >= maxdepth do
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

  defp process_entry(entry, dir, maxdepth, type_filter, current_depth) do
    full_path = Path.join(dir, entry)

    cond do
      File.dir?(full_path) ->
        # Always recurse into directories, but only include in results if not filtered
        children = do_walk(full_path, maxdepth, type_filter, current_depth + 1)
        if include_type?(:dir, type_filter), do: [{full_path, :dir} | children], else: children

      File.regular?(full_path) ->
        if include_type?(:file, type_filter), do: [{full_path, :file}], else: []

      true ->
        # Symlinks, devices, etc. - skip
        []
    end
  end

  defp include_type?(_type, nil), do: true
  defp include_type?(type, type), do: true
  defp include_type?(_type, _filter), do: false
end
