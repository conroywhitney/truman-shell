defmodule TrumanShell.Stages.Expander do
  @moduledoc """
  Expands shell syntax in command arguments before execution.

  Handles (in order):
  1. Tilde expansion: `~` → sandbox_root, `~/path` → sandbox_root/path
  2. Glob expansion: `*.ex` → list of matching files

  Runs after Parser, before Executor in the pipeline.

  ## Argument Types

  The Parser stage marks arguments with their expansion behavior:

  - `{:glob, pattern}` - Unquoted args containing `*` wildcards. These get
    both tilde and glob expansion.
  - `String.t()` - Quoted args or args without wildcards. These get tilde
    expansion only (no glob expansion), preserving literal filenames.

  This allows `ls *.txt` to expand globs while `ls "*.txt"` treats it as
  a literal filename (matching bash behavior).
  """

  alias TrumanShell.Command
  alias TrumanShell.Support.Glob
  alias TrumanShell.Support.Tilde

  @doc """
  Expands shell syntax in a Command struct.

  Transforms the command's args and redirect paths, expanding `~` to the sandbox root
  and glob patterns to matching files. Also recursively expands piped commands.

  ## Context

  Requires a context map with:
  - `:sandbox_root` - Root directory for tilde expansion and sandbox constraint
  - `:current_dir` - Current working directory for glob expansion

  ## Examples

      iex> alias TrumanShell.Command
      iex> alias TrumanShell.Stages.Expander
      iex> cmd = %Command{name: "cat", args: ["~/file.txt"], redirects: [], pipes: []}
      iex> ctx = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}
      iex> Expander.expand(cmd, ctx)
      %Command{name: "cat", args: ["/sandbox/file.txt"], redirects: [], pipes: []}

      iex> alias TrumanShell.Command
      iex> alias TrumanShell.Stages.Expander
      iex> cmd = %Command{name: "echo", args: ["hi"], redirects: [{:stdout, "~/out.txt"}], pipes: []}
      iex> ctx = %{sandbox_root: "/sandbox", current_dir: "/sandbox"}
      iex> Expander.expand(cmd, ctx)
      %Command{name: "echo", args: ["hi"], redirects: [{:stdout, "/sandbox/out.txt"}], pipes: []}

  """
  @spec expand(Command.t(), map()) :: Command.t()
  def expand(%Command{args: args, redirects: redirects, pipes: pipes} = command, context) do
    expanded_args = Enum.flat_map(args, &expand_arg(&1, context))
    expanded_redirects = Enum.map(redirects, &expand_redirect(&1, context))
    expanded_pipes = Enum.map(pipes, &expand(&1, context))

    %{command | args: expanded_args, redirects: expanded_redirects, pipes: expanded_pipes}
  end

  # Expand a {:glob, pattern} argument - tilde expansion then glob expansion
  # Glob.expand/2 returns [String.t()] if matches found, or String.t() if no matches
  defp expand_arg({:glob, pattern}, context) do
    expanded = Tilde.expand(pattern, context.sandbox_root)

    case Glob.expand(expanded, context) do
      files when is_list(files) -> files
      pattern when is_binary(pattern) -> [pattern]
    end
  end

  # Expand a literal string argument - tilde expansion only, NO glob expansion
  # This handles quoted args like "*.txt" which should remain literal
  defp expand_arg(arg, context) when is_binary(arg) do
    [Tilde.expand(arg, context.sandbox_root)]
  end

  # Expand tilde in redirect path
  defp expand_redirect({type, path}, context) when is_binary(path) do
    {type, Tilde.expand(path, context.sandbox_root)}
  end
end
