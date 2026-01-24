defmodule TrumanShell.Boundaries do
  @moduledoc """
  Playground boundary management for TrumanShell.

  Handles:
  - Reading playground root from `TRUMAN_PLAYGROUND_ROOT` env var
  - Path expansion (tilde, relative paths)
  - Path validation (is this path within the playground?)
  - Error messages that follow the 404 Principle (no information leakage)

  > "Playground, not sandbox" — We're both Trumans in here.
  """

  @env_var "TRUMAN_PLAYGROUND_ROOT"

  @doc """
  Builds the execution context with playground boundaries.

  Returns a map with `:playground_root`, `:sandbox_root` (alias), and `:current_dir` keys.

  Note: `:sandbox_root` is included for backwards compatibility with existing commands.
  New code should use `:playground_root`. A full rename is planned for a future PR.
  """
  @spec build_context() :: %{
          playground_root: String.t(),
          sandbox_root: String.t(),
          current_dir: String.t()
        }
  def build_context do
    root = playground_root()
    # Include both keys during transition period
    %{playground_root: root, sandbox_root: root, current_dir: root}
  end

  @doc """
  Returns the playground root path.

  Reads from `TRUMAN_PLAYGROUND_ROOT` environment variable, falling back
  to `File.cwd!()` if not set or empty.

  Handles path expansion:
  - `~` expands to `$HOME`
  - `.` and `./path` expand relative to cwd
  - Trailing slashes are normalized

  Does NOT expand `$VAR` references (security risk).

  ## Examples

      # With env var set
      System.put_env("TRUMAN_PLAYGROUND_ROOT", "~/projects/myapp")
      TrumanShell.Boundaries.playground_root()
      #=> "/Users/you/projects/myapp"

      # Without env var
      System.delete_env("TRUMAN_PLAYGROUND_ROOT")
      TrumanShell.Boundaries.playground_root()
      #=> File.cwd!()

  """
  @spec playground_root() :: String.t()
  def playground_root do
    case System.get_env(@env_var) do
      nil -> File.cwd!()
      "" -> File.cwd!()
      path -> expand_and_normalize(path)
    end
  end

  @doc """
  Validates that a path is within the playground boundary.

  Returns `{:ok, absolute_path}` if valid, `{:error, :outside_playground}` if not.

  Handles:
  - Absolute paths
  - Relative paths (resolved against current_dir)
  - Path traversal attempts (`../`)
  - Symlink escape attempts (follows symlinks before checking)

  ## Examples

      iex> TrumanShell.Boundaries.validate_path("/playground/lib/foo.ex", "/playground")
      {:ok, "/playground/lib/foo.ex"}

      iex> TrumanShell.Boundaries.validate_path("/etc/passwd", "/playground")
      {:error, :outside_playground}

      iex> TrumanShell.Boundaries.validate_path("lib/foo.ex", "/playground", "/playground")
      {:ok, "/playground/lib/foo.ex"}

  """
  @spec validate_path(String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, :outside_playground}
  def validate_path(path, playground_root, current_dir \\ nil)

  def validate_path(path, playground_root, current_dir) do
    # Resolve to absolute path
    absolute_path =
      cond do
        Path.type(path) == :absolute ->
          path

        current_dir != nil ->
          Path.join(current_dir, path)

        true ->
          Path.join(playground_root, path)
      end

    # Expand the path to resolve .. and symlinks
    case resolve_real_path(absolute_path) do
      {:ok, real_path} ->
        if path_within?(real_path, playground_root) do
          {:ok, real_path}
        else
          {:error, :outside_playground}
        end

      {:error, _} ->
        # Path doesn't exist or can't be resolved
        # For symlinks, we still need to check if the target would be valid
        expanded = Path.expand(absolute_path)

        if path_within?(expanded, playground_root) do
          {:ok, expanded}
        else
          {:error, :outside_playground}
        end
    end
  end

  @doc """
  Converts an error tuple to a user-facing message.

  Follows the 404 Principle: paths outside the playground return
  "No such file or directory" rather than revealing they're blocked.

  ## Examples

      iex> TrumanShell.Boundaries.error_message({:error, :outside_playground})
      "No such file or directory"

  """
  @spec error_message({:error, atom()}) :: String.t()
  def error_message({:error, :outside_playground}), do: "No such file or directory"
  def error_message({:error, :enoent}), do: "No such file or directory"
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

  defp resolve_real_path(path) do
    # Use :file.read_link_info to follow symlinks
    case :file.read_link_all(path) do
      {:ok, target} when is_list(target) ->
        # It's a symlink, resolve the target
        target_path = List.to_string(target)

        resolved =
          if Path.type(target_path) == :absolute do
            target_path
          else
            Path.join(Path.dirname(path), target_path)
          end

        {:ok, Path.expand(resolved)}

      {:error, :einval} ->
        # Not a symlink, just expand the path
        if File.exists?(path) do
          {:ok, Path.expand(path)}
        else
          {:error, :enoent}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp path_within?(path, root) do
    # Expand both to canonical form
    expanded_path = Path.expand(path)
    expanded_root = Path.expand(root)

    # Check if path starts with root
    String.starts_with?(expanded_path, expanded_root <> "/") or
      expanded_path == expanded_root
  end
end
