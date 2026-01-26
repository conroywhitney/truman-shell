defmodule TrumanShell.Stages.ExecutorTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Command
  alias TrumanShell.Commands.Context
  alias TrumanShell.Config.Sandbox, as: SandboxConfig
  alias TrumanShell.Stages.Executor

  # Default ctx using File.cwd!()
  defp default_ctx(opts \\ []) do
    build_ctx(File.cwd!(), opts)
  end

  # Helper to build ctx with home_path as both home and current_path
  defp build_ctx(home_path, opts \\ []) do
    config = %SandboxConfig{allowed_paths: [home_path], home_path: home_path}
    current_path = Keyword.get(opts, :current_path, home_path)
    stdin = Keyword.get(opts, :stdin)
    %Context{current_path: current_path, sandbox_config: config, stdin: stdin}
  end

  describe "run/2" do
    test "passes stdin in ctx to first command" do
      command = %Command{name: :cmd_head, args: ["-n", "2"], pipes: [], redirects: []}
      ctx = default_ctx(stdin: "line 1\nline 2\nline 3\n")

      result = Executor.run(command, ctx)

      assert {:ok, output} = result
      assert output == "line 1\nline 2\n"
    end

    test "passes stdin to first command even with pipes" do
      command = %Command{
        name: :cmd_head,
        args: ["-n", "2"],
        pipes: [
          %Command{name: :cmd_wc, args: ["-l"], pipes: [], redirects: []}
        ],
        redirects: []
      }

      ctx = default_ctx(stdin: "line 1\nline 2\nline 3\nline 4\n")

      result = Executor.run(command, ctx)

      assert {:ok, output} = result
      assert output =~ "2"
    end

    test "executes a valid command and returns {:ok, output}" do
      command = %Command{name: :cmd_ls, args: [], pipes: [], redirects: []}
      ctx = default_ctx()

      result = Executor.run(command, ctx)

      assert {:ok, output} = result
      assert is_binary(output)
    end

    test "returns error for unknown command" do
      command = %Command{name: {:unknown, "xyz"}, args: [], pipes: [], redirects: []}
      ctx = default_ctx()

      result = Executor.run(command, ctx)

      assert {:error, message} = result
      assert message == "bash: xyz: command not found\n"
    end

    test "uses sandbox from ctx" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-sandbox-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "test.txt"), "content")

      try do
        command = %Command{name: :cmd_ls, args: [], pipes: [], redirects: []}
        ctx = build_ctx(tmp_dir)
        {:ok, output} = Executor.run(command, ctx)

        assert output =~ "test.txt"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "cd updates ctx.current_path for subsequent commands in pipeline" do
      # This tests that cd returns updated ctx and it flows through pipeline
      # cd lib && pwd should show lib (but we can't chain like that)
      # Instead test via TrumanShell.execute which manages ctx internally
      home_path = File.cwd!()
      ctx = build_ctx(home_path)

      cd_cmd = %Command{name: :cmd_cd, args: ["lib"], pipes: [], redirects: []}
      {:ok, ""} = Executor.run(cd_cmd, ctx)

      # The returned ctx would have updated current_path, but since run/2
      # doesn't return ctx, we test through the full pipeline
    end
  end

  describe "command dispatch" do
    # Smoke tests verifying each command is wired up correctly
    # Detailed behavior tests are in test/truman_shell/commands/*_test.exs

    test "dispatches :cmd_ls to Commands.Ls" do
      command = %Command{name: :cmd_ls, args: ["lib"], pipes: [], redirects: []}
      ctx = default_ctx()

      {:ok, output} = Executor.run(command, ctx)

      assert output =~ "truman_shell"
    end

    test "dispatches :cmd_pwd to Commands.Pwd" do
      command = %Command{name: :cmd_pwd, args: [], pipes: [], redirects: []}
      ctx = default_ctx()

      {:ok, output} = Executor.run(command, ctx)

      assert output == File.cwd!() <> "\n"
    end

    test "dispatches :cmd_cd to Commands.Cd" do
      home_path = File.cwd!()
      ctx = build_ctx(home_path)

      cd_cmd = %Command{name: :cmd_cd, args: ["lib"], pipes: [], redirects: []}

      assert {:ok, ""} = Executor.run(cd_cmd, ctx)
    end

    test "dispatches :cmd_cat to Commands.Cat" do
      ctx = default_ctx()
      command = %Command{name: :cmd_cat, args: ["mix.exs"], pipes: [], redirects: []}

      {:ok, output} = Executor.run(command, ctx)

      assert output =~ "defmodule TrumanShell.MixProject"
    end

    test "dispatches :cmd_head to Commands.Head" do
      command = %Command{name: :cmd_head, args: ["-n", "1", "mix.exs"], pipes: [], redirects: []}
      ctx = default_ctx()

      {:ok, output} = Executor.run(command, ctx)

      assert output == "defmodule TrumanShell.MixProject do\n"
    end

    test "dispatches :cmd_tail to Commands.Tail" do
      command = %Command{name: :cmd_tail, args: ["-n", "1", "mix.exs"], pipes: [], redirects: []}
      ctx = default_ctx()

      {:ok, output} = Executor.run(command, ctx)

      assert output == "end\n"
    end

    test "dispatches :cmd_echo to Commands.Echo" do
      command = %Command{name: :cmd_echo, args: ["hello", "world"], pipes: [], redirects: []}
      ctx = default_ctx()

      {:ok, output} = Executor.run(command, ctx)

      assert output == "hello world\n"
    end
  end

  describe "depth limits" do
    test "accepts command within depth limit" do
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

      ctx = default_ctx()

      result = Executor.run(command, ctx)

      assert {:ok, _output} = result
    end

    test "accepts exactly 10 stages (boundary)" do
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

      ctx = default_ctx()

      result = Executor.run(command, ctx)

      assert {:ok, _output} = result
    end

    test "rejects 11 stages (exceeds limit)" do
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

      ctx = default_ctx()

      result = Executor.run(command, ctx)

      assert {:error, message} = result
      assert message =~ "pipeline too deep"
      assert message =~ "11 commands"
    end

    test "rejects command exceeding depth limit" do
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

      ctx = default_ctx()

      result = Executor.run(command, ctx)

      assert {:error, message} = result
      assert message =~ "pipeline too deep"
      assert message =~ "16 commands"
    end
  end

  describe "redirects" do
    test "stdout redirect (>) writes output to file" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-redirect-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        command = %Command{
          name: :cmd_echo,
          args: ["hello"],
          pipes: [],
          redirects: [stdout: "output.txt"]
        }

        ctx = build_ctx(tmp_dir)

        {:ok, output} = Executor.run(command, ctx)

        assert output == ""
        file_path = Path.join(tmp_dir, "output.txt")
        assert File.exists?(file_path)
        assert File.read!(file_path) == "hello\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "stdout append redirect (>>) appends to file" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-append-#{:rand.uniform(100_000)}")
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

        ctx = build_ctx(tmp_dir)

        {:ok, output} = Executor.run(command, ctx)

        assert output == ""
        assert File.read!(file_path) == "first\nsecond\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "redirect to path outside sandbox returns error (404 principle)" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-sandbox-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        command = %Command{
          name: :cmd_echo,
          args: ["sneaky"],
          pipes: [],
          redirects: [stdout: "/etc/passwd"]
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

        assert {:error, message} = result
        assert message =~ "No such file or directory"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "redirect to directory returns error (not crash)" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-eisdir-#{:rand.uniform(100_000)}")
      subdir = Path.join(tmp_dir, "subdir")
      File.mkdir_p!(subdir)

      try do
        command = %Command{
          name: :cmd_echo,
          args: ["test"],
          pipes: [],
          redirects: [stdout: "subdir"]
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

        assert {:error, message} = result
        assert message =~ "Is a directory"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "redirect to nonexistent parent directory returns error (ENOENT)" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-enoent-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        command = %Command{
          name: :cmd_echo,
          args: ["test"],
          pipes: [],
          redirects: [stdout: "nonexistent/output.txt"]
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

        assert {:error, message} = result
        assert message =~ "No such file or directory"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "multiple redirects: last file gets output, earlier files truncated (bash behavior)" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-multi-redir-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        command = %Command{
          name: :cmd_echo,
          args: ["hello"],
          pipes: [],
          redirects: [stdout: "a.txt", stdout: "b.txt"]
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

        assert {:ok, ""} = result
        assert File.exists?(Path.join(tmp_dir, "a.txt"))
        assert File.exists?(Path.join(tmp_dir, "b.txt"))
        assert File.read!(Path.join(tmp_dir, "a.txt")) == ""
        assert File.read!(Path.join(tmp_dir, "b.txt")) == "hello\n"
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "piping" do
    test "ls | grep pattern filters directory output" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-pipe-ls-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "test_file.txt"), "")
        File.write!(Path.join(tmp_dir, "other_file.txt"), "")
        File.write!(Path.join(tmp_dir, "readme.md"), "")

        command = %Command{
          name: :cmd_ls,
          args: [],
          pipes: [
            %Command{name: :cmd_grep, args: ["test"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

        assert {:ok, output} = result
        assert output =~ "test_file.txt"
        refute output =~ "other_file.txt"
        refute output =~ "readme.md"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "cat file.txt | head -5 returns first 5 lines" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-pipe-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        content = Enum.map_join(1..10, "\n", &"line #{&1}")
        File.write!(Path.join(tmp_dir, "data.txt"), content <> "\n")

        command = %Command{
          name: :cmd_cat,
          args: ["data.txt"],
          pipes: [
            %Command{name: :cmd_head, args: ["-n", "5"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

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
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-pipe-3-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
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

        command = %Command{
          name: :cmd_cat,
          args: ["fruits.txt"],
          pipes: [
            %Command{name: :cmd_grep, args: ["apple"], pipes: [], redirects: []},
            %Command{name: :cmd_head, args: ["-n", "3"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

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
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-pipe-tail-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        content = Enum.map_join(1..10, "\n", &"line #{&1}")
        File.write!(Path.join(tmp_dir, "data.txt"), content <> "\n")

        command = %Command{
          name: :cmd_cat,
          args: ["data.txt"],
          pipes: [
            %Command{name: :cmd_tail, args: ["-n", "3"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

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
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-pipe-wc-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        content = Enum.map_join(1..5, "\n", &"line #{&1}")
        File.write!(Path.join(tmp_dir, "data.txt"), content <> "\n")

        command = %Command{
          name: :cmd_cat,
          args: ["data.txt"],
          pipes: [
            %Command{name: :cmd_wc, args: ["-l"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

        assert {:ok, output} = result
        assert output =~ "5"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "first command error stops pipeline" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-pipe-err-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        command = %Command{
          name: :cmd_cat,
          args: ["missing.txt"],
          pipes: [
            %Command{name: :cmd_head, args: ["-n", "5"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

        assert {:error, msg} = result
        assert msg =~ "No such file or directory"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "middle command error stops pipeline" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-pipe-mid-err-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        command = %Command{
          name: :cmd_echo,
          args: ["ok"],
          pipes: [
            %Command{name: :cmd_cat, args: ["missing.txt"], pipes: [], redirects: []},
            %Command{name: :cmd_head, args: ["-n", "5"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

        assert {:error, msg} = result
        assert msg =~ "No such file or directory"
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "middle command with no matches returns empty output" do
      tmp_dir = Path.join(Path.join(File.cwd!(), "tmp"), "truman-pipe-empty-#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        File.write!(Path.join(tmp_dir, "data.txt"), "hello\nworld\n")

        command = %Command{
          name: :cmd_cat,
          args: ["data.txt"],
          pipes: [
            %Command{name: :cmd_grep, args: ["nomatch"], pipes: [], redirects: []},
            %Command{name: :cmd_head, args: ["-n", "5"], pipes: [], redirects: []}
          ],
          redirects: []
        }

        ctx = build_ctx(tmp_dir)

        result = Executor.run(command, ctx)

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
