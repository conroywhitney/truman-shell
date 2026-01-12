defmodule TrumanShell.ExecutorTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Command
  alias TrumanShell.Executor

  describe "run/1" do
    test "executes a valid command and returns {:ok, output}" do
      command = %Command{name: :cmd_ls, args: [], pipes: [], redirects: []}

      result = Executor.run(command)

      assert {:ok, output} = result
      assert is_binary(output)
    end

    test "returns error for unknown command" do
      command = %Command{name: {:unknown, "xyz"}, args: [], pipes: [], redirects: []}

      result = Executor.run(command)

      assert {:error, message} = result
      assert message == "bash: xyz: command not found\n"
    end
  end

  describe "ls handler" do
    test "lists files in current directory" do
      command = %Command{name: :cmd_ls, args: [], pipes: [], redirects: []}

      {:ok, output} = Executor.run(command)

      # Current directory should contain mix.exs (we're in project root)
      assert output =~ "mix.exs"
    end

    test "lists files in specified directory" do
      command = %Command{name: :cmd_ls, args: ["lib"], pipes: [], redirects: []}

      {:ok, output} = Executor.run(command)

      assert output =~ "truman_shell.ex"
    end

    test "returns error for non-existent directory" do
      command = %Command{name: :cmd_ls, args: ["nonexistent_dir"], pipes: [], redirects: []}

      result = Executor.run(command)

      assert {:error, message} = result
      assert message == "ls: nonexistent_dir: No such file or directory\n"
    end
  end

  describe "depth limits" do
    test "accepts command within depth limit" do
      # 3 pipes = depth 4, well under limit of 10
      command = %Command{
        name: :cmd_ls,
        args: [],
        pipes: [
          %Command{name: :cmd_ls, args: [], pipes: [], redirects: []},
          %Command{name: :cmd_ls, args: [], pipes: [], redirects: []},
          %Command{name: :cmd_ls, args: [], pipes: [], redirects: []}
        ],
        redirects: []
      }

      result = Executor.run(command)

      assert {:ok, _output} = result
    end

    test "rejects command exceeding depth limit" do
      # Build a command with 15 pipes (depth 16)
      deep_pipes =
        Enum.map(1..15, fn _ ->
          %Command{name: :cmd_ls, args: [], pipes: [], redirects: []}
        end)

      command = %Command{
        name: :cmd_ls,
        args: [],
        pipes: deep_pipes,
        redirects: []
      }

      result = Executor.run(command)

      assert {:error, message} = result
      assert message =~ "pipe depth exceeded"
    end
  end

  describe "TrumanShell.execute/1 public API" do
    test "parses and executes a command string" do
      result = TrumanShell.execute("ls")

      assert {:ok, output} = result
      assert output =~ "mix.exs"
    end

    test "returns parse error for invalid syntax" do
      # Empty command should fail at parse stage
      result = TrumanShell.execute("")

      assert {:error, _reason} = result
    end

    test "returns execution error for unknown command" do
      result = TrumanShell.execute("unknowncommand")

      assert {:error, message} = result
      assert message =~ "command not found"
    end
  end
end
