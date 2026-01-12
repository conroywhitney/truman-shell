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

  @type t :: %__MODULE__{
          name: atom(),
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

  ## Examples

      iex> TrumanShell.Command.new(:ls, ["-la"])
      %TrumanShell.Command{name: :ls, args: ["-la"], pipes: [], redirects: []}

  """
  def new(name, args \\ [], opts \\ []) when is_atom(name) and is_list(args) do
    %__MODULE__{
      name: name,
      args: args,
      pipes: Keyword.get(opts, :pipes, []),
      redirects: Keyword.get(opts, :redirects, [])
    }
  end
end
