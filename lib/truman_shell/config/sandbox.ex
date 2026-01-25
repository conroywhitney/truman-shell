defmodule TrumanShell.Config.Sandbox do
  @moduledoc """
  Sandbox configuration for path validation.

  Defines the boundaries (roots) and home base (default_cwd) for agent operations.

  ## Fields

  - `roots` - List of directories the agent can access (boundaries)
  - `default_cwd` - Working directory for command execution (home base)

  ## Example

      %Config.Sandbox{
        roots: ["/home/user/project", "/home/user/libs"],
        default_cwd: "/home/user/project"
      }

  """

  alias TrumanShell.DomePath

  @type t :: %__MODULE__{
          roots: [String.t()],
          default_cwd: String.t()
        }

  @enforce_keys [:roots, :default_cwd]
  defstruct [:roots, :default_cwd]

  @doc """
  Creates a Sandbox config from raw values.

  Canonicalizes all paths (resolving `..` segments) and validates that
  default_cwd is within one of the roots.

  ## Examples

      iex> TrumanShell.Config.Sandbox.new(["/project"], "/project")
      {:ok, %TrumanShell.Config.Sandbox{roots: ["/project"], default_cwd: "/project"}}

      iex> TrumanShell.Config.Sandbox.new(["/project"], "/elsewhere")
      {:error, "default_cwd must be within one of the roots"}

      iex> TrumanShell.Config.Sandbox.new(["/project/../project"], "/project")
      {:ok, %TrumanShell.Config.Sandbox{roots: ["/project"], default_cwd: "/project"}}

  """
  @spec new([String.t()], String.t()) :: {:ok, t()} | {:error, String.t()}
  def new(roots, default_cwd) when is_list(roots) and is_binary(default_cwd) do
    # Canonicalize paths at construction time for defense-in-depth
    canonical_roots = Enum.map(roots, &DomePath.expand/1)
    canonical_cwd = DomePath.expand(default_cwd)

    sandbox = %__MODULE__{roots: canonical_roots, default_cwd: canonical_cwd}
    validate(sandbox)
  end

  @doc """
  Validates a Sandbox config struct.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{roots: [], default_cwd: _}) do
    {:error, "sandbox must have at least one root"}
  end

  def validate(%__MODULE__{default_cwd: cwd} = sandbox) do
    if path_allowed?(sandbox, cwd) do
      {:ok, sandbox}
    else
      {:error, "default_cwd must be within one of the roots"}
    end
  end

  @doc """
  Checks if a path is within any of the sandbox roots.

  Canonicalizes the path first (resolving `..` segments) to prevent
  path traversal attacks. Relative paths are expanded against `default_cwd`,
  not the process CWD. Delegates to `DomePath.within?/2` for boundary check.
  Symlink detection happens at the DomePath.validate level when accessing files.

  ## Examples

      iex> sandbox = %TrumanShell.Config.Sandbox{roots: ["/project"], default_cwd: "/project"}
      iex> TrumanShell.Config.Sandbox.path_allowed?(sandbox, "/project/src/file.ex")
      true

      iex> sandbox = %TrumanShell.Config.Sandbox{roots: ["/project"], default_cwd: "/project"}
      iex> TrumanShell.Config.Sandbox.path_allowed?(sandbox, "/etc/passwd")
      false

      iex> sandbox = %TrumanShell.Config.Sandbox{roots: ["/project"], default_cwd: "/project"}
      iex> TrumanShell.Config.Sandbox.path_allowed?(sandbox, "/project/../etc/passwd")
      false

      iex> sandbox = %TrumanShell.Config.Sandbox{roots: ["/project"], default_cwd: "/project/src"}
      iex> TrumanShell.Config.Sandbox.path_allowed?(sandbox, "file.ex")
      true

  """
  @spec path_allowed?(t(), String.t()) :: boolean()
  def path_allowed?(%__MODULE__{roots: roots, default_cwd: default_cwd}, path) do
    # Canonicalize path, expanding relative paths against default_cwd
    canonical_path =
      case DomePath.type(path) do
        :absolute -> DomePath.expand(path)
        :relative -> DomePath.expand(path, default_cwd)
      end

    Enum.any?(roots, &DomePath.within?(canonical_path, &1))
  end
end
