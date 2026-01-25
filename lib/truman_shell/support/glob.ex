defmodule TrumanShell.Support.Glob do
  @moduledoc """
  Glob pattern expansion for TrumanShell.

  Expands `*` and `**` patterns to matching files within the sandbox.
  Enforces a maximum depth limit of 100 levels for recursive patterns.
  """

  alias TrumanShell.Commands.Context
  alias TrumanShell.Config.Sandbox, as: SandboxConfig
  alias TrumanShell.DomePath
  alias TrumanShell.Support.Sandbox

  # Maximum depth for recursive glob patterns (consistent with TreeWalker)
  @max_depth_limit 100

  @doc """
  Expands a glob pattern to matching file paths.

  Returns a sorted list of matching file paths relative to current_path,
  or the original pattern if no files match.

  Recursive patterns (`**`) are limited to #{@max_depth_limit} levels deep.

  ## Arguments

  - `pattern` - The glob pattern to expand
  - `ctx` - `%Commands.Context{}` with current_path and sandbox_config

  ## Examples

      # No match returns original pattern
      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}}
      iex> TrumanShell.Support.Glob.expand("no_match_*.xyz", ctx)
      "no_match_*.xyz"

      # Matching files returns sorted list
      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}}
      iex> result = TrumanShell.Support.Glob.expand("mix.*", ctx)
      iex> is_list(result) and "mix.exs" in result
      true

      # Outside sandbox returns original pattern
      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}}
      iex> TrumanShell.Support.Glob.expand("/etc/*", ctx)
      "/etc/*"

  """
  @spec expand(String.t(), Context.t()) :: [String.t()] | String.t()
  def expand(pattern, %Context{current_path: current_path, sandbox_config: config}) do
    # current_path is @enforce_keys in Context - if nil, let it crash
    do_expand_with_validation(pattern, current_path, config)
  end

  defp do_expand_with_validation(pattern, current_path, config) do
    # Defense-in-depth: validate current_path is absolute and inside sandbox
    with :ok <- validate_absolute(current_path),
         {:ok, validated_path} <- Sandbox.validate_path(current_path, config) do
      do_expand(pattern, validated_path, config)
    else
      _ ->
        # Invalid current_path - fail loud (this is a bug, not user error)
        raise ArgumentError, "current_path must be absolute and inside sandbox, got: #{inspect(current_path)}"
    end
  end

  defp validate_absolute(path) do
    if DomePath.type(path) == :absolute, do: :ok, else: {:error, :relative}
  end

  defp do_expand(pattern, current_path, config) do
    is_absolute = String.starts_with?(pattern, "/")
    full_pattern = resolve_pattern(pattern, is_absolute, current_path)
    base_dir = glob_base_dir(full_pattern)

    # Security: validate base path is in sandbox BEFORE calling DomePath.wildcard
    if in_sandbox?(base_dir, config) do
      expand_glob(pattern, full_pattern, base_dir, is_absolute, current_path, config)
    else
      pattern
    end
  end

  defp resolve_pattern(pattern, true, _current_path), do: pattern
  defp resolve_pattern(pattern, false, current_path), do: DomePath.join(current_path, pattern)

  defp expand_glob(pattern, full_pattern, base_dir, is_absolute, current_path, config) do
    match_dot = pattern_matches_dotfiles?(pattern)
    has_dot_prefix = String.starts_with?(pattern, "./")

    matches =
      full_pattern
      |> DomePath.wildcard(match_dot: match_dot)
      |> Enum.filter(&(in_sandbox?(&1, config) and within_depth_limit?(&1, base_dir)))
      |> normalize_paths(is_absolute, has_dot_prefix, current_path)
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
