defmodule TrumanShell.Support.Sandbox do
  @moduledoc """
  Sandbox boundary management for TrumanShell.

  Handles:
  - Reading sandbox root from `TRUMAN_DOME` env var
  - Path expansion (tilde, relative paths)
  - Path validation (is this path within the sandbox?)
  - Symlink rejection (symlinks denied, period)
  - Error messages that follow the 404 Principle (no information leakage)

  > "You're not leaving the dome, Truman."

  **Symlinks are denied.** Any path containing a symlink component is rejected.
  No exceptions, no allow-list, no complexity. If an agent wants `/tmp`, they
  can use `./tmp` inside the sandbox.

  Implements the "404 Principle" - paths outside the sandbox appear
  as "not found" rather than "permission denied" to avoid information leakage.

  ## Security Limitations

  **TOCTOU (Time-of-Check to Time-of-Use):** This module validates paths at
  check time, but the filesystem can change between validation and actual use.
  A path could be modified after `validate_path/2` returns `{:ok, path}` but
  before the file operation occurs.

  This is inherent to userspace sandboxing. For untrusted environments, use
  OS-level isolation (containers, chroot, namespaces) in addition to this module.
  """

  alias TrumanShell.DomePath

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
  - Symlink rejection (symlinks denied, period)
  - `$VAR` injection prevention

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
          {:ok, String.t()} | {:error, :outside_sandbox}
  def validate_path(path, sandbox_root, current_dir \\ nil)

  def validate_path(path, sandbox_root, current_dir) do
    # Delegate to DomePath.validate which enforces:
    # - No $VAR references
    # - No symlinks (symlinks denied, period)
    # - Path must be within boundary
    case DomePath.validate(path, sandbox_root, current_dir) do
      {:ok, validated_path} ->
        {:ok, validated_path}

      {:error, :embedded_var} ->
        {:error, :outside_sandbox}

      {:error, :symlink} ->
        {:error, :outside_sandbox}

      {:error, :outside_boundary} ->
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

      DomePath.type(path) == :relative ->
        DomePath.expand(path, File.cwd!())

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
end
