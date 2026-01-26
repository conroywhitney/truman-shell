defmodule TrumanShell.Commands.CpTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Context
  alias TrumanShell.Commands.Cp
  alias TrumanShell.Config.Sandbox, as: SandboxConfig

  @moduletag :commands

  describe "handle/2" do
    setup do
      # Create a temp sandbox for each test
      sandbox = Path.join(Path.join(File.cwd!(), "tmp"), "cp_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)

      on_exit(fn -> File.rm_rf!(sandbox) end)

      config = %SandboxConfig{allowed_paths: [sandbox], home_path: sandbox}
      ctx = %Context{current_path: sandbox, sandbox_config: config}
      {:ok, ctx: ctx, sandbox: sandbox}
    end

    test "copies a file", %{ctx: ctx, sandbox: sandbox} do
      # Create source file
      src = Path.join(sandbox, "src.txt")
      File.write!(src, "original content")

      result = Cp.handle(["src.txt", "dst.txt"], ctx)

      assert {:ok, ""} = result
      # Source still exists
      assert File.read!(src) == "original content"
      # Destination has same content
      assert File.read!(Path.join(sandbox, "dst.txt")) == "original content"
    end

    test "cp directory without -r returns error", %{ctx: ctx, sandbox: sandbox} do
      # Create a directory
      dir_path = Path.join(sandbox, "mydir")
      File.mkdir!(dir_path)

      result = Cp.handle(["mydir", "newdir"], ctx)

      assert {:error, "cp: -r not specified; omitting directory 'mydir'\n"} = result
    end

    test "cp -r copies directory recursively", %{ctx: ctx, sandbox: sandbox} do
      # Create a directory with content
      dir_path = Path.join(sandbox, "mydir")
      File.mkdir!(dir_path)
      File.write!(Path.join(dir_path, "inner.txt"), "inner content")

      result = Cp.handle(["-r", "mydir", "newdir"], ctx)

      assert {:ok, ""} = result
      # Original still exists
      assert File.dir?(dir_path)
      # Copy exists with content
      assert File.dir?(Path.join(sandbox, "newdir"))
      assert File.read!(Path.join(sandbox, "newdir/inner.txt")) == "inner content"
    end

    test "returns error for nonexistent source", %{ctx: ctx} do
      result = Cp.handle(["nonexistent.txt", "dest.txt"], ctx)

      assert {:error, "cp: nonexistent.txt: No such file or directory\n"} = result
    end

    test "returns error when destination directory does not exist", %{
      ctx: ctx,
      sandbox: sandbox
    } do
      # Create source file
      File.write!(Path.join(sandbox, "file.txt"), "content")

      result = Cp.handle(["file.txt", "nonexistent_dir/file.txt"], ctx)

      # Note: Error reports source file name (implementation choice, differs from bash)
      assert {:error, "cp: file.txt: No such file or directory\n"} = result
      # Source file should still exist
      assert File.exists?(Path.join(sandbox, "file.txt"))
    end

    test "blocks cp outside sandbox (404 principle)", %{ctx: ctx} do
      result = Cp.handle(["/etc/passwd", "stolen.txt"], ctx)

      assert {:error, "cp: /etc/passwd: No such file or directory\n"} = result
    end
  end
end
