defmodule TrumanShell.Commands.FileIO do
  @moduledoc """
  Shared file I/O functions for command handlers.
  """

  alias TrumanShell.Posix.Args
  alias TrumanShell.Sanitizer

  # Maximum file size in bytes (100KB) to prevent memory exhaustion
  @max_file_size 100_000

  @doc """
  Read a file with sandbox validation and size limit.

  Resolves the path relative to current_dir, validates it's within
  the sandbox, and returns the file contents (max 100KB).

  Uses `IO.binread/2` with a limit to prevent TOCTOU race conditions
  between size check and read. This is safer than `File.stat` + `File.read`.
  """
  @spec read_file(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def read_file(path, context) do
    # Resolve path relative to current working directory
    target = Path.expand(path, context.current_dir)
    target_rel = Path.relative_to(target, context.sandbox_root)

    with {:ok, safe_path} <- Sanitizer.validate_path(target_rel, context.sandbox_root),
         {:ok, contents} <- read_with_limit(safe_path) do
      {:ok, contents}
    else
      {:error, :outside_sandbox} ->
        {:error, "#{path}: No such file or directory"}

      {:error, :enoent} ->
        {:error, "#{path}: No such file or directory"}

      {:error, :eisdir} ->
        {:error, "#{path}: Is a directory"}

      {:error, :file_too_large} ->
        {:error, "#{path}: File too large (max #{div(@max_file_size, 1000)}KB)"}

      {:error, _} ->
        {:error, "#{path}: No such file or directory"}
    end
  end

  # Read file with size limit using IO.binread to prevent TOCTOU race
  # Opens file and reads up to limit+1 bytes in one operation
  defp read_with_limit(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        try do
          case IO.binread(file, @max_file_size + 1) do
            :eof ->
              {:ok, ""}

            {:error, reason} ->
              {:error, reason}

            data when byte_size(data) > @max_file_size ->
              {:error, :file_too_large}

            data ->
              {:ok, data}
          end
        after
          File.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Format an error message with command prefix.
  """
  @spec format_error(String.t(), String.t()) :: String.t()
  def format_error(cmd, msg) do
    "#{cmd}: #{msg}\n"
  end

  @doc """
  Parse line count arguments for head/tail commands.

  Supports formats:
    - `-n NUM` (e.g., `-n 5`)
    - `-NUM` (e.g., `-5`)
    - Just filename (defaults to 10 lines)

  Returns `{:ok, count, path}` or `{:error, message}`.
  """
  @spec parse_line_count_args(list(String.t())) ::
          {:ok, pos_integer(), String.t()} | {:error, String.t()}
  def parse_line_count_args(args) do
    # Try -n NUM format first using shared utility
    case Args.parse_int_flag(args, "-n") do
      {:ok, n, rest} when n > 0 ->
        {:ok, n, List.first(rest) || "-"}

      {:ok, _n, _rest} ->
        {:error, "invalid number of lines: must be positive"}

      {:error, _msg} ->
        {:error, "invalid number of lines"}

      {:not_found, args} ->
        # Fall back to -NUM shorthand or just path
        parse_shorthand_or_path(args)
    end
  end

  # Handle -NUM shorthand (e.g., -5) or just a path
  defp parse_shorthand_or_path(["-" <> n_str | rest]) when n_str != "" do
    case Integer.parse(n_str) do
      {n, ""} when n > 0 -> {:ok, n, List.first(rest) || "-"}
      _ -> {:error, "invalid number of lines: '-#{n_str}'"}
    end
  end

  defp parse_shorthand_or_path([path]), do: {:ok, 10, path}
  defp parse_shorthand_or_path([]), do: {:ok, 10, "-"}
end
