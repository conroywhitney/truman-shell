defmodule TrumanShell.Executor do
  @moduledoc """
  Executes parsed commands in a sandboxed environment.
  """

  alias TrumanShell.Command

  @max_pipe_depth 10

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
    case File.ls(path) do
      {:ok, entries} ->
        output =
          entries
          |> Enum.sort()
          |> Enum.map(&format_entry(path, &1))
          |> Enum.join("\n")

        {:ok, output <> "\n"}

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
