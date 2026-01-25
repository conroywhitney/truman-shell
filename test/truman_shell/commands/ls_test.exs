defmodule TrumanShell.Commands.LsTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.Ls
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  # Helper to build context
  defp build_ctx(current_path, sandbox_root \\ File.cwd!()) do
    config = %SandboxConfig{allowed_paths: [sandbox_root], home_path: sandbox_root}
    %Context{current_path: current_path, sandbox_config: config}
  end

  describe "handle/2" do
    test "lists files in current directory" do
      ctx = build_ctx(File.cwd!())

      {:ok, output} = Ls.handle([], ctx)

      assert output =~ "mix.exs"
    end

    test "lists files in specified directory" do
      ctx = build_ctx(File.cwd!())

      {:ok, output} = Ls.handle(["lib"], ctx)

      assert output =~ "truman_shell.ex"
    end

    test "appends / to directory names" do
      ctx = build_ctx(File.cwd!())

      {:ok, output} = Ls.handle([], ctx)

      assert output =~ "lib/"
      assert output =~ "test/"
    end

    test "returns error for non-existent directory" do
      ctx = build_ctx(File.cwd!())

      result = Ls.handle(["nonexistent_dir"], ctx)

      assert {:error, message} = result
      assert message == "ls: nonexistent_dir: No such file or directory\n"
    end

    test "rejects unsupported flags" do
      ctx = build_ctx(File.cwd!())

      result = Ls.handle(["-la"], ctx)

      assert {:error, message} = result
      assert message =~ "invalid option"
    end

    test "accepts multiple path arguments" do
      ctx = build_ctx(File.cwd!())

      result = Ls.handle(["lib", "test"], ctx)

      assert {:ok, output} = result
      # Should list contents of both directories
      assert output =~ "truman_shell"
      assert output =~ "test_helper"
    end

    test "rejects access to paths outside sandbox (404 principle)" do
      ctx = build_ctx(File.cwd!())

      result = Ls.handle(["/etc"], ctx)

      assert {:error, message} = result
      assert message =~ "No such file or directory"
      # Must NOT reveal that the path exists
      refute message =~ "permission"
    end

    test "truncates output for large directories" do
      tmp_dir =
        Path.join(Path.join(File.cwd!(), "tmp"), "truman-test-ls-truncation-#{:rand.uniform(100_000)}")

      File.mkdir_p!(tmp_dir)

      # Create 250 files (exceeds 200 line limit)
      for i <- 1..250 do
        File.write!(Path.join(tmp_dir, "file_#{String.pad_leading("#{i}", 3, "0")}.txt"), "")
      end

      try do
        ctx = build_ctx(tmp_dir, tmp_dir)
        {:ok, output} = Ls.handle(["."], ctx)

        assert output =~ "... (50 more entries, 250 total)"

        lines = String.split(output, "\n", trim: true)
        # 200 files + 1 truncation message
        assert length(lines) == 201
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
