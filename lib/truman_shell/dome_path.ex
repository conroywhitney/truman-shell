defmodule TrumanShell.DomePath do
  @moduledoc """
  Bounded path operations for TrumanShell.

  **Symlinks are denied.** Any path containing a symlink returns
  `{:error, :symlink}`. No exceptions, no allow-list, no complexity.

  If an agent wants `/tmp`, they can use `./tmp` inside the sandbox.

  > "You're not leaving the dome, Truman."
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
    components = Path.split(path)
    check_components_for_symlinks(components, "/")
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
end
