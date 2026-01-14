defmodule TrumanShell.Executor do
  @moduledoc """
  Executes parsed commands in a sandboxed environment.

  All filesystem operations are confined to the sandbox root directory.
  Attempts to access paths outside the sandbox return "not found" errors
  (404 principle - no information leakage about protected paths).

  Command handlers are implemented in `TrumanShell.Commands.*` modules.
  """

  alias TrumanShell.Command
  alias TrumanShell.Commands
  alias TrumanShell.Sanitizer

  @max_pipe_depth 10

  @doc """
  Executes a parsed command and returns the output.

  Returns `{:ok, output}` on success or `{:error, message}` on failure.

  ## Options

    * `:sandbox_root` - Root directory for sandbox confinement.
      Defaults to `File.cwd!()`. All file operations are restricted
      to this directory and its subdirectories.

  ## Examples

      iex> alias TrumanShell.Command
      iex> cmd = %Command{name: :cmd_ls, args: ["lib"], pipes: [], redirects: []}
      iex> {:ok, output} = TrumanShell.Executor.run(cmd)
      iex> output =~ "truman_shell"
      true

      iex> alias TrumanShell.Command
      iex> cmd = %Command{name: {:unknown, "fake"}, args: [], pipes: [], redirects: []}
      iex> TrumanShell.Executor.run(cmd)
      {:error, "bash: fake: command not found\\n"}

  """
  @spec run(Command.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(command, opts \\ [])

  def run(%Command{redirects: redirects} = command, opts) do
    if root = Keyword.get(opts, :sandbox_root) do
      set_sandbox_root(Path.expand(root))
    end

    with :ok <- validate_depth(command),
         {:ok, output} <- execute(command) do
      apply_redirects(output, redirects)
    end
  end

  # styler:sort
  # Command dispatch - maps command atoms to handler modules
  @command_modules %{
    cmd_cat: Commands.Cat,
    cmd_cd: Commands.Cd,
    cmd_cp: Commands.Cp,
    cmd_echo: Commands.Echo,
    cmd_head: Commands.Head,
    cmd_ls: Commands.Ls,
    cmd_mkdir: Commands.Mkdir,
    cmd_mv: Commands.Mv,
    cmd_pwd: Commands.Pwd,
    cmd_rm: Commands.Rm,
    cmd_tail: Commands.Tail,
    cmd_touch: Commands.Touch
  }

  defp execute(%Command{name: name, args: args}) when is_map_key(@command_modules, name) do
    module = @command_modules[name]
    context = build_context()

    case module.handle(args, context) do
      # Handle side effects from commands like cd
      {:ok, output, set_cwd: new_cwd} ->
        set_current_dir(new_cwd)
        {:ok, output}

      # Normal success/error pass through
      result ->
        result
    end
  end

  defp execute(%Command{name: {:unknown, name}}) do
    {:error, "bash: #{name}: command not found\n"}
  end

  # Context for command handlers
  defp build_context do
    %{
      sandbox_root: sandbox_root(),
      current_dir: current_dir()
    }
  end

  # Depth validation for pipes
  defp validate_depth(%Command{pipes: pipes}) do
    depth = length(pipes) + 1

    if depth > @max_pipe_depth do
      {:error, "pipe depth exceeded (max #{@max_pipe_depth})\n"}
    else
      :ok
    end
  end

  # Redirect handling - apply redirects after command execution
  defp apply_redirects(output, []), do: {:ok, output}

  defp apply_redirects(output, [{:stdout, path} | rest]) do
    write_redirect(output, path, [], rest)
  end

  defp apply_redirects(output, [{:stdout_append, path} | rest]) do
    write_redirect(output, path, [:append], rest)
  end

  defp write_redirect(output, path, write_opts, rest) do
    # Validate the original path first (catches absolute paths outside sandbox)
    case Sanitizer.validate_path(path, sandbox_root()) do
      {:ok, _} ->
        # Then resolve relative to current directory
        target_path = Path.join(current_dir(), path)

        with {:ok, safe_path} <- Sanitizer.validate_path(target_path, sandbox_root()) do
          File.write!(safe_path, output, write_opts)
          apply_redirects("", rest)
        end

      {:error, :outside_sandbox} ->
        {:error, "bash: #{path}: No such file or directory\n"}
    end
  end

  # State management - sandbox root and current directory
  # These are placed at the bottom as they are called by many functions above

  defp set_current_dir(path) do
    Process.put(:truman_cwd, path)
  end

  defp current_dir do
    Process.get(:truman_cwd, sandbox_root())
  end

  defp set_sandbox_root(path) do
    Process.put(:truman_sandbox_root, path)
  end

  defp sandbox_root do
    Process.get(:truman_sandbox_root, File.cwd!())
  end
end
