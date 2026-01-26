defmodule TrumanShell.Stages.Executor do
  @moduledoc """
  Executes parsed commands in a sandboxed environment.

  All filesystem operations are confined to the sandbox root directory.
  Attempts to access paths outside the sandbox return "not found" errors
  (404 principle - no information leakage about protected paths).

  Command handlers are implemented in `TrumanShell.Commands.*` modules.

  ## Memory Model

  Piping is synchronous and in-memory: each stage passes a full binary string
  to the next. For `cat file | grep pattern | head -5`, the entire file content
  flows through each stage as a string.

  **Mitigations:**
  - FileIO enforces a 10MB per-file limit (see `TrumanShell.Support.FileIO`)
  - Pipeline depth is limited to 10 commands

  **Acceptable for:** AI agent sandbox with controlled inputs (small files)
  **Not suitable for:** Processing large files (would need streaming/GenStage)
  """

  alias TrumanShell.Command
  alias TrumanShell.Commands
  alias TrumanShell.Commands.Context
  alias TrumanShell.Stages.Redirector

  # Maximum number of commands in a pipeline (e.g., cmd1 | cmd2 | cmd3 = 3 commands)
  # 9 pipe operators connect 10 commands maximum
  @max_pipeline_commands 10

  @doc """
  Executes a parsed command and returns the output.

  Returns `{:ok, output}` on success or `{:error, message}` on failure.

  ## Arguments

    * `command` - Parsed Command struct from Parser/Expander
    * `ctx` - Execution context with current_path and sandbox_config

  ## Examples

      iex> alias TrumanShell.Command
      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> cmd = %Command{name: :cmd_ls, args: ["lib"], pipes: [], redirects: []}
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> {:ok, output, _ctx} = TrumanShell.Stages.Executor.run(cmd, ctx)
      iex> output =~ "truman_shell"
      true

      iex> alias TrumanShell.Command
      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> cmd = %Command{name: {:unknown, "fake"}, args: [], pipes: [], redirects: []}
      iex> config = %SandboxConfig{allowed_paths: [File.cwd!()], home_path: File.cwd!()}
      iex> ctx = %Context{current_path: File.cwd!(), sandbox_config: config}
      iex> TrumanShell.Stages.Executor.run(cmd, ctx)
      {:error, "bash: fake: command not found\\n"}

  """
  @spec run(Command.t(), Context.t()) :: {:ok, String.t(), Context.t()} | {:error, String.t()}
  def run(%Command{pipes: pipes} = command, %Context{} = ctx) do
    # Get redirects from the LAST command in pipeline (most common: cmd1 | cmd2 > file.txt)
    final_command = if pipes == [], do: command, else: List.last(pipes)

    with :ok <- validate_depth(command),
         {:ok, output, ctx} <- execute(command, ctx),
         {:ok, piped_output, ctx} <- run_pipeline(output, pipes, ctx),
         {:ok, final_output} <- Redirector.apply(piped_output, final_command.redirects, ctx) do
      {:ok, final_output, ctx}
    end
  end

  # Execute each pipe stage, passing ctx through (cd can update current_path)
  defp run_pipeline(output, [], ctx), do: {:ok, output, ctx}

  defp run_pipeline(output, [%Command{} = next_cmd | rest], ctx) do
    # Pass previous output as stdin in ctx
    ctx_with_stdin = %{ctx | stdin: output}

    case execute(next_cmd, ctx_with_stdin) do
      {:ok, next_output, new_ctx} -> run_pipeline(next_output, rest, new_ctx)
      {:error, _} = error -> error
    end
  end

  # styler:sort
  # Command dispatch - maps command atoms to handler modules
  @command_modules %{
    cmd_cat: Commands.Cat,
    cmd_cd: Commands.Cd,
    cmd_cp: Commands.Cp,
    cmd_date: Commands.Date,
    cmd_echo: Commands.Echo,
    cmd_false: Commands.False,
    cmd_find: Commands.Find,
    cmd_grep: Commands.Grep,
    cmd_head: Commands.Head,
    cmd_ls: Commands.Ls,
    cmd_mkdir: Commands.Mkdir,
    cmd_mv: Commands.Mv,
    cmd_pwd: Commands.Pwd,
    cmd_rm: Commands.Rm,
    cmd_tail: Commands.Tail,
    cmd_touch: Commands.Touch,
    cmd_true: Commands.True,
    cmd_wc: Commands.Wc,
    cmd_which: Commands.Which
  }

  @doc """
  Returns the list of supported command names.

  Used by commands like `which` to avoid duplicating the command registry.

  ## Examples

      iex> commands = TrumanShell.Stages.Executor.supported_commands()
      iex> "ls" in commands
      true
      iex> "notreal" in commands
      false

  """
  @spec supported_commands() :: [String.t()]
  def supported_commands do
    @command_modules
    |> Map.keys()
    |> Enum.map(fn atom ->
      atom |> Atom.to_string() |> String.replace_prefix("cmd_", "")
    end)
  end

  defp execute(%Command{name: name, args: args}, %Context{} = ctx) when is_map_key(@command_modules, name) do
    module = @command_modules[name]

    case module.handle(args, ctx) do
      # cd returns updated ctx with new current_path
      {:ok, output, ctx: new_ctx} ->
        {:ok, output, new_ctx}

      # Normal success - ctx unchanged
      {:ok, output} ->
        {:ok, output, ctx}

      # Error pass through
      {:error, _} = error ->
        error
    end
  end

  defp execute(%Command{name: {:unknown, name}}, _ctx) do
    {:error, "bash: #{name}: command not found\n"}
  end

  # Depth validation for pipelines
  defp validate_depth(%Command{pipes: pipes}) do
    command_count = length(pipes) + 1

    if command_count > @max_pipeline_commands do
      {:error, "pipeline too deep: #{command_count} commands (max #{@max_pipeline_commands})\n"}
    else
      :ok
    end
  end
end
