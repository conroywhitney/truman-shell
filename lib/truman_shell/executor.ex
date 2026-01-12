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

  @doc "Returns the maximum output lines limit (for testing/introspection)"
  def max_output_lines, do: @max_output_lines

  # Default sandbox is current working directory
  # Can be overridden via run/2 options in the future
  defp sandbox_root, do: File.cwd!()

  @doc """
  Executes a parsed command and returns the output.

  Returns `{:ok, output}` on success or `{:error, message}` on failure.
  """
  @spec run(Command.t()) :: {:ok, String.t()} | {:error, String.t()}
  def run(%Command{} = command) do
    with :ok <- validate_depth(command) do
      execute(command)
    end
  end

  # Dispatch to command handlers
  defp execute(%Command{name: :cmd_ls, args: args}) do
    path = List.first(args) || "."
    handle_ls(path)
  end

  defp execute(%Command{name: {:unknown, name}}) do
    {:error, "bash: #{name}: command not found\n"}
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
          output <> "\n... (#{total_count - @max_output_lines} more entries, #{total_count} total)\n"
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
