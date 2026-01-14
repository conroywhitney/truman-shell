defmodule TrumanShell.Commands.Find do
  @moduledoc """
  Handler for the `find` command - search for files in a directory hierarchy.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Sanitizer

  @doc """
  Finds files matching a pattern in a directory tree.

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Find.handle([".", "-name", "*.exs"], context)
      iex> output =~ "mix.exs"
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Find.handle(["/etc", "-name", "*.conf"], context)
      {:error, "find: /etc: No such file or directory\\n"}

  """
  @impl true
  def handle([path, "-name", pattern], context) do
    find_files(path, pattern, context)
  end

  def handle([_path, "-name"], _context) do
    {:error, "find: missing argument to '-name'\n"}
  end

  def handle(_, _context) do
    {:error, "find: missing path or -name argument\n"}
  end

  defp find_files(path, pattern, context) do
    case Sanitizer.validate_path(path, context.sandbox_root) do
      {:ok, safe_path} ->
        if File.dir?(safe_path) do
          files = find_matching(safe_path, pattern)
          output = format_output(files, safe_path, path)
          {:ok, output}
        else
          {:error, "find: #{path}: Not a directory\n"}
        end

      {:error, :outside_sandbox} ->
        {:error, "find: #{path}: No such file or directory\n"}
    end
  end

  defp find_matching(dir, pattern) do
    dir
    |> walk_tree()
    |> Enum.filter(&matches_pattern?(&1, pattern))
    |> Enum.sort()
  end

  defp walk_tree(dir) do
    dir
    |> File.ls!()
    |> Enum.flat_map(fn entry ->
      full_path = Path.join(dir, entry)

      cond do
        File.dir?(full_path) -> [full_path | walk_tree(full_path)]
        File.regular?(full_path) -> [full_path]
        true -> []
      end
    end)
  end

  defp matches_pattern?(path, pattern) do
    filename = Path.basename(path)
    # Convert glob pattern to regex
    regex_pattern =
      pattern
      |> Regex.escape()
      |> String.replace("\\*", ".*")
      |> String.replace("\\?", ".")

    Regex.match?(~r/^#{regex_pattern}$/, filename)
  end

  defp format_output(files, base_path, original_path) do
    output =
      Enum.map_join(files, "\n", fn file ->
        relative = Path.relative_to(file, base_path)

        if original_path == "." do
          "./#{relative}"
        else
          Path.join(original_path, relative)
        end
      end)

    output <> "\n"
  end
end
