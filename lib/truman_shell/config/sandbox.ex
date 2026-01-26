defmodule TrumanShell.Config.Sandbox do
  @moduledoc """
  Sandbox configuration for path validation.

  Defines the boundaries and home base for agent operations. This struct is
  immutable - set once at session start and never modified.

  ## Fields

  - `allowed_paths` - List of directories the agent can access (boundaries)
  - `home_path` - The agent's home directory (for `cd` with no args, .trash, etc.)

  ## Example

      %Config.Sandbox{
        allowed_paths: ["/home/user/project", "/home/user/libs"],
        home_path: "/home/user/project"
      }

  ## YAML Configuration

  In `agents.yaml`, the sandbox section uses these fields:
  - `allowed_paths` - List of directories the agent can access (supports ~ and globs)
  - `home_path` - The agent's home directory (must be within allowed_paths)

  Example:

      sandbox:
        allowed_paths:
          - "~/studios/reification-labs"
          - "~/code/*"
        home_path: "~/studios/reification-labs"

  """

  alias TrumanShell.DomePath

  @type t :: %__MODULE__{
          allowed_paths: [String.t()],
          home_path: String.t()
        }

  @enforce_keys [:allowed_paths, :home_path]
  defstruct [:allowed_paths, :home_path]

  @doc """
  Creates a Sandbox config from the "sandbox" section of agents.yaml.

  Handles:
  - `allowed_paths` - list of directories (with tilde and glob expansion)
  - `home_path` - agent's home directory (with tilde expansion)
  - Validation that all paths exist and are directories
  - Validation that home_path is within allowed_paths

  ## Examples

      iex> yaml = %{"allowed_paths" => [File.cwd!()], "home_path" => File.cwd!()}
      iex> {:ok, sandbox} = TrumanShell.Config.Sandbox.from_yaml(yaml)
      iex> sandbox.home_path == File.cwd!()
      true

  """
  @spec from_yaml(map()) :: {:ok, t()} | {:error, String.t()}
  def from_yaml(yaml) when is_map(yaml) do
    with {:ok, raw_paths} <- require_field(yaml, "allowed_paths"),
         {:ok, raw_home} <- require_field(yaml, "home_path") do
      # Expand ~ and globs in allowed_paths
      allowed_paths = expand_paths(raw_paths)

      # Expand ~ in home_path
      home_path = expand_home_path(raw_home, allowed_paths)

      # Validate and return
      with :ok <- validate_paths_exist(allowed_paths),
           :ok <- validate_home_exists(home_path, allowed_paths) do
        {:ok, %__MODULE__{allowed_paths: allowed_paths, home_path: home_path}}
      end
    end
  end

  def from_yaml(_), do: {:error, "sandbox config must be a map"}

  defp require_field(yaml, field) do
    case Map.get(yaml, field) do
      nil -> {:error, "sandbox.#{field} is required"}
      "" -> {:error, "sandbox.#{field} cannot be empty"}
      [] -> {:error, "sandbox.#{field} cannot be empty"}
      value -> {:ok, value}
    end
  end

  @doc """
  Creates default sandbox config using current working directory.

  Used when no agents.yaml is found.
  """
  @spec defaults() :: t()
  def defaults do
    cwd = File.cwd!()
    %__MODULE__{allowed_paths: [cwd], home_path: cwd}
  end

  @doc """
  Creates a Sandbox config from raw values.

  Canonicalizes all paths (resolving `..` segments) and validates that
  home_path is within one of the allowed_paths.

  ## Examples

      iex> TrumanShell.Config.Sandbox.new(["/project"], "/project")
      {:ok, %TrumanShell.Config.Sandbox{allowed_paths: ["/project"], home_path: "/project"}}

      iex> TrumanShell.Config.Sandbox.new(["/project"], "/elsewhere")
      {:error, "home_path must be within one of the allowed_paths"}

      iex> TrumanShell.Config.Sandbox.new(["/project/../project"], "/project")
      {:ok, %TrumanShell.Config.Sandbox{allowed_paths: ["/project"], home_path: "/project"}}

  """
  @spec new([String.t()], String.t()) :: {:ok, t()} | {:error, String.t()}
  def new(allowed_paths, home_path) when is_list(allowed_paths) and is_binary(home_path) do
    # Canonicalize paths at construction time for defense-in-depth
    canonical_paths = Enum.map(allowed_paths, &DomePath.expand/1)
    canonical_home = DomePath.expand(home_path)

    sandbox = %__MODULE__{allowed_paths: canonical_paths, home_path: canonical_home}
    validate(sandbox)
  end

  @doc """
  Validates a Sandbox config struct.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{allowed_paths: []}) do
    {:error, "sandbox must have at least one allowed_path"}
  end

  def validate(%__MODULE__{home_path: home} = sandbox) do
    if path_allowed?(sandbox, home) do
      {:ok, sandbox}
    else
      {:error, "home_path must be within one of the allowed_paths"}
    end
  end

  @doc """
  Checks if an absolute path is within any of the allowed_paths.

  Canonicalizes the path first (resolving `..` segments) to prevent
  path traversal attacks. Callers must expand relative paths before calling
  this function - use `DomePath.expand(path, base)` where base is either
  `home_path` or `current_path` depending on context.

  ## Examples

      iex> sandbox = %TrumanShell.Config.Sandbox{allowed_paths: ["/project"], home_path: "/project"}
      iex> TrumanShell.Config.Sandbox.path_allowed?(sandbox, "/project/src/file.ex")
      true

      iex> sandbox = %TrumanShell.Config.Sandbox{allowed_paths: ["/project"], home_path: "/project"}
      iex> TrumanShell.Config.Sandbox.path_allowed?(sandbox, "/etc/passwd")
      false

      iex> sandbox = %TrumanShell.Config.Sandbox{allowed_paths: ["/project"], home_path: "/project"}
      iex> TrumanShell.Config.Sandbox.path_allowed?(sandbox, "/project/../etc/passwd")
      false

  """
  @spec path_allowed?(t(), String.t()) :: boolean()
  def path_allowed?(%__MODULE__{allowed_paths: allowed_paths}, "/" <> _ = path) do
    canonical_path = DomePath.expand(path)
    Enum.any?(allowed_paths, &DomePath.within?(canonical_path, &1))
  end

  def path_allowed?(%__MODULE__{}, path) when is_binary(path) do
    raise ArgumentError, "path must be absolute, got: #{inspect(path)}"
  end

  # --- Private Functions for YAML parsing ---

  defp expand_paths(raw_paths) when is_list(raw_paths) do
    raw_paths
    |> Enum.flat_map(&expand_path/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp expand_path(path) do
    expanded = expand_user_home(path)

    if String.contains?(expanded, "*") do
      # Glob expansion - ensure results are absolute paths
      expanded
      |> DomePath.wildcard()
      |> Enum.filter(&File.dir?/1)
      |> Enum.map(&DomePath.expand/1)
    else
      [DomePath.expand(expanded)]
    end
  end

  defp expand_home_path(raw_path, _allowed_paths) do
    expanded = expand_user_home(raw_path)
    # home_path must be absolute (after ~ expansion)
    DomePath.expand(expanded)
  end

  defp validate_paths_exist([]) do
    {:error, "sandbox must have at least one allowed_path"}
  end

  defp validate_paths_exist(paths) do
    Enum.reduce_while(paths, :ok, fn path, :ok ->
      case File.stat(path) do
        {:ok, %{type: :directory}} ->
          {:cont, :ok}

        {:ok, %{type: _other}} ->
          {:halt, {:error, "allowed_path is not a directory: #{path}"}}

        {:error, :enoent} ->
          {:halt, {:error, "allowed_path does not exist: #{path}"}}

        {:error, reason} ->
          {:halt, {:error, "cannot access allowed_path #{path}: #{reason}"}}
      end
    end)
  end

  defp validate_home_exists(home_path, allowed_paths) do
    # Build a temporary sandbox to check if home is within allowed_paths
    sandbox = %__MODULE__{allowed_paths: allowed_paths, home_path: home_path}

    case File.stat(home_path) do
      {:ok, %{type: :directory}} ->
        if path_allowed?(sandbox, home_path) do
          :ok
        else
          {:error, "home_path must be within one of the allowed_paths: #{home_path}"}
        end

      {:ok, %{type: _other}} ->
        {:error, "home_path is not a directory: #{home_path}"}

      {:error, :enoent} ->
        {:error, "home_path does not exist: #{home_path}"}

      {:error, reason} ->
        {:error, "cannot access home_path #{home_path}: #{reason}"}
    end
  end

  # Expand ~ to user's home directory (for config paths)
  defp expand_user_home("~"), do: System.user_home!()
  defp expand_user_home("~/" <> rest), do: DomePath.join(System.user_home!(), rest)
  defp expand_user_home(path), do: path
end
