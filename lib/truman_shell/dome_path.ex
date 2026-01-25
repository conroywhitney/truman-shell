defmodule TrumanShell.DomePath do
  @moduledoc """
  THE path module for TrumanShell.

  **This is the ONLY module that should use Path.* directly.**
  All other modules go through DomePath for path operations.
  A custom Credo check enforces this.

  **Symlinks are denied.** Any path containing a symlink returns
  `{:error, :symlink}`. No exceptions, no allow-list, no complexity.

  If an agent wants `/tmp`, they can use `./tmp` inside the sandbox.

  > "You're not leaving the dome, Truman."

  ## Core Functions

  - `validate/3` - expand + boundary check + symlink detection
  - `within?/2` - pure string boundary checking

  ## Wrapper Functions

  These delegate to Path.* but exist here so all path operations
  go through one module:

  - `basename/1`, `type/1`, `split/1`
  - `join/1`, `join/2`
  - `expand/1`, `expand/2`
  - `relative_to/2`
  - `wildcard/1`, `wildcard/2`
  """

  @doc """
  Validates a path within a sandbox boundary.

  Expands the path, checks for symlinks (denied), $VAR (denied),
  and verifies the result is within the sandbox boundary.

  Returns `{:ok, absolute_path}` or `{:error, reason}`.

  ## Error reasons

  - `:embedded_var` - path contains `$VAR` reference
  - `:symlink` - path contains a symlink component
  - `:outside_boundary` - resolved path is outside sandbox

  ## Examples

      iex> DomePath.validate("lib/foo.ex", "/sandbox")
      {:ok, "/sandbox/lib/foo.ex"}

      iex> DomePath.validate("../escape", "/sandbox")
      {:error, :outside_boundary}

      iex> DomePath.validate("$HOME/file", "/sandbox")
      {:error, :embedded_var}

  """
  @spec validate(String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, :embedded_var | :symlink | :outside_boundary}
  def validate(path, sandbox, current_dir \\ nil)

  def validate(path, sandbox, current_dir) do
    expanded_sandbox = Path.expand(sandbox)

    with :ok <- check_embedded_var(path),
         :ok <- check_embedded_var(current_dir),
         {:ok, validated_current_dir} <- validate_current_dir(current_dir, expanded_sandbox),
         absolute_path = expand_path(path, expanded_sandbox, validated_current_dir),
         :ok <- check_symlinks_in_path(absolute_path),
         :ok <- check_boundary(absolute_path, expanded_sandbox) do
      {:ok, absolute_path}
    end
  end

  # --- Private: Embedded $VAR check ---

  defp check_embedded_var(nil), do: :ok

  defp check_embedded_var(path) do
    if String.contains?(path, "$") do
      {:error, :embedded_var}
    else
      :ok
    end
  end

  # --- Private: Current directory validation ---

  defp validate_current_dir(nil, _sandbox), do: {:ok, nil}

  defp validate_current_dir(current_dir, sandbox) do
    expanded = Path.expand(current_dir)

    with :ok <- check_symlinks_in_path(expanded),
         :ok <- check_boundary(expanded, sandbox) do
      {:ok, expanded}
    end
  end

  # --- Private: Path expansion ---

  defp expand_path(path, sandbox, current_dir) do
    case Path.type(path) do
      :absolute ->
        Path.expand(path)

      :relative ->
        base = current_dir || sandbox
        Path.expand(path, base)
    end
  end

  # --- Private: Symlink detection (any symlink = error) ---

  defp check_symlinks_in_path(path) do
    # Path.split returns the root component first (e.g., "/" on Unix, "C:/" on Windows)
    # Use the first component as the starting point for cross-platform compatibility
    case Path.split(path) do
      [] -> :ok
      [root | rest] -> check_components_for_symlinks(rest, root)
    end
  end

  defp check_components_for_symlinks([], _current), do: :ok

  defp check_components_for_symlinks([component | rest], current) do
    next_path = Path.join(current, component)

    case :file.read_link_all(next_path) do
      {:ok, _target} ->
        # It's a symlink - reject
        {:error, :symlink}

      {:error, :einval} ->
        # Not a symlink - continue
        check_components_for_symlinks(rest, next_path)

      {:error, :enoent} ->
        # Path doesn't exist yet - OK for create operations
        :ok

      {:error, _reason} ->
        # Other error - let actual operation fail
        :ok
    end
  end

  # --- Private: Boundary check ---

  defp check_boundary(path, sandbox) do
    if within?(path, sandbox) do
      :ok
    else
      {:error, :outside_boundary}
    end
  end

  @doc """
  Checks if a path is within the given root boundary.

  Pure string comparison - no filesystem access.

  ## Examples

      iex> TrumanShell.DomePath.within?("/sandbox/lib/foo.ex", "/sandbox")
      true

      iex> TrumanShell.DomePath.within?("/etc/passwd", "/sandbox")
      false

      iex> TrumanShell.DomePath.within?("/sandbox2/file", "/sandbox")
      false

  """
  @spec within?(String.t(), String.t()) :: boolean()
  def within?(path, root) do
    normalized_root = String.trim_trailing(root, "/")
    normalized_path = String.trim_trailing(path, "/")

    normalized_path == normalized_root or
      String.starts_with?(normalized_path, normalized_root <> "/")
  end

  # =============================================================================
  # Wrapper functions - delegate to Path.*
  # These exist so ALL path operations go through DomePath (single chokepoint)
  # =============================================================================

  @doc """
  Returns the last component of the path.

  Delegates to `Path.basename/1`.
  """
  @spec basename(String.t()) :: String.t()
  def basename(path), do: Path.basename(path)

  @doc """
  Returns the type of the path: `:absolute` or `:relative`.

  Delegates to `Path.type/1`.
  """
  @spec type(String.t()) :: :absolute | :relative
  def type(path), do: Path.type(path)

  @doc """
  Splits a path into its components.

  Delegates to `Path.split/1`.
  """
  @spec split(String.t()) :: [String.t()]
  def split(path), do: Path.split(path)

  @doc """
  Joins two paths.

  Delegates to `Path.join/2`.
  """
  @spec join(String.t(), String.t()) :: String.t()
  def join(left, right), do: Path.join(left, right)

  @doc """
  Joins a list of paths.

  Handles empty list gracefully (returns "").
  """
  @spec join([String.t()]) :: String.t()
  def join([]), do: ""
  def join(paths) when is_list(paths), do: Path.join(paths)

  @doc """
  Expands a path relative to the current working directory.

  Delegates to `Path.expand/1`.
  """
  @spec expand(String.t()) :: String.t()
  def expand(path), do: Path.expand(path)

  @doc """
  Expands a path relative to the given base.

  Delegates to `Path.expand/2`.
  """
  @spec expand(String.t(), String.t()) :: String.t()
  def expand(path, base), do: Path.expand(path, base)

  @doc """
  Returns the path relative to the given base.

  Delegates to `Path.relative_to/2`.
  """
  @spec relative_to(String.t(), String.t()) :: String.t()
  def relative_to(path, base), do: Path.relative_to(path, base)

  @doc """
  Returns a list of paths matching the given pattern.

  Delegates to `Path.wildcard/1`.
  """
  @spec wildcard(String.t()) :: [String.t()]
  def wildcard(pattern), do: Path.wildcard(pattern)

  @doc """
  Returns a list of paths matching the given pattern with options.

  Delegates to `Path.wildcard/2`.

  ## Options

  - `:match_dot` - if `true`, `*` and `?` match files starting with `.`
  """
  @spec wildcard(String.t(), keyword()) :: [String.t()]
  def wildcard(pattern, opts), do: Path.wildcard(pattern, opts)
end
