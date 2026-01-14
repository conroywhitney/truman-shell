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

    test "rejects unsupported flags" do
      command = %Command{name: :cmd_ls, args: ["-la"], pipes: [], redirects: []}

      result = Executor.run(command)

      assert {:error, message} = result
      assert message =~ "invalid option"
    end

    test "rejects multiple path arguments" do
      command = %Command{name: :cmd_ls, args: ["lib", "test"], pipes: [], redirects: []}

      result = Executor.run(command)

      assert {:error, message} = result
      assert message =~ "too many arguments"
    end

    test "rejects access to system directories (404 principle)" do
      # Trying to access /etc should appear as "not found"
      # not "permission denied" - no information leakage
      # SECURITY: This test MUST fail if /etc is accessible
      command = %Command{name: :cmd_ls, args: ["/etc"], pipes: [], redirects: []}

      result = Executor.run(command)

      # Should NOT see real system files like passwd, hosts, etc
      assert {:error, message} = result
      assert message =~ "No such file or directory"
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

  describe "output truncation" do
    test "exposes max_output_lines configuration" do
      # Default max is 200 lines to prevent DoS
      assert TrumanShell.Executor.max_output_lines() == 200
    end

    test "truncates output and shows count for large directories" do
      # Create a temp directory with many files to test truncation
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-truncation-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      # Create 250 files (exceeds 200 line limit)
      for i <- 1..250 do
        File.write!(Path.join(tmp_dir, "file_#{String.pad_leading("#{i}", 3, "0")}.txt"), "")
      end

      try do
        # Change to tmp_dir so sandbox allows access
        original_cwd = File.cwd!()
        File.cd!(tmp_dir)

        command = %Command{name: :cmd_ls, args: ["."], pipes: [], redirects: []}
        {:ok, output} = Executor.run(command)

        # Should show truncation message
        assert output =~ "... (50 more entries, 250 total)"

        # Should only have 200 file entries (plus truncation line)
        lines = String.split(output, "\n", trim: true)
        # 200 files + 1 truncation message
        assert length(lines) == 201

        File.cd!(original_cwd)
      after
        # Cleanup
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "pwd handler" do
    test "returns current working directory" do
      command = %Command{name: :cmd_pwd, args: [], pipes: [], redirects: []}

      {:ok, output} = Executor.run(command)

      # pwd should return the current directory with a trailing newline
      expected = File.cwd!() <> "\n"
      assert output == expected
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
