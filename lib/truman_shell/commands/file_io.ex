defmodule TrumanShell.Commands.FileIO do
  @moduledoc """
  Shared file I/O functions for command handlers.
  """

  alias TrumanShell.Sanitizer

  @doc """
  Read a file with sandbox validation.

  Resolves the path relative to current_dir, validates it's within
  the sandbox, and returns the file contents.
  """
  @spec read_file(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def read_file(path, context) do
    # Resolve path relative to current working directory
    target = Path.expand(path, context.current_dir)
    target_rel = Path.relative_to(target, context.sandbox_root)

    with {:ok, safe_path} <- Sanitizer.validate_path(target_rel, context.sandbox_root),
         {:ok, contents} <- File.read(safe_path) do
      {:ok, contents}
    else
      {:error, :outside_sandbox} ->
        {:error, "#{path}: No such file or directory"}

      {:error, :enoent} ->
        {:error, "#{path}: No such file or directory"}

      {:error, :eisdir} ->
        {:error, "#{path}: Is a directory"}

      {:error, _} ->
        {:error, "#{path}: No such file or directory"}
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
