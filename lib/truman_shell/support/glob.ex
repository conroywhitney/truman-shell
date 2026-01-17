defmodule TrumanShell.Support.Glob do
  @moduledoc """
  Glob pattern expansion for TrumanShell.

  Expands `*` and `**` patterns to matching files within the sandbox.
  Enforces a maximum depth limit of 100 levels for recursive patterns.
  """

  alias TrumanShell.Support.Sandbox

  # Maximum depth for recursive glob patterns (consistent with TreeWalker)
  @max_depth_limit 100

  @doc """
  Expands a glob pattern to matching file paths.

  Returns a sorted list of matching file paths relative to current_dir,
  or the original pattern if no files match.

  Recursive patterns (`**`) are limited to #{@max_depth_limit} levels deep.

  ## Context

  Requires a context map with:
  - `:sandbox_root` - Root directory for sandbox constraint
  - `:current_dir` - Current working directory for relative patterns

  ## Examples

      # No match returns original pattern
      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Support.Glob.expand("no_match_*.xyz", context)
      "no_match_*.xyz"

      # Matching files returns sorted list
      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> result = TrumanShell.Support.Glob.expand("mix.*", context)
      iex> is_list(result) and "mix.exs" in result
      true

      # Outside sandbox returns original pattern
      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Support.Glob.expand("/etc/*", context)
      "/etc/*"

  """
  @spec expand(String.t(), map()) :: [String.t()] | String.t()
  def expand(pattern, context) do
    is_absolute = String.starts_with?(pattern, "/")
    full_pattern = resolve_pattern(pattern, is_absolute, context.current_dir)
    base_dir = glob_base_dir(full_pattern)

    # Security: validate base path is in sandbox BEFORE calling Path.wildcard
    # This prevents filesystem enumeration outside the sandbox
    if in_sandbox?(base_dir, context.sandbox_root) do
      do_expand(pattern, full_pattern, base_dir, is_absolute, context)
    else
      pattern
    end
  end

  defp resolve_pattern(pattern, true, _current_dir), do: pattern
  defp resolve_pattern(pattern, false, current_dir), do: Path.join(current_dir, pattern)

  defp do_expand(pattern, full_pattern, base_dir, is_absolute, context) do
    match_dot = pattern_matches_dotfiles?(pattern)
    has_dot_prefix = String.starts_with?(pattern, "./")

    matches =
      full_pattern
      |> Path.wildcard(match_dot: match_dot)
      |> Enum.filter(&(in_sandbox?(&1, context.sandbox_root) and within_depth_limit?(&1, base_dir)))
      |> normalize_paths(is_absolute, has_dot_prefix, context.current_dir)
      |> Enum.sort()

    case matches do
      [] -> pattern
      files -> files
    end
  end

  defp normalize_paths(paths, true, _has_dot_prefix, _current_dir), do: paths

  defp normalize_paths(paths, false, has_dot_prefix, current_dir) do
    paths
    |> Enum.map(&Path.relative_to(&1, current_dir))
    |> then(fn relative_paths ->
      if has_dot_prefix do
        Enum.map(relative_paths, &"./#{&1}")
      else
        relative_paths
      end
    end)
  end

  # Extract the base directory from a glob pattern (everything before first wildcard)
  defp glob_base_dir(pattern) do
    pattern
    |> Path.split()
    |> Enum.take_while(&(not String.contains?(&1, "*")))
    |> Path.join()
    |> case do
      "" -> "."
      dir -> dir
    end
  end

  # Check if path depth relative to base doesn't exceed limit
  defp within_depth_limit?(path, base_dir) do
    relative = Path.relative_to(path, base_dir)
    depth = relative |> Path.split() |> length()
    depth <= @max_depth_limit
  end

  # Check if pattern explicitly targets dotfiles (basename starts with .)
  defp pattern_matches_dotfiles?(pattern) do
    pattern |> Path.basename() |> String.starts_with?(".")
  end

  defp in_sandbox?(path, sandbox_root) do
    match?({:ok, _}, Sandbox.validate_path(path, sandbox_root))
  end
end
