defmodule TrumanShell.Executor do
  @moduledoc """
  Executes parsed commands in a sandboxed environment.

  All filesystem operations are confined to the sandbox root directory.
  Attempts to access paths outside the sandbox return "not found" errors
  (404 principle - no information leakage about protected paths).
  """

  alias TrumanShell.Command
  alias TrumanShell.Sanitizer

  @max_pipe_depth 10
  @max_output_lines 200
  @version "0.1.0"

  @truman_header """
  TRUMAN SHELL v#{@version}
  You are operating in a sandboxed environment. All filesystem operations are staged for review.

  Available capabilities beyond standard bash:
    ::intent "why"     - Declare your intent (helps human review)
    ::checkpoint       - Save current state, allow rollback
    ::ask "question"   - Queue a question for the human (async)
    ::confidence 0.8   - Rate your confidence in this action
    ::stage            - Show pending changes awaiting review
    ::commit           - Request human approval for staged changes

  Standard commands (ls, cat, grep, etc.) work as expected.
  Destructive commands (rm, mv) are soft by default.

  How can I help you today?
  """

  @doc """
  Returns the maximum output lines limit (for testing/introspection).

  ## Examples

      iex> TrumanShell.Executor.max_output_lines()
      200
  """
  def max_output_lines, do: @max_output_lines

  # Default sandbox is current working directory
  # Can be overridden via run/2 options in the future
  defp sandbox_root, do: File.cwd!()

  @doc """
  Executes a parsed command and returns the output.

  Returns `{:ok, output}` on success or `{:error, message}` on failure.

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
  @spec run(Command.t()) :: {:ok, String.t()} | {:error, String.t()}
  def run(%Command{} = command) do
    with :ok <- validate_depth(command) do
      execute(command)
    end
  end

  @doc """
  Executes a command with Truman Shell metadata wrapper.

  Returns enriched output including the Truman header, original command,
  and formatted result. This is designed for agent interaction where
  additional context and capabilities should be communicated.

  Options:
    - `:show_header` - Include the full Truman header (default: true)
    - `:raw_command` - The original command string for display

  ## Examples

      iex> alias TrumanShell.Command
      iex> cmd = %Command{name: :cmd_ls, args: [], pipes: [], redirects: []}
      iex> {:ok, output} = TrumanShell.Executor.run_interactive(cmd, raw_command: "ls")
      iex> output =~ "TRUMAN SHELL"
      true
      iex> output =~ "Your command: `ls`"
      true

  """
  @spec run_interactive(Command.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run_interactive(%Command{} = command, opts \\ []) do
    show_header = Keyword.get(opts, :show_header, true)
    raw_command = Keyword.get(opts, :raw_command, inspect(command.name))

    result = run(command)

    header = if show_header, do: @truman_header <> "\n---\n\n", else: ""

    case result do
      {:ok, output} ->
        wrapped = """
        #{header}Your command: `#{raw_command}`
        Result:
        ```
        #{String.trim(output)}
        ```
        """
        {:ok, wrapped}

      {:error, message} ->
        wrapped = """
        #{header}Your command: `#{raw_command}`
        Error:
        ```
        #{String.trim(message)}
        ```
        """
        {:error, wrapped}
    end
  end

  # Dispatch to command handlers
  defp execute(%Command{name: :cmd_ls, args: args}) do
    with :ok <- validate_ls_args(args) do
      path = List.first(args) || "."
      handle_ls(path)
    end
  end

  defp execute(%Command{name: {:unknown, name}}) do
    {:error, "bash: #{name}: command not found\n"}
  end

  # Argument validation helpers
  defp validate_ls_args(args) do
    {flags, paths} = Enum.split_with(args, &String.starts_with?(&1, "-"))

    cond do
      # Reject any flags (not supported yet)
      flags != [] ->
        flag = hd(flags)
        {:error, "ls: invalid option -- '#{String.trim_leading(flag, "-")}'\n"}

      # Reject multiple paths
      length(paths) > 1 ->
        {:error, "ls: too many arguments\n"}

      true ->
        :ok
    end
  end

  # Depth validation
  defp validate_depth(%Command{pipes: pipes}) do
    depth = length(pipes) + 1

    if depth > @max_pipe_depth do
      {:error, "pipe depth exceeded (max #{@max_pipe_depth})\n"}
    else
      :ok
    end
  end

  # Private handlers

  defp handle_ls(path) do
    with {:ok, safe_path} <- Sanitizer.validate_path(path, sandbox_root()),
         {:ok, entries} <- File.ls(safe_path) do
      sorted = Enum.sort(entries)
      total_count = length(sorted)

      {lines, truncated?} =
        if total_count > @max_output_lines do
          {Enum.take(sorted, @max_output_lines), true}
        else
          {sorted, false}
        end

      output =
        lines
        |> Enum.map(&format_entry(safe_path, &1))
        |> Enum.join("\n")

      final_output =
        if truncated? do
          output <>
            "\n... (#{total_count - @max_output_lines} more entries, #{total_count} total)\n"
        else
          output <> "\n"
        end

      {:ok, final_output}
    else
      {:error, :outside_sandbox} ->
        # 404 principle: don't reveal that path exists but is protected
        {:error, "ls: #{path}: No such file or directory\n"}

      {:error, :enoent} ->
        {:error, "ls: #{path}: No such file or directory\n"}

      {:error, _reason} ->
        {:error, "ls: #{path}: No such file or directory\n"}
    end
  end

  defp format_entry(base_path, name) do
    full_path = Path.join(base_path, name)

    if File.dir?(full_path) do
      name <> "/"
    else
      name
    end
  end
end
