defmodule TrumanShell.Stages.Expander do
  @moduledoc """
  Expands shell syntax in command arguments before execution.

  Handles (in order):
  1. Tilde expansion: `~` → sandbox_root, `~/path` → sandbox_root/path
  2. Glob expansion: `*.ex` → list of matching files

  Runs after Parser, before Executor in the pipeline.
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
  """
  @spec expand(Command.t(), map()) :: Command.t()
  def expand(%Command{args: args, redirects: redirects, pipes: pipes} = command, context) do
    expanded_args = Enum.flat_map(args, &expand_arg(&1, context))
    expanded_redirects = Enum.map(redirects, &expand_redirect(&1, context))
    expanded_pipes = Enum.map(pipes, &expand(&1, context))

    %{command | args: expanded_args, redirects: expanded_redirects, pipes: expanded_pipes}
  end

  # Expand a single argument - returns a list (glob can expand to multiple files)
  defp expand_arg(arg, context) when is_binary(arg) do
    arg
    |> Tilde.expand(context.sandbox_root)
    |> maybe_expand_glob(context)
  end

  # If arg contains *, expand as glob pattern
  defp maybe_expand_glob(arg, context) do
    if String.contains?(arg, "*") do
      case Glob.expand(arg, context) do
        files when is_list(files) -> files
        pattern when is_binary(pattern) -> [pattern]
      end
    else
      [arg]
    end
  end

  # Expand tilde in redirect path
  defp expand_redirect({type, path}, context) when is_binary(path) do
    {type, Tilde.expand(path, context.sandbox_root)}
  end
end
