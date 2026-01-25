defmodule TrumanShell.Commands.Behaviour do
  @moduledoc """
  Behaviour for Truman Shell command handlers.

  Each command module implements `handle/2` which receives:
  - `args` - List of command arguments (already parsed)
  - `context` - A `%Commands.Context{}` struct containing:
    - `:current_path` - Current working directory (absolute)
    - `:sandbox_config` - Immutable `%Config.Sandbox{}` with boundaries and home
    - `:stdin` - Optional input from piped commands

  ## Return Types

  Most commands return `{:ok, output}` or `{:error, message}`.

  Commands with **side effects** (like `cd`) return an extended 3-tuple:
  `{:ok, output, side_effects}` where `side_effects` is a keyword list of
  effect directives the executor should apply.

  This pattern separates effect *description* from effect *execution*,
  keeping command handlers pure while allowing them to request state changes.
  The executor is responsible for interpreting and applying these effects.

  ## Available Side Effects

  - `{:set_cwd, path}` - Update the shell's current working directory
  """

  alias TrumanShell.Commands.Context

  @type args :: [String.t()]
  @type context :: Context.t()

  @typedoc "Side effect directives that commands can request"
  @type side_effect :: {:set_cwd, String.t()}

  @typedoc "Standard result for pure commands"
  @type result :: {:ok, String.t()} | {:error, String.t()}

  @typedoc "Extended result for commands with side effects"
  @type result_with_effects :: {:ok, String.t(), [side_effect()]} | {:error, String.t()}

  @doc """
  Execute the command with given arguments and context.
  """
  @callback handle(args(), context()) :: result()
end
