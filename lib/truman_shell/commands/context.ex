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

  """

  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @type t :: %__MODULE__{
          current_path: String.t(),
          sandbox_config: SandboxConfig.t(),
          stdin: String.t() | nil
        }

  @enforce_keys [:current_path, :sandbox_config]
  defstruct [:current_path, :sandbox_config, :stdin]
end
