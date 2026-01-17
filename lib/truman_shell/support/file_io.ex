defmodule TrumanShell.Support.FileIO do
  @moduledoc """
  Shared file I/O functions for command handlers.
  """

  alias TrumanShell.Support.Sanitizer

  # Maximum file size in bytes (10MB) to prevent memory exhaustion
  # Large enough for most source files, small enough to prevent OOM attacks
  @max_file_size 10_000_000

  @doc """
  Read a file with sandbox validation and size limit.

  Resolves the path relative to current_dir, validates it's within
  the sandbox, and returns the file contents (max 10MB).

  Uses `IO.binread/2` with a limit to prevent TOCTOU race conditions
  between size check and read. This is safer than `File.stat` + `File.read`.

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, content} = TrumanShell.Support.FileIO.read_file("mix.exs", context)
      iex> content =~ "defmodule TrumanShell.MixProject"
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Support.FileIO.read_file("nonexistent.txt", context)
      {:error, "nonexistent.txt: No such file or directory"}

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Support.FileIO.read_file("/etc/passwd", context)
      {:error, "/etc/passwd: No such file or directory"}

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
        {:error, "#{path}: File too large (max #{div(@max_file_size, 1_000_000)}MB)"}

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

  ## Examples

      iex> TrumanShell.Support.FileIO.format_error("cat", "file.txt: No such file")
      "cat: file.txt: No such file\\n"

      iex> TrumanShell.Support.FileIO.format_error("head", "invalid number")
      "head: invalid number\\n"

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

  ## Examples

      iex> TrumanShell.Support.FileIO.parse_line_count_args(["-n", "5", "file.txt"])
      {:ok, 5, "file.txt"}

      iex> TrumanShell.Support.FileIO.parse_line_count_args(["-20", "file.txt"])
      {:ok, 20, "file.txt"}

      iex> TrumanShell.Support.FileIO.parse_line_count_args(["file.txt"])
      {:ok, 10, "file.txt"}

      iex> TrumanShell.Support.FileIO.parse_line_count_args(["-n", "abc", "file.txt"])
      {:error, "invalid number of lines: 'abc'"}

  """
  @spec parse_line_count_args(list(String.t())) ::
          {:ok, pos_integer(), String.t()} | {:error, String.t()}
  def parse_line_count_args(["-n", n_str | rest]) do
    case parse_positive_int(n_str) do
      {:ok, n} -> {:ok, n, List.first(rest) || "-"}
      :error -> {:error, "invalid number of lines: '#{n_str}'"}
    end
  end

  def parse_line_count_args(["-" <> n_str | rest]) when n_str != "" do
    case parse_positive_int(n_str) do
      {:ok, n} -> {:ok, n, List.first(rest) || "-"}
      :error -> {:error, "invalid number of lines: '-#{n_str}'"}
    end
  end

  def parse_line_count_args([path]), do: {:ok, 10, path}
  def parse_line_count_args([]), do: {:ok, 10, "-"}

  defp parse_positive_int(str) do
    case Integer.parse(str) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end
end
