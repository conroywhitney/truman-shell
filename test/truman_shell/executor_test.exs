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
    test "truncates output and shows count for large directories" do
      # Create a temp directory with many files to test truncation
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-truncation-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      # Create 250 files (exceeds 200 line limit)
      for i <- 1..250 do
        File.write!(Path.join(tmp_dir, "file_#{String.pad_leading("#{i}", 3, "0")}.txt"), "")
      end

      try do
        # Use explicit sandbox_root instead of File.cd! (async-safe)
        command = %Command{name: :cmd_ls, args: ["."], pipes: [], redirects: []}
        {:ok, output} = Executor.run(command, sandbox_root: tmp_dir)

        # Should show truncation message
        assert output =~ "... (50 more entries, 250 total)"

        # Should only have 200 file entries (plus truncation line)
        lines = String.split(output, "\n", trim: true)
        # 200 files + 1 truncation message
        assert length(lines) == 201
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

  describe "cd handler" do
    setup do
      # Reset current directory state before each test
      Process.delete(:truman_cwd)
      :ok
    end

    test "changes working directory to subdirectory" do
      cd_cmd = %Command{name: :cmd_cd, args: ["lib"], pipes: [], redirects: []}
      pwd_cmd = %Command{name: :cmd_pwd, args: [], pipes: [], redirects: []}

      # cd should succeed silently (empty output like real bash)
      assert {:ok, ""} = Executor.run(cd_cmd)

      # pwd should now return the new directory
      {:ok, output} = Executor.run(pwd_cmd)
      expected = Path.join(File.cwd!(), "lib") <> "\n"
      assert output == expected
    end

    test "cd .. navigates up within sandbox" do
      sandbox_root = File.cwd!()

      # First cd into lib/truman_shell
      cd_deep = %Command{name: :cmd_cd, args: ["lib/truman_shell"], pipes: [], redirects: []}
      assert {:ok, ""} = Executor.run(cd_deep)

      # cd .. should go back to lib
      cd_up = %Command{name: :cmd_cd, args: [".."], pipes: [], redirects: []}
      assert {:ok, ""} = Executor.run(cd_up)

      pwd_cmd = %Command{name: :cmd_pwd, args: [], pipes: [], redirects: []}
      {:ok, output} = Executor.run(pwd_cmd)
      assert output == Path.join(sandbox_root, "lib") <> "\n"
    end

    test "cd .. at sandbox root stays at root" do
      # Try to cd .. from root - should fail, not escape
      cd_up = %Command{name: :cmd_cd, args: [".."], pipes: [], redirects: []}

      # This should fail - can't go above sandbox (404 principle)
      assert {:error, msg} = Executor.run(cd_up)
      assert msg =~ "No such file or directory"
    end

    test "cd /etc blocked with 404 principle" do
      # SECURITY: Absolute paths outside sandbox should appear as "not found"
      # NOT "permission denied" - no information leakage
      cd_etc = %Command{name: :cmd_cd, args: ["/etc"], pipes: [], redirects: []}

      result = Executor.run(cd_etc)

      # Must fail with "No such file or directory", not "permission denied"
      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
      refute msg =~ "permission"
      refute msg =~ "Permission"
    end
  end

  describe "cat handler" do
    test "returns file contents" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-cat-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create a test file
        test_file = Path.join(tmp_dir, "hello.txt")
        File.write!(test_file, "Hello, World!\n")

        command = %Command{name: :cmd_cat, args: ["hello.txt"], pipes: [], redirects: []}
        {:ok, output} = Executor.run(command, sandbox_root: tmp_dir)

        assert output == "Hello, World!\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "concatenates multiple files" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-cat-multi-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create two test files
        File.write!(Path.join(tmp_dir, "a.txt"), "AAA\n")
        File.write!(Path.join(tmp_dir, "b.txt"), "BBB\n")

        command = %Command{name: :cmd_cat, args: ["a.txt", "b.txt"], pipes: [], redirects: []}
        {:ok, output} = Executor.run(command, sandbox_root: tmp_dir)

        # cat concatenates files in order
        assert output == "AAA\nBBB\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "returns error for missing file" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-cat-missing-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        command = %Command{name: :cmd_cat, args: ["missing.txt"], pipes: [], redirects: []}
        result = Executor.run(command, sandbox_root: tmp_dir)

        assert {:error, msg} = result
        assert msg == "cat: missing.txt: No such file or directory\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "head handler" do
    test "returns first n lines with -n flag" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-head-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create a file with 10 lines
        content = Enum.map(1..10, &"Line #{&1}") |> Enum.join("\n")
        File.write!(Path.join(tmp_dir, "lines.txt"), content <> "\n")

        command = %Command{name: :cmd_head, args: ["-n", "3", "lines.txt"], pipes: [], redirects: []}
        {:ok, output} = Executor.run(command, sandbox_root: tmp_dir)

        assert output == "Line 1\nLine 2\nLine 3\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "tail handler" do
    test "returns last n lines with -n flag" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-tail-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create a file with 10 lines
        content = Enum.map(1..10, &"Line #{&1}") |> Enum.join("\n")
        File.write!(Path.join(tmp_dir, "lines.txt"), content <> "\n")

        command = %Command{name: :cmd_tail, args: ["-n", "3", "lines.txt"], pipes: [], redirects: []}
        {:ok, output} = Executor.run(command, sandbox_root: tmp_dir)

        assert output == "Line 8\nLine 9\nLine 10\n"
      after
        File.rm_rf!(tmp_dir)
      end
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
