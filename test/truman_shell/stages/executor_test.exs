defmodule TrumanShell.Stages.ExecutorTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Command
  alias TrumanShell.Stages.Executor

  describe "run/2" do
    test "passes stdin option to first command" do
      # Bug: run/2 was calling execute(command) without opts,
      # so stdin passed to run() was ignored for the first command
      command = %Command{name: :cmd_head, args: ["-n", "2"], pipes: [], redirects: []}

      result = Executor.run(command, stdin: "line 1\nline 2\nline 3\n")

      assert {:ok, output} = result
      assert output == "line 1\nline 2\n"
    end

    test "passes stdin option to first command even with pipes" do
      # Verify stdin flows to first command when pipeline exists
      # head -n 2 | wc -l with stdin should work
      command = %Command{
        name: :cmd_head,
        args: ["-n", "2"],
        pipes: [
          %Command{name: :cmd_wc, args: ["-l"], pipes: [], redirects: []}
        ],
        redirects: []
      }

      result = Executor.run(command, stdin: "line 1\nline 2\nline 3\nline 4\n")

      assert {:ok, output} = result
      # head -n 2 gives 2 lines, wc -l counts them
      assert output =~ "2"
    end

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

    test "accepts exactly 10 stages (boundary)" do
      # 9 pipes = depth 10, exactly at limit
      pipes_9 =
        Enum.map(1..9, fn _ ->
          %Command{name: :cmd_head, args: ["-n", "100"], pipes: [], redirects: []}
        end)

      command = %Command{
        name: :cmd_echo,
        args: ["test"],
        pipes: pipes_9,
        redirects: []
      }

      result = Executor.run(command)

      # Should succeed - exactly at limit
      assert {:ok, _output} = result
    end

    test "rejects 11 stages (exceeds limit)" do
      # 10 pipes = depth 11, just over limit
      pipes_10 =
        Enum.map(1..10, fn _ ->
          %Command{name: :cmd_head, args: ["-n", "100"], pipes: [], redirects: []}
        end)

      command = %Command{
        name: :cmd_echo,
        args: ["test"],
        pipes: pipes_10,
        redirects: []
      }

      result = Executor.run(command)

      assert {:error, message} = result
      assert message =~ "pipeline too deep"
      assert message =~ "11 commands"
    end

    test "rejects command exceeding depth limit" do
      # Build a command with 15 pipes (16 commands total)
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
      assert message =~ "pipeline too deep"
      assert message =~ "16 commands"
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

    test "redirect to nonexistent parent directory returns error (ENOENT)" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-enoent-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        command = %Command{
          name: :cmd_echo,
          args: ["test"],
          pipes: [],
          # Parent directory "nonexistent" doesn't exist
          redirects: [stdout: "nonexistent/output.txt"]
        }

        result = Executor.run(command, sandbox_root: tmp_dir)

        assert {:error, message} = result
        assert message =~ "No such file or directory"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "multiple redirects: last file gets output, earlier files truncated (bash behavior)" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-multi-redir-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # echo hi > a.txt > b.txt
        # Bash behavior: both files created, only LAST gets output
        command = %Command{
          name: :cmd_echo,
          args: ["hello"],
          pipes: [],
          redirects: [stdout: "a.txt", stdout: "b.txt"]
        }

        result = Executor.run(command, sandbox_root: tmp_dir)

        assert {:ok, ""} = result

        # Both files should exist
        assert File.exists?(Path.join(tmp_dir, "a.txt"))
        assert File.exists?(Path.join(tmp_dir, "b.txt"))

        # First file should be empty (truncated by bash semantics)
        assert File.read!(Path.join(tmp_dir, "a.txt")) == ""

        # Last file should have the output
        assert File.read!(Path.join(tmp_dir, "b.txt")) == "hello\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "piping" do
    test "ls | grep pattern filters directory output" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-pipe-ls-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create files with different names
        File.write!(Path.join(tmp_dir, "test_file.txt"), "")
        File.write!(Path.join(tmp_dir, "other_file.txt"), "")
        File.write!(Path.join(tmp_dir, "readme.md"), "")

        # ls | grep test
        command = %Command{
          name: :cmd_ls,
          args: [],
          pipes: [
            %Command{name: :cmd_grep, args: ["test"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        result = Executor.run(command, sandbox_root: tmp_dir)

        assert {:ok, output} = result
        assert output =~ "test_file.txt"
        refute output =~ "other_file.txt"
        refute output =~ "readme.md"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "cat file.txt | head -5 returns first 5 lines" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-pipe-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create a file with 10 lines
        content = Enum.map_join(1..10, "\n", &"line #{&1}")
        File.write!(Path.join(tmp_dir, "data.txt"), content <> "\n")

        # cat data.txt | head -5
        command = %Command{
          name: :cmd_cat,
          args: ["data.txt"],
          pipes: [
            %Command{name: :cmd_head, args: ["-n", "5"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        result = Executor.run(command, sandbox_root: tmp_dir)

        assert {:ok, output} = result
        lines = String.split(output, "\n", trim: true)
        assert length(lines) == 5
        assert hd(lines) == "line 1"
        assert List.last(lines) == "line 5"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "3-stage pipe: cat | grep | head chains correctly" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-pipe-3-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create a file with numbered lines, some matching a pattern
        content = """
        apple 1
        banana 2
        apple 3
        cherry 4
        apple 5
        apple 6
        banana 7
        apple 8
        """

        File.write!(Path.join(tmp_dir, "fruits.txt"), content)

        # cat fruits.txt | grep apple | head -3
        command = %Command{
          name: :cmd_cat,
          args: ["fruits.txt"],
          pipes: [
            %Command{name: :cmd_grep, args: ["apple"], pipes: [], redirects: []},
            %Command{name: :cmd_head, args: ["-n", "3"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        result = Executor.run(command, sandbox_root: tmp_dir)

        assert {:ok, output} = result
        lines = String.split(output, "\n", trim: true)
        assert length(lines) == 3
        assert Enum.all?(lines, &String.contains?(&1, "apple"))
        assert hd(lines) == "apple 1"
        assert List.last(lines) == "apple 5"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "pipe with tail: cat | tail -3 returns last 3 lines" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-pipe-tail-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        content = Enum.map_join(1..10, "\n", &"line #{&1}")
        File.write!(Path.join(tmp_dir, "data.txt"), content <> "\n")

        # cat data.txt | tail -3
        command = %Command{
          name: :cmd_cat,
          args: ["data.txt"],
          pipes: [
            %Command{name: :cmd_tail, args: ["-n", "3"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        result = Executor.run(command, sandbox_root: tmp_dir)

        assert {:ok, output} = result
        lines = String.split(output, "\n", trim: true)
        assert length(lines) == 3
        assert hd(lines) == "line 8"
        assert List.last(lines) == "line 10"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "pipe with wc: cat | wc -l counts lines" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-pipe-wc-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        content = Enum.map_join(1..5, "\n", &"line #{&1}")
        File.write!(Path.join(tmp_dir, "data.txt"), content <> "\n")

        # cat data.txt | wc -l
        command = %Command{
          name: :cmd_cat,
          args: ["data.txt"],
          pipes: [
            %Command{name: :cmd_wc, args: ["-l"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        result = Executor.run(command, sandbox_root: tmp_dir)

        assert {:ok, output} = result
        # Output should contain "5" (5 lines)
        assert output =~ "5"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "first command error stops pipeline" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-pipe-err-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # cat missing.txt | head -5 should error
        command = %Command{
          name: :cmd_cat,
          args: ["missing.txt"],
          pipes: [
            %Command{name: :cmd_head, args: ["-n", "5"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        result = Executor.run(command, sandbox_root: tmp_dir)

        assert {:error, msg} = result
        assert msg =~ "No such file or directory"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "middle command error stops pipeline" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-pipe-mid-err-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # echo ok | cat missing.txt | head -5
        # Middle command (cat missing.txt) should error and stop pipeline
        command = %Command{
          name: :cmd_echo,
          args: ["ok"],
          pipes: [
            %Command{name: :cmd_cat, args: ["missing.txt"], pipes: [], redirects: []},
            %Command{name: :cmd_head, args: ["-n", "5"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        result = Executor.run(command, sandbox_root: tmp_dir)

        assert {:error, msg} = result
        assert msg =~ "No such file or directory"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "middle command with no matches returns empty output" do
      tmp_dir = Path.join(System.tmp_dir!(), "truman-pipe-empty-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "data.txt"), "hello\nworld\n")

        # cat data.txt | grep nomatch | head -5
        command = %Command{
          name: :cmd_cat,
          args: ["data.txt"],
          pipes: [
            %Command{name: :cmd_grep, args: ["nomatch"], pipes: [], redirects: []},
            %Command{name: :cmd_head, args: ["-n", "5"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        result = Executor.run(command, sandbox_root: tmp_dir)

        # Empty output is OK (not an error)
        assert {:ok, ""} = result
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
