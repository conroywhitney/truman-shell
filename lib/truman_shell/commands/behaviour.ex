defmodule TrumanShell.Commands.Behaviour do
  @moduledoc """
  Behaviour for Truman Shell command handlers.

  Each command module implements `handle/2` which receives:
  - `args` - List of command arguments (already parsed)
  - `context` - Map containing execution context:
    - `:sandbox_root` - Absolute path to sandbox directory
    - `:current_dir` - Current working directory (absolute)

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

  @type args :: [String.t()]
  @type context :: %{
          sandbox_root: String.t(),
          current_dir: String.t()
        }

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
