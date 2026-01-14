defmodule TrumanShell.Commands.Grep do
  @moduledoc """
  Handler for the `grep` command - search for patterns in files.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.FileIO
  alias TrumanShell.Sanitizer

  @doc """
  Searches for lines matching a pattern in files.

  Returns lines containing the pattern, one per line.
  With `-r`, searches directories recursively and prefixes matches with filename.

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Grep.handle(["defmodule", "mix.exs"], context)
      iex> output =~ "defmodule TrumanShell.MixProject"
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Grep.handle(["pattern", "nonexistent.txt"], context)
      {:error, "grep: nonexistent.txt: No such file or directory\\n"}

  """
  @impl true
  def handle(["-r", pattern, path], context) do
    search_recursive(pattern, path, context)
  end

  def handle([pattern | paths], context) when paths != [] do
    case search_files(pattern, paths, context, _show_filename = length(paths) > 1) do
      {:ok, matches} -> {:ok, matches}
      {:error, msg} -> {:error, msg}
    end
  end

  def handle(_, _context) do
    {:error, "grep: missing pattern or file operand\n"}
  end

  # Recursive search in directory
  defp search_recursive(pattern, path, context) do
    case Sanitizer.validate_path(path, context.sandbox_root) do
      {:ok, safe_path} ->
        if File.dir?(safe_path) do
          files = find_all_files(safe_path)
          search_files_with_prefix(pattern, files, safe_path, path, context)
        else
          # Single file with -r just searches that file
          search_files(pattern, [path], context, _show_filename = true)
        end

      {:error, :outside_sandbox} ->
        {:error, FileIO.format_error("grep", "#{path}: No such file or directory")}
    end
  end

  # Find all regular files recursively
  defp find_all_files(dir) do
    dir
    |> File.ls!()
    |> Enum.flat_map(fn entry ->
      full_path = Path.join(dir, entry)

      cond do
        File.dir?(full_path) -> find_all_files(full_path)
        File.regular?(full_path) -> [full_path]
        true -> []
      end
    end)
    |> Enum.sort()
  end

  # Search files and prefix with relative path
  defp search_files_with_prefix(pattern, files, base_path, original_path, context) do
    results =
      Enum.map(files, fn file ->
        relative = Path.relative_to(file, base_path)

        display_path =
          if original_path == "." do
            relative
          else
            Path.join(original_path, relative)
          end

        case FileIO.read_file(file, context) do
          {:ok, contents} ->
            matches =
              contents
              |> String.split("\n")
              |> Enum.filter(&String.contains?(&1, pattern))
              |> Enum.map_join(&"#{display_path}:#{&1}\n")

            {:ok, matches}

          {:error, _msg} ->
            # Skip files that can't be read (e.g., binary files, permission issues)
            {:ok, ""}
        end
      end)

    combined = Enum.map_join(results, fn {:ok, m} -> m end)
    {:ok, combined}
  end

  defp search_files(pattern, paths, context, show_filename) do
    Enum.reduce_while(paths, {:ok, ""}, fn path, {:ok, acc} ->
      case search_file(pattern, path, context, show_filename) do
        {:ok, matches} ->
          {:cont, {:ok, acc <> matches}}

        {:error, msg} ->
          {:halt, {:error, FileIO.format_error("grep", msg)}}
      end
    end)
  end

  defp search_file(pattern, path, context, show_filename) do
    case FileIO.read_file(path, context) do
      {:ok, contents} ->
        matches =
          contents
          |> String.split("\n")
          |> Enum.filter(&String.contains?(&1, pattern))
          |> Enum.map_join(&format_match(&1, path, show_filename))

        {:ok, matches}

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp format_match(line, path, true), do: "#{path}:#{line}\n"
  defp format_match(line, _path, false), do: line <> "\n"
end
