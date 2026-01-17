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

    full_pattern =
      if is_absolute do
        pattern
      else
        Path.join(context.current_dir, pattern)
      end

    match_dot = pattern_matches_dotfiles?(pattern)
    base_dir = glob_base_dir(full_pattern)

    matches =
      full_pattern
      |> Path.wildcard(match_dot: match_dot)
      |> Enum.filter(&(in_sandbox?(&1, context.sandbox_root) and within_depth_limit?(&1, base_dir)))
      |> then(fn paths ->
        if is_absolute do
          paths
        else
          Enum.map(paths, &Path.relative_to(&1, context.current_dir))
        end
      end)
      |> Enum.sort()

    case matches do
      [] -> pattern
      files -> files
    end
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
