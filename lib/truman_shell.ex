defmodule TrumanShell do
  @moduledoc """
  TrumanShell - A simulated shell environment for AI agents.

  Named after "The Truman Show" - the agent lives in a convincing
  simulation without knowing it.

  ## Key Properties

  1. **Convincing simulation** - Implements enough Unix commands that agents don't question it
  2. **Reversible operations** - `rm` moves to `.trash`, not permanent delete
  3. **Pattern-matched security** - Elixir pattern matching blocks unauthorized paths
  4. **The 404 Principle** - Protected paths return "not found" not "permission denied"

  ## Example

      iex> TrumanShell.parse("ls -la /tmp")
      {:ok, %TrumanShell.Command{
        name: :cmd_ls,
        args: ["-la", "/tmp"],
        pipes: [],
        redirects: []
      }}

  """

  alias TrumanShell.Commands.Context
  alias TrumanShell.Config
  alias TrumanShell.Stages.Executor
  alias TrumanShell.Stages.Expander
  alias TrumanShell.Stages.Parser

  @doc """
  Parse and execute a shell command string.

  This is the main entry point for running commands. It parses the input,
  validates it, and executes it in the sandboxed environment.

  ## Arguments

    * `input` - The shell command string to execute
    * `ctx` - Optional context (if nil, loads from Config.discover())

  Returns `{:ok, output, ctx}` on success or `{:error, reason}` on failure.
  The returned context may have updated `current_path` (e.g., after `cd`).

  ## Stateless Design

  Each call to `execute/1` (without context) creates a fresh context from config.
  To maintain state across commands (e.g., `cd` persistence), pass the returned
  context to the next call:

      {:ok, _, ctx} = TrumanShell.execute("cd lib")
      {:ok, output, ctx} = TrumanShell.execute("ls", ctx)

  ## Examples

      iex> {:ok, output, _ctx} = TrumanShell.execute("ls lib")
      iex> output =~ "truman_shell.ex"
      true

      iex> TrumanShell.execute("")
      {:error, "Empty command"}

      iex> match?({:error, _}, TrumanShell.execute("ls nonexistent_path_12345"))
      true

  """
  @spec execute(String.t(), Context.t() | nil) :: {:ok, String.t(), Context.t()} | {:error, String.t()}
  def execute(input, ctx \\ nil)

  def execute(input, nil) do
    # No context provided - load from config
    with {:ok, config} <- Config.discover() do
      ctx = Context.from_config(config)
      execute(input, ctx)
    end
  end

  def execute(input, %Context{} = ctx) do
    # Context provided - use it directly
    # Pipeline: Tokenizer → Parser → Expander → Executor → Redirector
    with {:ok, command} <- parse(input),
         expanded = Expander.expand(command, ctx),
         {:ok, output, final_ctx} <- Executor.run(expanded, ctx) do
      # Clear stdin to prevent leakage between chained commands in REPL usage
      {:ok, output, %{final_ctx | stdin: nil}}
    end
  end

  @doc """
  Parse a shell command string into a structured Command.

  Returns `{:ok, command}` on success or `{:error, reason}` on failure.

  ## Simple Commands

      iex> TrumanShell.parse("pwd")
      {:ok, %TrumanShell.Command{name: :cmd_pwd, args: []}}

      iex> TrumanShell.parse("ls -la /tmp")
      {:ok, %TrumanShell.Command{name: :cmd_ls, args: ["-la", "/tmp"]}}

      iex> TrumanShell.parse("cd ~")
      {:ok, %TrumanShell.Command{name: :cmd_cd, args: ["~"]}}

  ## Pipes

      iex> {:ok, cmd} = TrumanShell.parse("cat file.txt | grep pattern")
      iex> cmd.name
      :cmd_cat
      iex> cmd.args
      ["file.txt"]
      iex> length(cmd.pipes)
      1
      iex> hd(cmd.pipes).name
      :cmd_grep

      iex> {:ok, cmd} = TrumanShell.parse("ls | grep foo | head -5")
      iex> cmd.name
      :cmd_ls
      iex> length(cmd.pipes)
      2

  ## Redirects

      iex> {:ok, cmd} = TrumanShell.parse("echo hello > output.txt")
      iex> cmd.redirects
      [{:stdout, "output.txt"}]

      iex> {:ok, cmd} = TrumanShell.parse("echo more >> log.txt")
      iex> cmd.redirects
      [{:stdout_append, "log.txt"}]

      iex> {:ok, cmd} = TrumanShell.parse("make 2> errors.log")
      iex> cmd.redirects
      [{:stderr, "errors.log"}]

  ## Quoted Strings

      iex> {:ok, cmd} = TrumanShell.parse("echo \\"hello world\\"")
      iex> cmd.args
      ["hello world"]

      iex> {:ok, cmd} = TrumanShell.parse("grep 'pattern with spaces' file.txt")
      iex> cmd.args
      ["pattern with spaces", "file.txt"]

  ## Error Cases

      iex> TrumanShell.parse("")
      {:error, "Empty command"}

      iex> TrumanShell.parse("   ")
      {:error, "Empty command"}

  """
  defdelegate parse(input), to: Parser
end
