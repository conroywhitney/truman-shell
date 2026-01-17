defmodule TrumanShell.Support.Glob do
  @moduledoc """
  Glob pattern expansion for TrumanShell.

  Expands `*` and `**` patterns to matching files within the sandbox.
  """

  alias TrumanShell.Support.Sandbox

  @doc """
  Expands a glob pattern to matching file paths.

  Returns a sorted list of matching file paths relative to current_dir,
  or the original pattern if no files match.

  ## Context

  Requires a context map with:
  - `:sandbox_root` - Root directory for sandbox constraint
  - `:current_dir` - Current working directory for relative patterns
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

    matches =
      Path.wildcard(full_pattern, match_dot: match_dot)
      |> Enum.filter(&in_sandbox?(&1, context.sandbox_root))
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

  # Check if pattern explicitly targets dotfiles (basename starts with .)
  defp pattern_matches_dotfiles?(pattern) do
    pattern |> Path.basename() |> String.starts_with?(".")
  end

  defp in_sandbox?(path, sandbox_root) do
    match?({:ok, _}, Sandbox.validate_path(path, sandbox_root))
  end
end
