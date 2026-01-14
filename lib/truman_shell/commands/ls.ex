defmodule TrumanShell.Commands.Ls do
  @moduledoc """
  Handler for the `ls` command - list directory contents.
  """

  @behaviour TrumanShell.Commands.Behaviour

  alias TrumanShell.Sanitizer

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
  @impl true
  def handle(args, context) do
    with :ok <- validate_args(args) do
      path = List.first(args) || "."
      list_directory(path, context)
    end
  end

  # Argument validation
  defp validate_args(args) do
    {flags, paths} = Enum.split_with(args, &String.starts_with?(&1, "-"))

    cond do
      flags != [] ->
        flag = hd(flags)
        {:error, "ls: invalid option -- '#{String.trim_leading(flag, "-")}'\n"}

      length(paths) > 1 ->
        {:error, "ls: too many arguments\n"}

      true ->
        :ok
    end
  end

  defp list_directory(path, context) do
    with {:ok, safe_path} <- Sanitizer.validate_path(path, context.sandbox_root),
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
