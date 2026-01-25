defmodule TrumanShell.Support.Glob do
  @moduledoc """
  Glob pattern expansion for TrumanShell.

  Expands `*` and `**` patterns to matching files within the sandbox.
  Enforces a maximum depth limit of 100 levels for recursive patterns.
  """

  alias TrumanShell.Config.Sandbox, as: SandboxConfig
  alias TrumanShell.DomePath
  alias TrumanShell.Support.Sandbox

  # Maximum depth for recursive glob patterns (consistent with TreeWalker)
  @max_depth_limit 100

  @doc """
  Expands a glob pattern to matching file paths.

  Returns a sorted list of matching file paths relative to current_dir,
  or the original pattern if no files match.

  Recursive patterns (`**`) are limited to #{@max_depth_limit} levels deep.

  ## Config

  Accepts a `%Config.Sandbox{}` struct with:
  - `allowed_paths` - List of allowed directories (all paths checked for sandbox constraint)
  - `home_path` - Current working directory for relative patterns

  ## Examples

      # No match returns original pattern
      iex> config = %TrumanShell.Config.Sandbox{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> TrumanShell.Support.Glob.expand("no_match_*.xyz", config)
      "no_match_*.xyz"

      # Matching files returns sorted list
      iex> config = %TrumanShell.Config.Sandbox{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> result = TrumanShell.Support.Glob.expand("mix.*", config)
      iex> is_list(result) and "mix.exs" in result
      true

      # Outside sandbox returns original pattern
      iex> config = %TrumanShell.Config.Sandbox{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> TrumanShell.Support.Glob.expand("/etc/*", config)
      "/etc/*"

  """
  @spec expand(String.t(), SandboxConfig.t() | map()) :: [String.t()] | String.t()
  def expand(pattern, %SandboxConfig{home_path: current_dir} = config) do
    # Defense-in-depth: validate current_dir is absolute and inside sandbox
    # This prevents Path.wildcard from resolving relative patterns against process cwd
    # (In normal operation, current_dir is always validated by cd command)
    with :ok <- validate_current_dir_is_absolute(current_dir),
         {:ok, validated_current_dir} <- Sandbox.validate_path(current_dir, config) do
      do_expand_with_config(pattern, %{config | home_path: validated_current_dir})
    else
      _ ->
        # Invalid current_dir - fail safe by returning original pattern
        pattern
    end
  end

  # Backward compatibility: convert legacy context map to Config.Sandbox struct
  def expand(pattern, %{sandbox_root: sandbox_root} = context) do
    current_dir = Map.get(context, :current_dir, sandbox_root)
    config = %SandboxConfig{allowed_paths: [sandbox_root], home_path: current_dir}
    expand(pattern, config)
  end

  defp validate_current_dir_is_absolute(current_dir) do
    if DomePath.type(current_dir) == :absolute do
      :ok
    else
      {:error, :relative_current_dir}
    end
  end

  defp do_expand_with_config(pattern, %SandboxConfig{home_path: current_dir} = config) do
    is_absolute = String.starts_with?(pattern, "/")
    full_pattern = resolve_pattern(pattern, is_absolute, current_dir)
    base_dir = glob_base_dir(full_pattern)

    # Security: validate base path is in sandbox BEFORE calling DomePath.wildcard
    # This prevents filesystem enumeration outside the sandbox
    if in_sandbox?(base_dir, config) do
      do_expand(pattern, full_pattern, base_dir, is_absolute, config)
    else
      pattern
    end
  end

  defp resolve_pattern(pattern, true, _current_dir), do: pattern
  defp resolve_pattern(pattern, false, current_dir), do: DomePath.join(current_dir, pattern)

  defp do_expand(pattern, full_pattern, base_dir, is_absolute, %SandboxConfig{home_path: current_dir} = config) do
    match_dot = pattern_matches_dotfiles?(pattern)
    has_dot_prefix = String.starts_with?(pattern, "./")

    matches =
      full_pattern
      |> DomePath.wildcard(match_dot: match_dot)
      |> Enum.filter(&(in_sandbox?(&1, config) and within_depth_limit?(&1, base_dir)))
      |> normalize_paths(is_absolute, has_dot_prefix, current_dir)
      |> Enum.sort()

    case matches do
      [] -> pattern
      files -> files
    end
  end

  defp normalize_paths(paths, true = _is_absolute, _has_dot_prefix, _current_dir), do: paths

  defp normalize_paths(paths, false = _is_absolute, has_dot_prefix, current_dir) do
    paths
    |> Enum.map(&DomePath.relative_to(&1, current_dir))
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
    |> DomePath.split()
    |> Enum.take_while(&(not String.contains?(&1, "*")))
    |> DomePath.join()
    |> case do
      "" -> "."
      dir -> dir
    end
  end

  # Check if path depth relative to base doesn't exceed limit
  defp within_depth_limit?(path, base_dir) do
    relative = DomePath.relative_to(path, base_dir)
    depth = relative |> DomePath.split() |> length()
    depth <= @max_depth_limit
  end

  # Check if pattern explicitly targets dotfiles (basename starts with .)
  defp pattern_matches_dotfiles?(pattern) do
    pattern |> DomePath.basename() |> String.starts_with?(".")
  end

  defp in_sandbox?(path, %SandboxConfig{} = config) do
    match?({:ok, _}, Sandbox.validate_path(path, config))
  end
end
