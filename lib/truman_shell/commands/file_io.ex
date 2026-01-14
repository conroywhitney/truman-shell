defmodule TrumanShell.Commands.FileIO do
  @moduledoc """
  Shared file I/O functions for command handlers.
  """

  alias TrumanShell.Sanitizer

  # Maximum file size in bytes (100KB) to prevent memory exhaustion
  @max_file_size 100_000

  @doc """
  Read a file with sandbox validation and size limit.

  Resolves the path relative to current_dir, validates it's within
  the sandbox, checks file size, and returns the file contents.

  Files larger than 100KB are rejected to prevent memory exhaustion.
  """
  @spec read_file(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def read_file(path, context) do
    # Resolve path relative to current working directory
    target = Path.expand(path, context.current_dir)
    target_rel = Path.relative_to(target, context.sandbox_root)

    with {:ok, safe_path} <- Sanitizer.validate_path(target_rel, context.sandbox_root),
         :ok <- check_file_size(safe_path),
         {:ok, contents} <- File.read(safe_path) do
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

  # Check if file size is within limit to prevent memory exhaustion
  defp check_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_file_size ->
        {:error, :file_too_large}

      {:ok, _} ->
        :ok

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
end
