defmodule TrumanShell.Stages.Tokenizer do
  @moduledoc """
  Tokenizes shell command strings into a list of tokens.

  Handles:
  - Simple words
  - Quoted strings (single and double quotes)
  - Pipes (`|`)
  - Redirects (`>`, `>>`, `<`, `2>`, `2>>`)
  - Command chains (`&&`, `||`, `;`)
  - Glob patterns (`*`, `?`, `[...]`)
  - Escape sequences (`\\`)

  ## Token Types

  - `{:word, string}` - A simple word or argument
  - `{:pipe, "|"}` - Pipe operator
  - `{:redirect, type}` - Redirect operator (`:stdout`, `:stdout_append`, etc.)
  - `{:chain, type}` - Chain operator (`:and`, `:or`, `:seq`)
  - `{:glob, pattern}` - Glob pattern

  ## Examples

      iex> TrumanShell.Stages.Tokenizer.tokenize("ls -la")
      {:ok, [{:word, "ls"}, {:word, "-la"}]}

      iex> TrumanShell.Stages.Tokenizer.tokenize("cat file.txt | grep pattern")
      {:ok, [{:word, "cat"}, {:word, "file.txt"}, {:pipe, "|"}, {:word, "grep"}, {:word, "pattern"}]}

  """

  @type token ::
          {:word, String.t()}
          | {:pipe, String.t()}
          | {:redirect, atom()}
          | {:chain, atom()}
          | {:glob, String.t()}

  @doc """
  Tokenize a shell command string.

  Returns `{:ok, tokens}` on success or `{:error, reason}` on failure.
  """
  @spec tokenize(String.t()) :: {:ok, [token()]} | {:error, String.t()}
  def tokenize(input) when is_binary(input) do
    input
    |> String.trim()
    |> do_tokenize([])
    |> case do
      {:ok, tokens} -> {:ok, Enum.reverse(tokens)}
      error -> error
    end
  end

  # Empty string - done
  defp do_tokenize("", tokens), do: {:ok, tokens}

  # Skip leading whitespace
  defp do_tokenize(<<c, rest::binary>>, tokens) when c in [?\s, ?\t] do
    do_tokenize(rest, tokens)
  end

  # IMPORTANT: Multi-character operators must come BEFORE single-character ones!
  # Otherwise `||` matches as two `|` pipes, `>>` matches as two `>` redirects, etc.

  # Or chain (||) - MUST come before pipe (|)
  defp do_tokenize(<<"||", rest::binary>>, tokens) do
    do_tokenize(rest, [{:chain, :or} | tokens])
  end

  # Pipe (|)
  defp do_tokenize(<<"|", rest::binary>>, tokens) do
    do_tokenize(rest, [{:pipe, "|"} | tokens])
  end

  # And chain (&&)
  defp do_tokenize(<<"&&", rest::binary>>, tokens) do
    do_tokenize(rest, [{:chain, :and} | tokens])
  end

  # Stderr redirect append (2>>) - MUST come before 2>
  defp do_tokenize(<<"2>>", rest::binary>>, tokens) do
    do_tokenize(rest, [{:redirect, :stderr_append} | tokens])
  end

  # Stderr redirect (2>)
  defp do_tokenize(<<"2>", rest::binary>>, tokens) do
    do_tokenize(rest, [{:redirect, :stderr} | tokens])
  end

  # Stdout redirect append (>>) - MUST come before >
  defp do_tokenize(<<">>", rest::binary>>, tokens) do
    do_tokenize(rest, [{:redirect, :stdout_append} | tokens])
  end

  # Stdout redirect (>)
  defp do_tokenize(<<">", rest::binary>>, tokens) do
    do_tokenize(rest, [{:redirect, :stdout} | tokens])
  end

  # Stdin redirect (<)
  defp do_tokenize(<<"<", rest::binary>>, tokens) do
    do_tokenize(rest, [{:redirect, :stdin} | tokens])
  end

  # Sequence chain (;)
  defp do_tokenize(<<";", rest::binary>>, tokens) do
    do_tokenize(rest, [{:chain, :seq} | tokens])
  end

  # Double-quoted string
  defp do_tokenize(<<"\"", rest::binary>>, tokens) do
    case parse_quoted_string(rest, "", ?") do
      {:ok, string, remaining} ->
        do_tokenize(remaining, [{:word, string} | tokens])

      {:error, _} = error ->
        error
    end
  end

  # Single-quoted string
  defp do_tokenize(<<"'", rest::binary>>, tokens) do
    case parse_quoted_string(rest, "", ?') do
      {:ok, string, remaining} ->
        do_tokenize(remaining, [{:word, string} | tokens])

      {:error, _} = error ->
        error
    end
  end

  # Regular word
  defp do_tokenize(<<c, _::binary>> = input, tokens) when c not in [?\s, ?\t] do
    {word, rest} = parse_word(input, "")

    # Check if it's a glob pattern
    token =
      if String.contains?(word, ["*", "?", "[", "]"]) do
        {:glob, word}
      else
        {:word, word}
      end

    do_tokenize(rest, [token | tokens])
  end

  # Parse a word until we hit whitespace or special characters
  defp parse_word("", acc), do: {acc, ""}

  defp parse_word(<<c, rest::binary>>, acc) when c in [?\s, ?\t, ?|, ?>, ?<, ?;, ?&, ?", ?'] do
    {acc, <<c, rest::binary>>}
  end

  # Handle escape sequences
  defp parse_word(<<"\\", c, rest::binary>>, acc) do
    parse_word(rest, acc <> <<c>>)
  end

  defp parse_word(<<c, rest::binary>>, acc) do
    parse_word(rest, acc <> <<c>>)
  end

  # Parse quoted string, handling escape sequences for double quotes
  defp parse_quoted_string("", _acc, quote_char) do
    {:error, "Unterminated #{<<quote_char>>}-quoted string"}
  end

  defp parse_quoted_string(<<char, rest::binary>>, acc, quote_char) when char == quote_char do
    {:ok, acc, rest}
  end

  # Handle escape sequences in double quotes
  defp parse_quoted_string(<<"\\", c, rest::binary>>, acc, ?" = q) when c in [?", ?\\, ?n, ?t] do
    escaped =
      case c do
        ?" -> "\""
        ?\\ -> "\\"
        ?n -> "\n"
        ?t -> "\t"
      end

    parse_quoted_string(rest, acc <> escaped, q)
  end

  # Single quotes don't interpret escapes (except '')
  defp parse_quoted_string(<<c, rest::binary>>, acc, quote_char) do
    parse_quoted_string(rest, acc <> <<c>>, quote_char)
  end
end
