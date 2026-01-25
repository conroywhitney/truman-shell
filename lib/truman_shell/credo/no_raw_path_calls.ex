defmodule TrumanShell.Credo.NoRawPathCalls do
  # Dialyzer can't see Credo at compile time (dev dependency)
  # Silence all warnings for this file
  @moduledoc """
  Custom Credo check that disallows direct use of Path.* functions.

  All path operations must go through `TrumanShell.DomePath` to ensure
  consistent security handling and a single point of control.

  ## Why this matters

  DomePath is the ONLY module allowed to use Path.* directly. This provides:
  - Single chokepoint for all path operations
  - Consistent symlink rejection
  - Auditable path handling
  - Prevents security bypasses

  ## Allowed exceptions

  - `lib/truman_shell/dome_path.ex` - THE path module
  - Test files in `test/` - tests may need direct Path.* for setup
  """

  use Credo.Check,
    id: "EX9001",
    base_priority: :high,
    category: :warning,
    exit_status: 1

  @dialyzer [:no_return, :no_match, :no_unused]

  @path_functions ~w(
    absname basename dirname expand extname join relative relative_to
    relative_to_cwd rootname split type wildcard
  )a

  @impl true
  def run(%SourceFile{} = source_file, params) do
    # Skip DomePath itself and test files
    filename = source_file.filename

    cond do
      String.ends_with?(filename, "dome_path.ex") ->
        []

      # Skip test files - handle both "test/..." and "/test/..."
      String.starts_with?(filename, "test/") or String.contains?(filename, "/test/") ->
        []

      true ->
        issue_meta = IssueMeta.for(source_file, params)

        source_file
        |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
        |> Enum.reverse()
    end
  end

  # Match remote calls to Path module
  defp traverse({{:., _meta, [{:__aliases__, _, [:Path]}, function_name]}, meta, _args} = ast, issues, issue_meta)
       when function_name in @path_functions do
    issue = issue_for(issue_meta, meta[:line], function_name)
    {ast, [issue | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, function_name) do
    format_issue(
      issue_meta,
      message:
        "Use DomePath.#{function_name}/... instead of Path.#{function_name}/... " <>
          "(all path operations must go through DomePath)",
      line_no: line_no,
      trigger: "Path.#{function_name}"
    )
  end
end
