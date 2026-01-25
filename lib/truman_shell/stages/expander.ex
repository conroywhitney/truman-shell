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
  alias TrumanShell.Commands.Context
  alias TrumanShell.Support.Glob
  alias TrumanShell.Support.Tilde

  @doc """
  Expands shell syntax in a Command struct.

  Transforms the command's args and redirect paths, expanding `~` to home_path
  and glob patterns to matching files relative to current_path.

  ## Context

  Requires a `%Commands.Context{}` with:
  - `current_path` - Working directory for glob expansion
  - `sandbox_config.home_path` - Used for tilde expansion (`~` → `home_path`)
  - `sandbox_config.allowed_paths` - Boundaries for glob filtering

  ## Examples

      iex> alias TrumanShell.Command
      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> alias TrumanShell.Stages.Expander
      iex> cmd = %Command{name: "cat", args: ["~/file.txt"], redirects: [], pipes: []}
      iex> ctx = %Context{current_path: "/sandbox", sandbox_config: %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}}
      iex> Expander.expand(cmd, ctx)
      %Command{name: "cat", args: ["/sandbox/file.txt"], redirects: [], pipes: []}

      iex> alias TrumanShell.Command
      iex> alias TrumanShell.Commands.Context
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> alias TrumanShell.Stages.Expander
      iex> cmd = %Command{name: "echo", args: ["hi"], redirects: [{:stdout, "~/out.txt"}], pipes: []}
      iex> ctx = %Context{current_path: "/sandbox", sandbox_config: %SandboxConfig{allowed_paths: ["/sandbox"], home_path: "/sandbox"}}
      iex> Expander.expand(cmd, ctx)
      %Command{name: "echo", args: ["hi"], redirects: [{:stdout, "/sandbox/out.txt"}], pipes: []}

  """
  @spec expand(Command.t(), Context.t()) :: Command.t()
  def expand(%Command{args: args, redirects: redirects, pipes: pipes} = command, %Context{} = ctx) do
    # Tilde expands to home_path, globs expand relative to current_path
    home = ctx.sandbox_config.home_path

    expanded_args = Enum.flat_map(args, &expand_arg(&1, home, ctx))
    expanded_redirects = Enum.map(redirects, &expand_redirect(&1, home))
    expanded_pipes = Enum.map(pipes, &expand(&1, ctx))

    %{command | args: expanded_args, redirects: expanded_redirects, pipes: expanded_pipes}
  end

  # Expand a {:glob, pattern} argument - tilde expansion then glob expansion
  defp expand_arg({:glob, pattern}, home, ctx) do
    expanded = Tilde.expand(pattern, home)

    case Glob.expand(expanded, ctx) do
      files when is_list(files) -> files
      pattern when is_binary(pattern) -> [pattern]
    end
  end

  # Expand a literal string argument - tilde expansion only, NO glob expansion
  # This handles quoted args like "*.txt" which should remain literal
  defp expand_arg(arg, home, _ctx) when is_binary(arg) do
    [Tilde.expand(arg, home)]
  end

  # Expand tilde in redirect path
  defp expand_redirect({type, path}, home) when is_binary(path) do
    {type, Tilde.expand(path, home)}
  end
end
