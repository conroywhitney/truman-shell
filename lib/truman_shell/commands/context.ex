defmodule TrumanShell.Commands.Context do
  @moduledoc """
  Runtime context for command execution.

  Contains the dynamic state (current_path) and static configuration (sandbox_config)
  that commands need to operate.

  ## Fields

  - `current_path` - The current working directory (changes with `cd`)
  - `sandbox_config` - Immutable sandbox configuration (boundaries and home)
  - `stdin` - Optional input from piped commands

  ## Example

      %Context{
        current_path: "/project/lib",
        sandbox_config: %Config.Sandbox{
          allowed_paths: ["/project"],
          home_path: "/project"
        }
      }

  ## Construction

  Context should be built using `from_config/1`, not constructed directly:

      {:ok, config} = TrumanShell.Config.discover()
      ctx = TrumanShell.Commands.Context.from_config(config)

  """

  alias TrumanShell.Config
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @type t :: %__MODULE__{
          current_path: String.t(),
          sandbox_config: SandboxConfig.t(),
          stdin: String.t() | nil
        }

  @enforce_keys [:current_path, :sandbox_config]
  defstruct [:current_path, :sandbox_config, :stdin]

  @doc """
  Creates a Context from a loaded Config.

  Sets `current_path` to `home_path` (the starting directory).

  ## Examples

      iex> config = TrumanShell.Config.defaults()
      iex> ctx = TrumanShell.Commands.Context.from_config(config)
      iex> ctx.current_path == ctx.sandbox_config.home_path
      true

  """
  @spec from_config(Config.t()) :: t()
  def from_config(%Config{sandbox: sandbox}) do
    %__MODULE__{
      current_path: sandbox.home_path,
      sandbox_config: sandbox
    }
  end
end
