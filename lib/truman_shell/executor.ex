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

  @doc false
  # Internal constant for testing/introspection
  def max_output_lines, do: @max_output_lines

  # Sandbox root - set via run/2 opts or defaults to File.cwd!()
  defp sandbox_root do
    Process.get(:truman_sandbox_root, File.cwd!())
  end

  defp set_sandbox_root(path) do
    Process.put(:truman_sandbox_root, path)
  end

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

  def run(%Command{} = command, opts) do
    # Set sandbox root from opts or use default
    if root = Keyword.get(opts, :sandbox_root) do
      set_sandbox_root(Path.expand(root))
    end

    with :ok <- validate_depth(command) do
      execute(command)
    end
  end

  # Dispatch to command handlers
  defp execute(%Command{name: :cmd_ls, args: args}) do
    with :ok <- validate_ls_args(args) do
      path = List.first(args) || "."
      handle_ls(path)
    end
  end

  defp execute(%Command{name: :cmd_pwd}) do
    {:ok, current_dir() <> "\n"}
  end

  defp execute(%Command{name: :cmd_cd, args: args}) do
    path = List.first(args) || "."
    handle_cd(path)
  end

  defp execute(%Command{name: :cmd_cat, args: args}) do
    handle_cat(args)
  end

  defp execute(%Command{name: :cmd_head, args: args}) do
    handle_head(args)
  end

  defp execute(%Command{name: {:unknown, name}}) do
    {:error, "bash: #{name}: command not found\n"}
  end

  # Current working directory - defaults to sandbox root
  # Will be modified by cd command
  defp current_dir do
    Process.get(:truman_cwd, sandbox_root())
  end

  defp set_current_dir(path) do
    Process.put(:truman_cwd, path)
  end

  # head handler - displays first n lines of a file
  defp handle_head(args) do
    {n, path} = parse_head_args(args)

    case read_file(path) do
      {:ok, contents} ->
        lines = String.split(contents, "\n")
        # Take n lines, rejoin with newlines
        result = lines |> Enum.take(n) |> Enum.join("\n")
        # Add trailing newline if we had content
        {:ok, if(result == "", do: "", else: result <> "\n")}

      {:error, msg} ->
        # Reformat error message from cat to head
        {:error, String.replace(msg, "cat:", "head:")}
    end
  end

  # Parse head arguments: -n NUM or -NUM or just file
  defp parse_head_args(["-n", n_str | rest]) do
    n = String.to_integer(n_str)
    path = List.first(rest) || "-"
    {n, path}
  end

  defp parse_head_args(["-" <> n_str | rest]) when n_str != "" do
    n = String.to_integer(n_str)
    path = List.first(rest) || "-"
    {n, path}
  end

  defp parse_head_args([path]) do
    {10, path}  # Default: 10 lines
  end

  defp parse_head_args([]) do
    {10, "-"}  # Default: 10 lines from stdin
  end

  # cat handler - displays file contents (supports multiple files)
  defp handle_cat(paths) do
    results =
      Enum.reduce_while(paths, {:ok, ""}, fn path, {:ok, acc} ->
        case read_file(path) do
          {:ok, contents} -> {:cont, {:ok, acc <> contents}}
          {:error, msg} -> {:halt, {:error, msg}}
        end
      end)

    results
  end

  # Read a single file with sandbox validation
  defp read_file(path) do
    # Resolve path relative to current working directory
    target = Path.expand(path, current_dir())
    target_rel = Path.relative_to(target, sandbox_root())

    with {:ok, safe_path} <- Sanitizer.validate_path(target_rel, sandbox_root()),
         {:ok, contents} <- File.read(safe_path) do
      {:ok, contents}
    else
      {:error, :outside_sandbox} ->
        {:error, "cat: #{path}: No such file or directory\n"}

      {:error, :enoent} ->
        {:error, "cat: #{path}: No such file or directory\n"}

      {:error, :eisdir} ->
        {:error, "cat: #{path}: Is a directory\n"}

      {:error, _} ->
        {:error, "cat: #{path}: No such file or directory\n"}
    end
  end

  # cd handler - changes current directory within sandbox
  defp handle_cd(path) do
    # Compute target path relative to current working directory
    # Then make it relative to sandbox for validation
    target_abs = Path.expand(path, current_dir())
    target_rel = Path.relative_to(target_abs, sandbox_root())

    with {:ok, safe_path} <- Sanitizer.validate_path(target_rel, sandbox_root()),
         true <- File.dir?(safe_path) do
      set_current_dir(safe_path)
      {:ok, ""}
    else
      {:error, :outside_sandbox} ->
        # 404 principle: don't reveal path exists but is protected
        {:error, "bash: cd: #{path}: No such file or directory\n"}

      false ->
        {:error, "bash: cd: #{path}: No such file or directory\n"}

      {:error, _} ->
        {:error, "bash: cd: #{path}: No such file or directory\n"}
    end
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
