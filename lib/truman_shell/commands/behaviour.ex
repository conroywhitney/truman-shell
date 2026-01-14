defmodule TrumanShell.Commands.Behaviour do
  @moduledoc """
  Behaviour for Truman Shell command handlers.

  Each command module implements `handle/2` which receives:
  - `args` - List of command arguments (already parsed)
  - `context` - Map containing execution context:
    - `:sandbox_root` - Absolute path to sandbox directory
    - `:current_dir` - Current working directory (absolute)

  Commands return `{:ok, output}` or `{:error, message}`.
  """

  @type args :: [String.t()]
  @type context :: %{
          sandbox_root: String.t(),
          current_dir: String.t()
        }
  @type result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Execute the command with given arguments and context.
  """
  @callback handle(args(), context()) :: result()
end
