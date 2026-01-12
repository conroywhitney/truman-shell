defmodule TrumanShell.Command do
  @moduledoc """
  Represents a parsed shell command.

  ## Fields

  - `name` - The command name as an atom (`:cmd_ls`, `:cmd_cat`, `:cmd_grep`, etc.)
  - `args` - List of arguments as strings
  - `pipes` - List of piped commands (each is another Command struct)
  - `redirects` - List of redirections as `{type, target}` tuples

  ## Redirect Types

  - `:stdout` - Standard output (`>`)
  - `:stdout_append` - Append stdout (`>>`)
  - `:stderr` - Standard error (`2>`)
  - `:stderr_append` - Append stderr (`2>>`)
  - `:stdin` - Standard input (`<`)

  ## Examples

      # Simple command
      %Command{name: :cmd_ls, args: ["-la"], pipes: [], redirects: []}

      # Command with pipe
      %Command{
        name: :cmd_cat,
        args: ["file.txt"],
        pipes: [%Command{name: :cmd_grep, args: ["pattern"]}],
        redirects: []
      }

      # Command with redirect
      %Command{
        name: :cmd_echo,
        args: ["hello"],
        pipes: [],
        redirects: [{:stdout, "output.txt"}]
      }

  """

  @type redirect_type :: :stdout | :stdout_append | :stderr | :stderr_append | :stdin

  # Command name is either a known atom or {:unknown, "string"} for unrecognized commands
  @type command_name :: atom() | {:unknown, String.t()}

  # Authoritative allowlist using cmd_ prefix for namespace clarity.
  # See: https://erlang.org/doc/efficiency_guide/commoncaveats.html#atoms
  # This prevents:
  # 1. Atom DoS attacks (no String.to_atom on untrusted input)
  # 2. The true/false falsy footgun (cmd_true/cmd_false aren't falsy)
  # 3. Namespace collisions (:type is common; :cmd_type is unambiguous)
  @known_commands %{
    # Navigation
    "cd" => :cmd_cd,
    "pwd" => :cmd_pwd,
    # Read operations
    "ls" => :cmd_ls,
    "cat" => :cmd_cat,
    "head" => :cmd_head,
    "tail" => :cmd_tail,
    # Search operations
    "grep" => :cmd_grep,
    "find" => :cmd_find,
    "wc" => :cmd_wc,
    # Write operations
    "mkdir" => :cmd_mkdir,
    "touch" => :cmd_touch,
    "rm" => :cmd_rm,
    "mv" => :cmd_mv,
    "cp" => :cmd_cp,
    "echo" => :cmd_echo,
    "date" => :cmd_date,
    # Utility
    "which" => :cmd_which,
    "type" => :cmd_type,
    "true" => :cmd_true,
    "false" => :cmd_false
  }

  @type t :: %__MODULE__{
          name: command_name(),
          args: [String.t()],
          pipes: [t()],
          redirects: [{redirect_type(), String.t()}]
        }

  defstruct name: nil,
            args: [],
            pipes: [],
            redirects: []

  @doc """
  Create a new Command struct.

  ## Basic Usage

      iex> TrumanShell.Command.new(:cmd_ls)
      %TrumanShell.Command{name: :cmd_ls, args: [], pipes: [], redirects: []}

      iex> TrumanShell.Command.new(:cmd_ls, ["-la"])
      %TrumanShell.Command{name: :cmd_ls, args: ["-la"], pipes: [], redirects: []}

      iex> TrumanShell.Command.new(:cmd_grep, ["-r", "TODO", "."])
      %TrumanShell.Command{name: :cmd_grep, args: ["-r", "TODO", "."], pipes: [], redirects: []}

  ## With Pipes

      iex> grep_cmd = TrumanShell.Command.new(:cmd_grep, ["pattern"])
      iex> TrumanShell.Command.new(:cmd_cat, ["file.txt"], pipes: [grep_cmd])
      %TrumanShell.Command{
        name: :cmd_cat,
        args: ["file.txt"],
        pipes: [%TrumanShell.Command{name: :cmd_grep, args: ["pattern"], pipes: [], redirects: []}],
        redirects: []
      }

  ## With Redirects

      iex> TrumanShell.Command.new(:cmd_echo, ["hello"], redirects: [{:stdout, "out.txt"}])
      %TrumanShell.Command{
        name: :cmd_echo,
        args: ["hello"],
        pipes: [],
        redirects: [{:stdout, "out.txt"}]
      }

  ## Pattern Matching

  Commands are plain structs, so you can pattern match on them:

      iex> cmd = TrumanShell.Command.new(:cmd_ls, ["-la", "/tmp"])
      iex> %TrumanShell.Command{name: name, args: [flag | paths]} = cmd
      iex> name
      :cmd_ls
      iex> flag
      "-la"
      iex> paths
      ["/tmp"]

  ## Unknown Commands

      iex> TrumanShell.Command.new({:unknown, "kubectl"}, ["get", "pods"])
      %TrumanShell.Command{
        name: {:unknown, "kubectl"},
        args: ["get", "pods"],
        pipes: [],
        redirects: []
      }

  """
  def new(name, args \\ [], opts \\ []) when is_list(args) do
    %__MODULE__{
      name: name,
      args: args,
      pipes: Keyword.get(opts, :pipes, []),
      redirects: Keyword.get(opts, :redirects, [])
    }
  end

  @doc """
  Parse a command name string into a safe command_name type.

  Known commands return atoms, unknown return `{:unknown, name}` tuples.
  This prevents atom table exhaustion from untrusted input.

  ## Examples

      iex> TrumanShell.Command.parse_name("ls")
      :cmd_ls

      iex> TrumanShell.Command.parse_name("kubectl")
      {:unknown, "kubectl"}

  """
  @spec parse_name(String.t()) :: command_name()
  def parse_name(name) when is_binary(name) do
    Map.get(@known_commands, name, {:unknown, name})
  end

  @doc """
  Check if a command is a known (allowlisted) command.

  ## Examples

      iex> TrumanShell.Command.known?(%TrumanShell.Command{name: :cmd_ls})
      true

      iex> TrumanShell.Command.known?(%TrumanShell.Command{name: {:unknown, "kubectl"}})
      false

  """
  def known?(%__MODULE__{name: {:unknown, _}}), do: false
  def known?(%__MODULE__{name: name}) when is_atom(name), do: true
end
