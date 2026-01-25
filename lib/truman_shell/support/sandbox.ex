defmodule TrumanShell.Support.Sandbox do
  @moduledoc """
  Sandbox boundary management for TrumanShell.

  Handles:
  - Reading sandbox root from `TRUMAN_DOME` env var
  - Path expansion (tilde, relative paths)
  - Path validation (is this path within the sandbox?)
  - Symlink escape detection
  - Error messages that follow the 404 Principle (no information leakage)

  > "You're not leaving the dome, Truman."

  Implements the "404 Principle" - paths outside the sandbox appear
  as "not found" rather than "permission denied" to avoid information leakage.

  ## Security Limitations

  **TOCTOU (Time-of-Check to Time-of-Use):** This module validates paths at
  check time, but the filesystem can change between validation and actual use.
  A symlink could be modified after `validate_path/2` returns `{:ok, path}` but
  before the file operation occurs.

  This is inherent to userspace sandboxing. For untrusted environments, use
  OS-level isolation (containers, chroot, namespaces) in addition to this module.
  """

  @env_var "TRUMAN_DOME"

  @doc """
  Builds the execution context with sandbox boundaries.

  Returns a map with `:sandbox_root` and `:current_dir` keys.

  ## Examples

      iex> context = TrumanShell.Support.Sandbox.build_context()
      iex> Map.has_key?(context, :sandbox_root)
      true
      iex> Map.has_key?(context, :current_dir)
      true

  """
  @spec build_context() :: %{sandbox_root: String.t(), current_dir: String.t()}
  def build_context do
    root = sandbox_root()
    %{sandbox_root: root, current_dir: root}
  end

  @doc """
  Returns the sandbox root path.

  Reads from `TRUMAN_DOME` environment variable, falling back
  to `File.cwd!()` if not set or empty.

  Handles path expansion:
  - `~` expands to `$HOME`
  - `.` and `./path` expand relative to cwd
  - Trailing slashes are normalized

  Does NOT expand `$VAR` references (security risk).

  ## Examples

      # With env var set
      System.put_env("TRUMAN_DOME", "~/projects/myapp")
      TrumanShell.Support.Sandbox.sandbox_root()
      #=> "/Users/you/projects/myapp"

      # Without env var
      System.delete_env("TRUMAN_DOME")
      TrumanShell.Support.Sandbox.sandbox_root()
      #=> File.cwd!()

  """
  @spec sandbox_root() :: String.t()
  def sandbox_root do
    case System.get_env(@env_var) do
      nil -> File.cwd!()
      "" -> File.cwd!()
      path -> expand_and_normalize(path)
    end
  end

  @doc """
  Validates that a path resolves within the sandbox root.

  Returns `{:ok, resolved_path}` if the path is safe,
  or `{:error, :outside_sandbox}` if it would escape.

  Handles:
  - Absolute paths
  - Relative paths (resolved against current_dir)
  - Path traversal attempts (`../`)
  - Symlink escape attempts (follows symlinks before checking)

  ## Examples

      # Relative paths within sandbox are allowed
      iex> {:ok, path} = TrumanShell.Support.Sandbox.validate_path("lib/foo.ex", "/sandbox")
      iex> path
      "/sandbox/lib/foo.ex"

      # Directory traversal is blocked
      iex> TrumanShell.Support.Sandbox.validate_path("../escape", "/sandbox")
      {:error, :outside_sandbox}

      # Absolute paths outside sandbox are blocked
      iex> TrumanShell.Support.Sandbox.validate_path("/etc/passwd", "/sandbox")
      {:error, :outside_sandbox}

      # Similar prefix but different directory is blocked
      iex> TrumanShell.Support.Sandbox.validate_path("/sandbox2/file", "/sandbox")
      {:error, :outside_sandbox}

      # Absolute paths within sandbox are allowed
      iex> {:ok, path} = TrumanShell.Support.Sandbox.validate_path("/sandbox/file", "/sandbox")
      iex> path
      "/sandbox/file"

      # With current_dir context
      iex> {:ok, path} = TrumanShell.Support.Sandbox.validate_path("lib/foo.ex", "/sandbox", "/sandbox")
      iex> path
      "/sandbox/lib/foo.ex"

  """
  @spec validate_path(String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, :outside_sandbox | :eloop}
  def validate_path(path, sandbox_root, current_dir \\ nil)

  def validate_path(path, sandbox_root, current_dir) do
    # Reject paths with embedded $VAR references (security risk)
    if String.contains?(path, "$") do
      {:error, :outside_sandbox}
    else
      sandbox_resolved = resolve_sandbox_root(sandbox_root)

      case validate_current_dir(current_dir, sandbox_resolved) do
        {:error, reason} ->
          {:error, reason}

        {:ok, validated_current_dir} ->
          absolute_path = resolve_to_absolute(path, sandbox_resolved, validated_current_dir)
          validate_resolved_path(absolute_path, sandbox_resolved)
      end
    end
  end

  # Validate current_dir is within sandbox and return the resolved path
  # Returns {:ok, resolved_current_dir} to avoid double symlink resolution
  defp validate_current_dir(nil, _sandbox), do: {:ok, nil}

  defp validate_current_dir(current_dir, sandbox_resolved) do
    # Reject current_dir with embedded $VAR references (same as path)
    if String.contains?(current_dir, "$") do
      {:error, :outside_sandbox}
    else
      # Resolve current_dir to handle symlinks (e.g., /var -> /private/var on macOS)
      resolved_current_dir =
        case resolve_real_path(Path.expand(current_dir)) do
          {:ok, resolved} -> resolved
          {:error, _} -> Path.expand(current_dir)
        end

      if path_within_sandbox?(resolved_current_dir, sandbox_resolved) do
        # Return the resolved path to avoid resolving again in resolve_to_absolute
        {:ok, resolved_current_dir}
      else
        # current_dir outside sandbox is a security error
        {:error, :outside_sandbox}
      end
    end
  end

  defp resolve_sandbox_root(sandbox_root) do
    # Resolve symlinks in sandbox_root too (e.g., /tmp -> /private/tmp on macOS)
    case resolve_real_path(Path.expand(sandbox_root)) do
      {:ok, resolved} -> resolved
      {:error, _} -> Path.expand(sandbox_root)
    end
  end

  defp resolve_to_absolute(path, sandbox_resolved, current_dir) do
    cond do
      Path.type(path) == :absolute -> path
      current_dir != nil -> Path.join(current_dir, path)
      true -> Path.join(sandbox_resolved, path)
    end
  end

  defp validate_resolved_path(absolute_path, sandbox_resolved) do
    case resolve_real_path(absolute_path) do
      {:ok, real_path} ->
        check_path_within_sandbox(real_path, sandbox_resolved)

      {:error, :eloop} ->
        # Symlink depth limit exceeded - this is a security error, propagate
        {:error, :eloop}

      {:error, _reason} ->
        # Path doesn't exist or other error - check if target would be valid
        # Let the actual file operation return the specific error
        expanded = Path.expand(absolute_path)
        check_path_within_sandbox(expanded, sandbox_resolved)
    end
  end

  defp check_path_within_sandbox(path, sandbox) do
    if path_within_sandbox?(path, sandbox) do
      {:ok, path}
    else
      {:error, :outside_sandbox}
    end
  end

  @doc """
  Converts an error tuple to a user-facing message.

  Follows the 404 Principle: paths outside the sandbox return
  "No such file or directory" rather than revealing they're blocked.

  ## Examples

      iex> TrumanShell.Support.Sandbox.error_message({:error, :outside_sandbox})
      "No such file or directory"

      iex> TrumanShell.Support.Sandbox.error_message({:error, :enoent})
      "No such file or directory"

  """
  @spec error_message({:error, atom()}) :: String.t()
  def error_message({:error, :outside_sandbox}), do: "No such file or directory"
  def error_message({:error, :enoent}), do: "No such file or directory"
  def error_message({:error, :eloop}), do: "Too many levels of symbolic links"
  def error_message({:error, reason}) when is_atom(reason), do: "#{reason}"

  # --- Private Functions ---

  defp expand_and_normalize(path) do
    path
    |> expand_tilde()
    |> expand_relative()
    |> normalize_trailing_slashes()
  end

  defp expand_tilde("~" <> rest) do
    home = System.get_env("HOME") || "~"
    home <> rest
  end

  defp expand_tilde(path), do: path

  defp expand_relative(path) do
    cond do
      # Don't expand $VAR references - return as-is (intentionally not supported)
      String.starts_with?(path, "$") ->
        path

      Path.type(path) == :relative ->
        Path.expand(path, File.cwd!())

      true ->
        path
    end
  end

  defp normalize_trailing_slashes(path) do
    path
    |> String.trim_trailing("/")
    |> case do
      "" -> "/"
      normalized -> normalized
    end
  end

  # Maximum symlink depth to prevent infinite loops
  @max_symlink_depth 10

  defp resolve_real_path(path) do
    # Resolve ALL symlinks in the path, not just the final component
    # This prevents intermediate directory symlink escapes
    # Returns {:ok, resolved_path} or {:error, reason}
    case do_resolve_path(Path.expand(path), @max_symlink_depth) do
      {:ok, resolved, _remaining_depth} -> {:ok, resolved}
      {:error, reason} -> {:error, reason}
    end
  end

  # Functions for recursive symlink resolution (mutual recursion)
  # Note: These have mutual recursion, so order matters for credo
  #
  # All resolve functions return {:ok, path, remaining_depth} or {:error, reason}
  # to properly track depth consumption across nested symlink chains.

  # Resolve a symlink target and continue with remaining path components.
  # Each symlink hop consumes 1 depth.
  # parent_dir: the directory containing the symlink (for relative target resolution)
  defp resolve_symlink_target(target, parent_dir, rest, depth) do
    # Check depth BEFORE processing this symlink
    if depth <= 0 do
      {:error, :eloop}
    else
      target_path = List.to_string(target)
      new_depth = depth - 1

      resolved =
        if Path.type(target_path) == :absolute do
          target_path
        else
          Path.join(parent_dir, target_path)
        end

      # Recursively resolve the target (it might also have symlinks)
      # IMPORTANT: Use the remaining depth from do_resolve_path for continue
      with {:ok, resolved_target, remaining_depth} <- do_resolve_path(Path.expand(resolved), new_depth) do
        continue_after_symlink(resolved_target, rest, remaining_depth)
      end
    end
  end

  defp continue_after_symlink(resolved_target, [], depth) do
    {:ok, resolved_target, depth}
  end

  defp continue_after_symlink(resolved_target, rest, depth) do
    remaining_path = Path.join([resolved_target | rest])
    do_resolve_path(remaining_path, depth)
  end

  defp resolve_components([], current_path, depth) do
    {:ok, current_path, depth}
  end

  defp resolve_components([component | rest], current_path, depth) do
    next_path = Path.join(current_path, component)

    case :file.read_link_all(next_path) do
      {:ok, target} when is_list(target) ->
        resolve_symlink_target(target, current_path, rest, depth)

      {:error, :einval} ->
        resolve_components(rest, next_path, depth)

      {:error, :enoent} ->
        full_path = Path.join([next_path | rest])
        {:ok, Path.expand(full_path), depth}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_resolve_path(_path, 0), do: {:error, :eloop}

  defp do_resolve_path(path, depth) do
    components = Path.split(path)
    resolve_components(components, "/", depth)
  end

  # Check if path is within sandbox using proper directory boundary check.
  # "/tmp/sandbox/file" is within "/tmp/sandbox"
  # "/tmp/sandbox2/file" is NOT within "/tmp/sandbox" (different directory!)
  defp path_within_sandbox?(path, sandbox) do
    # Expand both to canonical form
    expanded_path = Path.expand(path)
    expanded_sandbox = Path.expand(sandbox)

    # Check if path starts with sandbox
    String.starts_with?(expanded_path, expanded_sandbox <> "/") or
      expanded_path == expanded_sandbox
  end
end
