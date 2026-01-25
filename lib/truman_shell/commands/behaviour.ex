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

  Commands that update context (like `cd`) return `{:ok, output, ctx: new_ctx}`
  with the updated context. The executor passes the new context to subsequent
  commands in a pipeline.
  """

  alias TrumanShell.Commands.Context

  @type args :: [String.t()]
  @type context :: Context.t()

  @typedoc "Standard result for pure commands"
  @type result :: {:ok, String.t()} | {:error, String.t()}

  @typedoc "Result for commands that update context (like cd)"
  @type result_with_ctx :: {:ok, String.t(), [{:ctx, Context.t()}]} | {:error, String.t()}

  @doc """
  Execute the command with given arguments and context.
  """
  @callback handle(args(), context()) :: result()
end
