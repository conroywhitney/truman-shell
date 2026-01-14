defmodule TrumanShell.TokenizerTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Tokenizer

  describe "tokenize/1 - basic words" do
    test "single word" do
      assert {:ok, [{:word, "ls"}]} = Tokenizer.tokenize("ls")
    end

    test "multiple words" do
      assert {:ok, [{:word, "ls"}, {:word, "-la"}]} = Tokenizer.tokenize("ls -la")
    end

    test "words with paths" do
      assert {:ok, [{:word, "cat"}, {:word, "/etc/hosts"}]} =
               Tokenizer.tokenize("cat /etc/hosts")
    end

    test "handles extra whitespace" do
      assert {:ok, [{:word, "ls"}, {:word, "-la"}]} = Tokenizer.tokenize("  ls   -la  ")
    end
  end

  describe "tokenize/1 - pipes" do
    test "simple pipe" do
      assert {:ok, [{:word, "cat"}, {:word, "file"}, {:pipe, "|"}, {:word, "grep"}, {:word, "x"}]} =
               Tokenizer.tokenize("cat file | grep x")
    end

    test "multiple pipes" do
      {:ok, tokens} = Tokenizer.tokenize("a | b | c")
      assert length(tokens) == 5
      assert Enum.at(tokens, 1) == {:pipe, "|"}
      assert Enum.at(tokens, 3) == {:pipe, "|"}
    end
  end

  describe "tokenize/1 - redirects" do
    test "stdout redirect" do
      assert {:ok, [{:word, "echo"}, {:word, "hi"}, {:redirect, :stdout}, {:word, "out.txt"}]} =
               Tokenizer.tokenize("echo hi > out.txt")
    end

    test "stdout append" do
      assert {:ok,
              [{:word, "echo"}, {:word, "more"}, {:redirect, :stdout_append}, {:word, "out.txt"}]} =
               Tokenizer.tokenize("echo more >> out.txt")
    end

    test "stderr redirect" do
      {:ok, tokens} = Tokenizer.tokenize("cmd 2> error.log")
      assert {:redirect, :stderr} in tokens
    end

    test "stderr append" do
      {:ok, tokens} = Tokenizer.tokenize("cmd 2>> error.log")
      assert {:redirect, :stderr_append} in tokens
    end

    test "stdin redirect" do
      {:ok, tokens} = Tokenizer.tokenize("cmd < input.txt")
      assert {:redirect, :stdin} in tokens
    end
  end

  describe "tokenize/1 - chains" do
    test "and chain" do
      {:ok, tokens} = Tokenizer.tokenize("mkdir dir && cd dir")
      assert {:chain, :and} in tokens
    end

    test "or chain" do
      {:ok, tokens} = Tokenizer.tokenize("false || echo fallback")
      assert {:chain, :or} in tokens
    end

    test "sequence chain" do
      {:ok, tokens} = Tokenizer.tokenize("cd dir ; ls")
      assert {:chain, :seq} in tokens
    end
  end

  describe "tokenize/1 - quoted strings" do
    test "double quotes" do
      assert {:ok, [{:word, "echo"}, {:word, "hello world"}]} =
               Tokenizer.tokenize("echo \"hello world\"")
    end

    test "single quotes" do
      assert {:ok, [{:word, "echo"}, {:word, "hello world"}]} =
               Tokenizer.tokenize("echo 'hello world'")
    end

    test "nested quotes in double quotes" do
      {:ok, tokens} = Tokenizer.tokenize("echo \"it's fine\"")
      assert {:word, "it's fine"} in tokens
    end

    test "escaped quote in double quotes" do
      {:ok, tokens} = Tokenizer.tokenize(~s(echo "say \\"hello\\""))
      assert {:word, ~s(say "hello")} in tokens
    end

    test "unterminated double quote returns error" do
      assert {:error, "Unterminated \"-quoted string"} = Tokenizer.tokenize("echo \"hello")
    end

    test "unterminated single quote returns error" do
      assert {:error, "Unterminated '-quoted string"} = Tokenizer.tokenize("echo 'hello")
    end
  end

  describe "tokenize/1 - globs" do
    test "asterisk glob" do
      assert {:ok, [{:word, "ls"}, {:glob, "*.md"}]} = Tokenizer.tokenize("ls *.md")
    end

    test "question mark glob" do
      assert {:ok, [{:word, "ls"}, {:glob, "file?.txt"}]} = Tokenizer.tokenize("ls file?.txt")
    end

    test "bracket glob" do
      assert {:ok, [{:word, "ls"}, {:glob, "[abc].txt"}]} = Tokenizer.tokenize("ls [abc].txt")
    end

    test "double asterisk glob" do
      assert {:ok, [{:word, "ls"}, {:glob, "**/*.ex"}]} = Tokenizer.tokenize("ls **/*.ex")
    end
  end

  describe "tokenize/1 - escape sequences" do
    test "escaped space in word" do
      assert {:ok, [{:word, "ls"}, {:word, "my file.txt"}]} =
               Tokenizer.tokenize("ls my\\ file.txt")
    end
  end

  describe "tokenize/1 - empty and whitespace" do
    test "empty string" do
      assert {:ok, []} = Tokenizer.tokenize("")
    end

    test "whitespace only" do
      assert {:ok, []} = Tokenizer.tokenize("   ")
    end
  end
end
