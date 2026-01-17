defmodule TrumanShell.Commands.Ls do
  @moduledoc """
  Handler for the `ls` command - list directory contents.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Commands.Behaviour
  alias TrumanShell.Support.Sandbox

  @max_output_lines 200

  @doc """
  Lists directory contents, sorted alphabetically.

  Directories are suffixed with `/`. Output is truncated at 200 lines.

  ## Examples

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> {:ok, output} = TrumanShell.Commands.Ls.handle(["lib"], context)
      iex> output =~ "truman_shell/"
      true

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Ls.handle(["nonexistent"], context)
      {:error, "ls: nonexistent: No such file or directory\\n"}

      iex> context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}
      iex> TrumanShell.Commands.Ls.handle(["-la"], context)
      {:error, "ls: invalid option -- 'la'\\n"}

  """
  @spec handle(Behaviour.args(), Behaviour.context()) :: Behaviour.result()
  @impl true
  def handle(args, context) do
    with {:ok, paths} <- validate_args(args) do
      list_paths(paths, context)
    end
  end

  # Argument validation - returns {:ok, paths} or {:error, msg}
  defp validate_args(args) do
    {flags, paths} = Enum.split_with(args, &String.starts_with?(&1, "-"))

    cond do
      flags != [] ->
        flag = hd(flags)
        {:error, "ls: invalid option -- '#{String.trim_leading(flag, "-")}'\n"}

      true ->
        # Default to "." if no paths specified
        {:ok, if(paths == [], do: ["."], else: paths)}
    end
  end

  # List one or more paths
  defp list_paths([path], context) do
    # Single path: list contents (directory) or just the file
    list_single_path(path, context)
  end

  defp list_paths(paths, context) do
    # Multiple paths: list each, collecting results
    results =
      Enum.map(paths, fn path ->
        case list_single_path(path, context) do
          {:ok, output} -> {:ok, path, output}
          {:error, msg} -> {:error, path, msg}
        end
      end)

    # Collect errors and successes
    {errors, successes} = Enum.split_with(results, &match?({:error, _, _}, &1))

    error_output = Enum.map_join(errors, "", fn {:error, _path, msg} -> msg end)
    success_output = Enum.map_join(successes, "", fn {:ok, _path, output} -> output end)

    output = error_output <> success_output

    if errors == [] do
      {:ok, output}
    else
      # If there were any errors, return error with combined output
      {:error, output}
    end
  end

  # List a single path (file or directory)
  defp list_single_path(path, context) do
    with {:ok, safe_path} <- Sandbox.validate_path(path, context.sandbox_root) do
      cond do
        File.regular?(safe_path) ->
          # It's a file - just output the path
          {:ok, path <> "\n"}

        File.dir?(safe_path) ->
          list_directory(path, safe_path)

        true ->
          {:error, "ls: #{path}: No such file or directory\n"}
      end
    else
      {:error, :outside_sandbox} ->
        {:error, "ls: #{path}: No such file or directory\n"}

      {:error, _reason} ->
        {:error, "ls: #{path}: No such file or directory\n"}
    end
  end

  # List contents of a directory (path already validated)
  defp list_directory(display_path, safe_path) do
    case File.ls(safe_path) do
      {:ok, entries} ->
        sorted = Enum.sort(entries)
        total_count = length(sorted)

        {lines, truncated?} =
          if total_count > @max_output_lines do
            {Enum.take(sorted, @max_output_lines), true}
          else
            {sorted, false}
          end

        output = Enum.map_join(lines, "\n", &format_entry(safe_path, &1))

        final_output =
          if truncated? do
            output <>
              "\n... (#{total_count - @max_output_lines} more entries, #{total_count} total)\n"
          else
            output <> "\n"
          end

        {:ok, final_output}

      {:error, :enoent} ->
        {:error, "ls: #{display_path}: No such file or directory\n"}

      {:error, _reason} ->
        {:error, "ls: #{display_path}: No such file or directory\n"}
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
