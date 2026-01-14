defmodule TrumanShell.ExecutorTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Command
  alias TrumanShell.Executor

  describe "run/2" do
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

    test "passes sandbox_root option to commands" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-test-sandbox-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "test.txt"), "content")

      try do
        command = %Command{name: :cmd_ls, args: [], pipes: [], redirects: []}
        {:ok, output} = Executor.run(command, sandbox_root: tmp_dir)

        assert output =~ "test.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "resets cwd when sandbox_root changes" do
      # Create two sandboxes
      sandbox1 = Path.join(System.tmp_dir!(), "truman-sandbox1-#{:rand.uniform(100_000)}")
      sandbox2 = Path.join(System.tmp_dir!(), "truman-sandbox2-#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox1)
      File.mkdir_p!(sandbox2)
      subdir1 = Path.join(sandbox1, "subdir")
      File.mkdir_p!(subdir1)

      try do
        # cd into a subdirectory of sandbox1
        cd_cmd = %Command{name: :cmd_cd, args: ["subdir"], pipes: [], redirects: []}
        {:ok, ""} = Executor.run(cd_cmd, sandbox_root: sandbox1)

        # Now switch to sandbox2 - CWD should reset to sandbox2 root, not keep old path
        pwd_cmd = %Command{name: :cmd_pwd, args: [], pipes: [], redirects: []}
        {:ok, output} = Executor.run(pwd_cmd, sandbox_root: sandbox2)

        # CWD should be sandbox2, not sandbox1/subdir
        assert String.trim(output) == sandbox2
      after
        File.rm_rf!(sandbox1)
        File.rm_rf!(sandbox2)
      end
    end
  end

  describe "command dispatch" do
    # Smoke tests verifying each command is wired up correctly
    # Detailed behavior tests are in test/truman_shell/commands/*_test.exs

    test "dispatches :cmd_ls to Commands.Ls" do
      command = %Command{name: :cmd_ls, args: ["lib"], pipes: [], redirects: []}

      {:ok, output} = Executor.run(command)

      assert output =~ "truman_shell"
    end

    test "dispatches :cmd_pwd to Commands.Pwd" do
      command = %Command{name: :cmd_pwd, args: [], pipes: [], redirects: []}

      {:ok, output} = Executor.run(command)

      assert output == File.cwd!() <> "\n"
    end

    test "dispatches :cmd_cd to Commands.Cd and applies set_cwd" do
      # Reset state
      Process.delete(:truman_cwd)

      cd_cmd = %Command{name: :cmd_cd, args: ["lib"], pipes: [], redirects: []}
      pwd_cmd = %Command{name: :cmd_pwd, args: [], pipes: [], redirects: []}

      assert {:ok, ""} = Executor.run(cd_cmd)

      # Verify state was updated
      {:ok, output} = Executor.run(pwd_cmd)
      assert output == Path.join(File.cwd!(), "lib") <> "\n"
    end

    test "dispatches :cmd_cat to Commands.Cat" do
      context_dir = File.cwd!()
      command = %Command{name: :cmd_cat, args: ["mix.exs"], pipes: [], redirects: []}

      {:ok, output} = Executor.run(command, sandbox_root: context_dir)

      assert output =~ "defmodule TrumanShell.MixProject"
    end

    test "dispatches :cmd_head to Commands.Head" do
      command = %Command{name: :cmd_head, args: ["-n", "1", "mix.exs"], pipes: [], redirects: []}

      {:ok, output} = Executor.run(command)

      assert output == "defmodule TrumanShell.MixProject do\n"
    end

    test "dispatches :cmd_tail to Commands.Tail" do
      command = %Command{name: :cmd_tail, args: ["-n", "1", "mix.exs"], pipes: [], redirects: []}

      {:ok, output} = Executor.run(command)

      assert output == "end\n"
    end

    test "dispatches :cmd_echo to Commands.Echo" do
      command = %Command{name: :cmd_echo, args: ["hello", "world"], pipes: [], redirects: []}

      {:ok, output} = Executor.run(command)

      assert output == "hello world\n"
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

  describe "redirects" do
    test "stdout redirect (>) writes output to file" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-redirect-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        command = %Command{
          name: :cmd_echo,
          args: ["hello"],
          pipes: [],
          redirects: [stdout: "output.txt"]
        }

        {:ok, output} = Executor.run(command, sandbox_root: tmp_dir)

        # Output should be empty (went to file)
        assert output == ""

        # File should contain the command output
        file_path = Path.join(tmp_dir, "output.txt")
        assert File.exists?(file_path)
        assert File.read!(file_path) == "hello\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "stdout append redirect (>>) appends to file" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-append-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        file_path = Path.join(tmp_dir, "output.txt")
        File.write!(file_path, "first\n")

        command = %Command{
          name: :cmd_echo,
          args: ["second"],
          pipes: [],
          redirects: [stdout_append: "output.txt"]
        }

        {:ok, output} = Executor.run(command, sandbox_root: tmp_dir)

        assert output == ""
        assert File.read!(file_path) == "first\nsecond\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "redirect to path outside sandbox returns error (404 principle)" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-sandbox-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        command = %Command{
          name: :cmd_echo,
          args: ["sneaky"],
          pipes: [],
          redirects: [stdout: "/etc/passwd"]
        }

        result = Executor.run(command, sandbox_root: tmp_dir)

        # 404 principle: return "not found", don't reveal path exists
        assert {:error, message} = result
        assert message =~ "No such file or directory"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "redirect to directory returns error (not crash)" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-eisdir-#{:rand.uniform(100_000)}")
      subdir = Path.join(tmp_dir, "subdir")
      File.mkdir_p!(subdir)

      try do
        command = %Command{
          name: :cmd_echo,
          args: ["test"],
          pipes: [],
          redirects: [stdout: "subdir"]
        }

        # Should return error, not crash
        result = Executor.run(command, sandbox_root: tmp_dir)

        assert {:error, message} = result
        assert message =~ "Is a directory"
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
