defmodule TrumanShell.Commands.MvTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.Mv
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  describe "handle/2" do
    setup do
      # Create a temp sandbox for each test
      sandbox = Path.join(Path.join(File.cwd!(), "tmp"), "mv_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)

      on_exit(fn -> File.rm_rf!(sandbox) end)

      config = %SandboxConfig{allowed_paths: [sandbox], home_path: sandbox}
      ctx = %Context{current_path: sandbox, sandbox_config: config}
      {:ok, ctx: ctx, sandbox: sandbox}
    end

    test "renames a file", %{ctx: ctx, sandbox: sandbox} do
      # Create source file
      src = Path.join(sandbox, "old.txt")
      File.write!(src, "content")

      result = Mv.handle(["old.txt", "new.txt"], ctx)

      assert {:ok, ""} = result
      refute File.exists?(src)
      assert File.read!(Path.join(sandbox, "new.txt")) == "content"
    end

    test "moves file to subdirectory", %{ctx: ctx, sandbox: sandbox} do
      # Create source file and target directory
      File.write!(Path.join(sandbox, "file.txt"), "content")
      File.mkdir!(Path.join(sandbox, "subdir"))

      result = Mv.handle(["file.txt", "subdir/file.txt"], ctx)

      assert {:ok, ""} = result
      refute File.exists?(Path.join(sandbox, "file.txt"))
      assert File.read!(Path.join(sandbox, "subdir/file.txt")) == "content"
    end

    test "returns error for nonexistent source", %{ctx: ctx} do
      result = Mv.handle(["nonexistent.txt", "dest.txt"], ctx)

      assert {:error, "mv: nonexistent.txt: No such file or directory\n"} = result
    end

    test "returns error when destination directory does not exist", %{
      ctx: ctx,
      sandbox: sandbox
    } do
      # Create source file
      File.write!(Path.join(sandbox, "file.txt"), "content")

      result = Mv.handle(["file.txt", "nonexistent_dir/file.txt"], ctx)

      # Note: Error reports source file name (implementation choice, differs from bash)
      assert {:error, "mv: file.txt: No such file or directory\n"} = result
      # Source file should still exist (move failed)
      assert File.exists?(Path.join(sandbox, "file.txt"))
    end

    test "blocks mv outside sandbox (404 principle)", %{ctx: ctx} do
      result = Mv.handle(["/etc/passwd", "stolen.txt"], ctx)

      assert {:error, "mv: /etc/passwd: No such file or directory\n"} = result
    end
  end
end
