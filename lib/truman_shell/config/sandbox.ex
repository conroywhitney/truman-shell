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

  Validates that default_cwd is within one of the roots.

  ## Examples

      iex> TrumanShell.Config.Sandbox.new(["/project"], "/project")
      {:ok, %TrumanShell.Config.Sandbox{roots: ["/project"], default_cwd: "/project"}}

      iex> TrumanShell.Config.Sandbox.new(["/project"], "/elsewhere")
      {:error, "default_cwd must be within one of the roots"}

  """
  @spec new([String.t()], String.t()) :: {:ok, t()} | {:error, String.t()}
  def new(roots, default_cwd) when is_list(roots) and is_binary(default_cwd) do
    sandbox = %__MODULE__{roots: roots, default_cwd: default_cwd}
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

  Delegates to `DomePath.within?/2` for each root - pure string boundary check.
  Symlink detection happens at the DomePath.validate level when accessing files.

  ## Examples

      iex> sandbox = %TrumanShell.Config.Sandbox{roots: ["/project"], default_cwd: "/project"}
      iex> TrumanShell.Config.Sandbox.path_allowed?(sandbox, "/project/src/file.ex")
      true

      iex> sandbox = %TrumanShell.Config.Sandbox{roots: ["/project"], default_cwd: "/project"}
      iex> TrumanShell.Config.Sandbox.path_allowed?(sandbox, "/etc/passwd")
      false

  """
  @spec path_allowed?(t(), String.t()) :: boolean()
  def path_allowed?(%__MODULE__{roots: roots}, path) do
    Enum.any?(roots, &DomePath.within?(path, &1))
  end
end
