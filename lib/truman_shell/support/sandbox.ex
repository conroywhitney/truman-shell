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

  alias TrumanShell.Commands.Context
  alias TrumanShell.Config.Sandbox, as: SandboxConfig
  alias TrumanShell.DomePath

  @env_var "TRUMAN_DOME"

  @doc """
  Builds a sandbox configuration struct.

  Returns a `%Config.Sandbox{}` struct with `allowed_paths` and `home_path` fields.
  This is the preferred way to get sandbox configuration for use with `validate_path/2`.

  ## Examples

      iex> config = TrumanShell.Support.Sandbox.build_config()
      iex> %TrumanShell.Config.Sandbox{} = config
      iex> is_list(config.allowed_paths)
      true

  """
  @spec build_config() :: SandboxConfig.t()
  def build_config do
    root = sandbox_root()
    # Use struct! directly since we know root is valid (no validation needed)
    %SandboxConfig{allowed_paths: [root], home_path: root}
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
  Validates that a path resolves within the sandbox.

  Returns `{:ok, resolved_path}` if the path is safe,
  or `{:error, :outside_sandbox}` if it would escape.

  Accepts three forms:
  - `validate_path(path, %Context{})` - uses ctx.current_path for relative resolution
  - `validate_path(path, %Config.Sandbox{})` - uses config.home_path for relative resolution
  - `validate_path(path, sandbox_root)` - simple string boundary

  Handles:
  - Absolute paths
  - Relative paths (resolved against current_dir)
  - Path traversal attempts (`../`)
  - Symlink rejection (symlinks denied, period)
  - `$VAR` injection prevention

  ## Examples

      # With Context - relative paths resolve using current_path
      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> config = %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}
      iex> ctx = %Context{current_path: "/sandbox/subdir", sandbox_config: config}
      iex> {:ok, path} = TrumanShell.Support.Sandbox.validate_path("file.txt", ctx)
      iex> path
      "/sandbox/subdir/file.txt"

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

  """
  @spec validate_path(String.t(), Context.t() | SandboxConfig.t() | String.t()) ::
          {:ok, String.t()} | {:error, :outside_sandbox}
  def validate_path(path, %Context{} = ctx) do
    # Use current_path for resolving relative paths (where user cd'd to)
    %Context{current_path: current_path, sandbox_config: config} = ctx
    %SandboxConfig{allowed_paths: allowed_paths} = config

    Enum.reduce_while(allowed_paths, {:error, :outside_sandbox}, fn boundary, _acc ->
      case do_validate_path(path, boundary, current_path) do
        {:ok, validated_path} -> {:halt, {:ok, validated_path}}
        {:error, _} -> {:cont, {:error, :outside_sandbox}}
      end
    end)
  end

  def validate_path(path, %SandboxConfig{} = config) do
    # Try each allowed_path until one validates, or return error if none work
    %SandboxConfig{allowed_paths: allowed_paths, home_path: home_path} = config

    Enum.reduce_while(allowed_paths, {:error, :outside_sandbox}, fn boundary, _acc ->
      case do_validate_path(path, boundary, home_path) do
        {:ok, validated_path} -> {:halt, {:ok, validated_path}}
        {:error, _} -> {:cont, {:error, :outside_sandbox}}
      end
    end)
  end

  def validate_path(path, sandbox_root) when is_binary(sandbox_root) do
    do_validate_path(path, sandbox_root, nil)
  end

  defp do_validate_path(path, sandbox_root, current_dir) do
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
