defmodule TrumanShell.Command do
  @moduledoc """
  Represents a parsed shell command.

  ## Fields

  - `name` - The command name as an atom (`:ls`, `:cat`, `:grep`, etc.)
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
      %Command{name: :ls, args: ["-la"], pipes: [], redirects: []}

      # Command with pipe
      %Command{
        name: :cat,
        args: ["file.txt"],
        pipes: [%Command{name: :grep, args: ["pattern"]}],
        redirects: []
      }

      # Command with redirect
      %Command{
        name: :echo,
        args: ["hello"],
        pipes: [],
        redirects: [{:stdout, "output.txt"}]
      }

  """

  @type redirect_type :: :stdout | :stdout_append | :stderr | :stderr_append | :stdin

  # Command name is either a known atom or {:unknown, "string"} for unrecognized commands
  @type command_name :: atom() | {:unknown, String.t()}

  # Authoritative allowlist of known commands (prevents atom DoS)
  # See: https://erlang.org/doc/efficiency_guide/commoncaveats.html#atoms
  @known_commands %{
    # Navigation
    "cd" => :cd,
    "pwd" => :pwd,
    # Read operations
    "ls" => :ls,
    "cat" => :cat,
    "head" => :head,
    "tail" => :tail,
    # Search operations
    "grep" => :grep,
    "find" => :find,
    "wc" => :wc,
    # Write operations
    "mkdir" => :mkdir,
    "touch" => :touch,
    "rm" => :rm,
    "mv" => :mv,
    "cp" => :cp,
    "echo" => :echo,
    "date" => :date,
    # Utility
    "which" => :which,
    "type" => :type,
    "true" => :true,
    "false" => :false
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

      iex> TrumanShell.Command.new(:ls)
      %TrumanShell.Command{name: :ls, args: [], pipes: [], redirects: []}

      iex> TrumanShell.Command.new(:ls, ["-la"])
      %TrumanShell.Command{name: :ls, args: ["-la"], pipes: [], redirects: []}

      iex> TrumanShell.Command.new(:grep, ["-r", "TODO", "."])
      %TrumanShell.Command{name: :grep, args: ["-r", "TODO", "."], pipes: [], redirects: []}

  ## With Pipes

      iex> grep_cmd = TrumanShell.Command.new(:grep, ["pattern"])
      iex> TrumanShell.Command.new(:cat, ["file.txt"], pipes: [grep_cmd])
      %TrumanShell.Command{
        name: :cat,
        args: ["file.txt"],
        pipes: [%TrumanShell.Command{name: :grep, args: ["pattern"], pipes: [], redirects: []}],
        redirects: []
      }

  ## With Redirects

      iex> TrumanShell.Command.new(:echo, ["hello"], redirects: [{:stdout, "out.txt"}])
      %TrumanShell.Command{
        name: :echo,
        args: ["hello"],
        pipes: [],
        redirects: [{:stdout, "out.txt"}]
      }

  ## Pattern Matching

  Commands are plain structs, so you can pattern match on them:

      iex> cmd = TrumanShell.Command.new(:ls, ["-la", "/tmp"])
      iex> %TrumanShell.Command{name: name, args: [flag | paths]} = cmd
      iex> name
      :ls
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
      :ls

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

      iex> TrumanShell.Command.known?(%TrumanShell.Command{name: :ls})
      true

      iex> TrumanShell.Command.known?(%TrumanShell.Command{name: {:unknown, "kubectl"}})
      false

  """
  def known?(%__MODULE__{name: {:unknown, _}}), do: false
  def known?(%__MODULE__{name: name}) when is_atom(name), do: true
end
