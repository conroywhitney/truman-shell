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
  alias TrumanShell.Config.Sandbox, as: SandboxConfig
  alias TrumanShell.Support.Glob
  alias TrumanShell.Support.Tilde

  @doc """
  Expands shell syntax in a Command struct.

  Transforms the command's args and redirect paths, expanding `~` to the sandbox root
  and glob patterns to matching files. Also recursively expands piped commands.

  ## Config

  Accepts a `%Config.Sandbox{}` struct with:
  - `roots` - List of allowed directories (first root used for tilde expansion)
  - `default_cwd` - Working directory for glob expansion

  ## Examples

      iex> alias TrumanShell.Command
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> alias TrumanShell.Stages.Expander
      iex> cmd = %Command{name: "cat", args: ["~/file.txt"], redirects: [], pipes: []}
      iex> config = %SandboxConfig{roots: ["/sandbox"], default_cwd: "/sandbox"}
      iex> Expander.expand(cmd, config)
      %Command{name: "cat", args: ["/sandbox/file.txt"], redirects: [], pipes: []}

      iex> alias TrumanShell.Command
      iex> alias TrumanShell.Config.Sandbox, as: SandboxConfig
      iex> alias TrumanShell.Stages.Expander
      iex> cmd = %Command{name: "echo", args: ["hi"], redirects: [{:stdout, "~/out.txt"}], pipes: []}
      iex> config = %SandboxConfig{roots: ["/sandbox"], default_cwd: "/sandbox"}
      iex> Expander.expand(cmd, config)
      %Command{name: "echo", args: ["hi"], redirects: [{:stdout, "/sandbox/out.txt"}], pipes: []}

  """
  @spec expand(Command.t(), SandboxConfig.t() | map()) :: Command.t()
  def expand(%Command{args: args, redirects: redirects, pipes: pipes} = command, %SandboxConfig{} = config) do
    expanded_args = Enum.flat_map(args, &expand_arg(&1, config))
    expanded_redirects = Enum.map(redirects, &expand_redirect(&1, config))
    expanded_pipes = Enum.map(pipes, &expand(&1, config))

    %{command | args: expanded_args, redirects: expanded_redirects, pipes: expanded_pipes}
  end

  # Backward compatibility: convert legacy context map to Config.Sandbox struct
  def expand(%Command{} = command, %{sandbox_root: sandbox_root} = context) do
    current_dir = Map.get(context, :current_dir, sandbox_root)
    config = %SandboxConfig{roots: [sandbox_root], default_cwd: current_dir}
    expand(command, config)
  end

  # Expand a {:glob, pattern} argument - tilde expansion then glob expansion
  # Glob.expand/2 returns [String.t()] if matches found, or String.t() if no matches
  defp expand_arg({:glob, pattern}, %SandboxConfig{roots: [root | _]} = config) do
    expanded = Tilde.expand(pattern, root)

    case Glob.expand(expanded, config) do
      files when is_list(files) -> files
      pattern when is_binary(pattern) -> [pattern]
    end
  end

  # Expand a literal string argument - tilde expansion only, NO glob expansion
  # This handles quoted args like "*.txt" which should remain literal
  defp expand_arg(arg, %SandboxConfig{roots: [root | _]}) when is_binary(arg) do
    [Tilde.expand(arg, root)]
  end

  # Expand tilde in redirect path
  defp expand_redirect({type, path}, %SandboxConfig{roots: [root | _]}) when is_binary(path) do
    {type, Tilde.expand(path, root)}
  end
end
