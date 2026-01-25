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

  """

  alias TrumanShell.DomePath

  @type t :: %__MODULE__{
          allowed_paths: [String.t()],
          home_path: String.t()
        }

  @enforce_keys [:allowed_paths, :home_path]
  defstruct [:allowed_paths, :home_path]

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
  Checks if a path is within any of the allowed_paths.

  Canonicalizes the path first (resolving `..` segments) to prevent
  path traversal attacks. Relative paths are expanded against `home_path`,
  not the process CWD. Delegates to `DomePath.within?/2` for boundary check.
  Symlink detection happens at the DomePath.validate level when accessing files.

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

      iex> sandbox = %TrumanShell.Config.Sandbox{allowed_paths: ["/project"], home_path: "/project/src"}
      iex> TrumanShell.Config.Sandbox.path_allowed?(sandbox, "file.ex")
      true

  """
  @spec path_allowed?(t(), String.t()) :: boolean()
  def path_allowed?(%__MODULE__{allowed_paths: allowed_paths, home_path: home_path}, path) do
    # Canonicalize path, expanding relative paths against home_path
    canonical_path =
      case DomePath.type(path) do
        :absolute -> DomePath.expand(path)
        :relative -> DomePath.expand(path, home_path)
      end

    Enum.any?(allowed_paths, &DomePath.within?(canonical_path, &1))
  end
end
