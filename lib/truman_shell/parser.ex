defmodule TrumanShell.Parser do
  @moduledoc """
  Parses tokenized shell commands into Command structs.

  Uses Elixir pattern matching to build structured representations
  of shell commands, including pipes, redirects, and chains.

  ## Supported Commands (v0.2)

  Navigation: `cd`, `pwd`
  Read: `ls`, `cat`, `head`, `tail`
  Search: `grep`, `find`, `wc`
  Write: `mkdir`, `touch`, `rm`, `mv`, `cp`, `echo`
  Utility: `date`

  ## Examples

      iex> TrumanShell.Parser.parse("pwd")
      {:ok, %TrumanShell.Command{name: :pwd, args: []}}

      iex> TrumanShell.Parser.parse("ls -la /tmp")
      {:ok, %TrumanShell.Command{name: :ls, args: ["-la", "/tmp"]}}

      iex> TrumanShell.Parser.parse("cat file.txt | grep pattern")
      {:ok, %TrumanShell.Command{
        name: :cat,
        args: ["file.txt"],
        pipes: [%TrumanShell.Command{name: :grep, args: ["pattern"]}]
      }}

  """

  alias TrumanShell.{Command, Tokenizer}

  @doc """
  Parse a shell command string into a Command struct.

  Returns `{:ok, command}` on success or `{:error, reason}` on failure.
  """
  @spec parse(String.t()) :: {:ok, Command.t()} | {:error, String.t()}
  def parse(input) when is_binary(input) do
    with {:ok, tokens} <- Tokenizer.tokenize(input),
         {:ok, command} <- parse_tokens(tokens) do
      {:ok, command}
    end
  end

  @doc """
  Parse tokens into a Command struct.
  """
  @spec parse_tokens([Tokenizer.token()]) :: {:ok, Command.t()} | {:error, String.t()}
  def parse_tokens([]), do: {:error, "Empty command"}

  def parse_tokens(tokens) do
    # First, split by chains (&&, ||, ;) - we'll handle just the first command for now
    # Future versions will return a list of commands or a tree structure
    {command_tokens, _chain_rest} = split_at_chain(tokens)

    # Then split by pipes
    case split_by_pipes(command_tokens) do
      [] ->
        {:error, "Empty command"}

      [single] ->
        parse_single_command(single)

      [first | rest] ->
        with {:ok, base_cmd} <- parse_single_command(first),
             {:ok, piped_cmds} <- parse_piped_commands(rest) do
          {:ok, %{base_cmd | pipes: piped_cmds}}
        end
    end
  end

  # Split tokens at the first chain operator
  defp split_at_chain(tokens) do
    case Enum.split_while(tokens, fn
           {:chain, _} -> false
           _ -> true
         end) do
      {before, [{:chain, _} | after_chain]} -> {before, after_chain}
      {all, []} -> {all, []}
    end
  end

  # Split tokens by pipe operators
  defp split_by_pipes(tokens) do
    tokens
    |> Enum.chunk_by(fn
      {:pipe, _} -> :pipe
      _ -> :token
    end)
    |> Enum.reject(fn
      [{:pipe, _}] -> true
      _ -> false
    end)
  end

  # Parse a single command (no pipes)
  defp parse_single_command([]) do
    {:error, "Empty command segment"}
  end

  defp parse_single_command([{:word, cmd_name} | rest]) do
    name = parse_command_name(cmd_name)
    {args, redirects} = parse_args_and_redirects(rest)
    {:ok, Command.new(name, args, redirects: redirects)}
  end

  defp parse_single_command([{:glob, pattern} | _rest]) do
    # Glob as first token is unusual but could happen (e.g., `*.sh`)
    {:error, "Cannot execute glob pattern: #{pattern}"}
  end

  defp parse_single_command([{type, _} | _]) do
    {:error, "Unexpected token type at start of command: #{type}"}
  end

  # Parse command name to atom
  # Unknown commands are allowed - executor will return "command not found"
  defp parse_command_name(name) do
    String.to_atom(name)
  end

  # Parse arguments and extract redirects
  defp parse_args_and_redirects(tokens) do
    parse_args_and_redirects(tokens, [], [])
  end

  defp parse_args_and_redirects([], args, redirects) do
    {Enum.reverse(args), Enum.reverse(redirects)}
  end

  # Handle redirect followed by target
  defp parse_args_and_redirects([{:redirect, type}, {:word, target} | rest], args, redirects) do
    parse_args_and_redirects(rest, args, [{type, target} | redirects])
  end

  defp parse_args_and_redirects([{:redirect, type}, {:glob, target} | rest], args, redirects) do
    parse_args_and_redirects(rest, args, [{type, target} | redirects])
  end

  # Redirect without target - error in strict mode, but we'll be lenient
  defp parse_args_and_redirects([{:redirect, _type} | rest], args, redirects) do
    # Skip malformed redirect
    parse_args_and_redirects(rest, args, redirects)
  end

  # Regular word argument
  defp parse_args_and_redirects([{:word, word} | rest], args, redirects) do
    parse_args_and_redirects(rest, [word | args], redirects)
  end

  # Glob argument
  defp parse_args_and_redirects([{:glob, pattern} | rest], args, redirects) do
    parse_args_and_redirects(rest, [pattern | args], redirects)
  end

  # Skip other token types (shouldn't happen after split_by_pipes)
  defp parse_args_and_redirects([_ | rest], args, redirects) do
    parse_args_and_redirects(rest, args, redirects)
  end

  # Parse list of piped commands
  defp parse_piped_commands(command_groups) do
    command_groups
    |> Enum.map(&parse_single_command/1)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, cmd}, {:ok, acc} -> {:cont, {:ok, [cmd | acc]}}
      {:error, _} = error, _ -> {:halt, error}
    end)
    |> case do
      {:ok, cmds} -> {:ok, Enum.reverse(cmds)}
      error -> error
    end
  end
end
