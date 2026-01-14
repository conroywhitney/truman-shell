defmodule TrumanShell.Commands.CpTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Cp

  @moduletag :commands

  describe "handle/2" do
    setup do
      # Create a temp sandbox for each test
      sandbox = Path.join(System.tmp_dir!(), "cp_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)

      on_exit(fn -> File.rm_rf!(sandbox) end)

      context = %{sandbox_root: sandbox, current_dir: sandbox}
      {:ok, context: context, sandbox: sandbox}
    end

    test "copies a file", %{context: context, sandbox: sandbox} do
      # Create source file
      src = Path.join(sandbox, "src.txt")
      File.write!(src, "original content")

      result = Cp.handle(["src.txt", "dst.txt"], context)

      assert {:ok, ""} = result
      # Source still exists
      assert File.read!(src) == "original content"
      # Destination has same content
      assert File.read!(Path.join(sandbox, "dst.txt")) == "original content"
    end

    test "cp directory without -r returns error", %{context: context, sandbox: sandbox} do
      # Create a directory
      dir_path = Path.join(sandbox, "mydir")
      File.mkdir!(dir_path)

      result = Cp.handle(["mydir", "newdir"], context)

      assert {:error, "cp: -r not specified; omitting directory 'mydir'\n"} = result
    end

    test "cp -r copies directory recursively", %{context: context, sandbox: sandbox} do
      # Create a directory with content
      dir_path = Path.join(sandbox, "mydir")
      File.mkdir!(dir_path)
      File.write!(Path.join(dir_path, "inner.txt"), "inner content")

      result = Cp.handle(["-r", "mydir", "newdir"], context)

      assert {:ok, ""} = result
      # Original still exists
      assert File.dir?(dir_path)
      # Copy exists with content
      assert File.dir?(Path.join(sandbox, "newdir"))
      assert File.read!(Path.join(sandbox, "newdir/inner.txt")) == "inner content"
    end

    test "returns error for nonexistent source", %{context: context} do
      result = Cp.handle(["nonexistent.txt", "dest.txt"], context)

      assert {:error, "cp: nonexistent.txt: No such file or directory\n"} = result
    end

    test "blocks cp outside sandbox (404 principle)", %{context: context} do
      result = Cp.handle(["/etc/passwd", "stolen.txt"], context)

      assert {:error, "cp: /etc/passwd: No such file or directory\n"} = result
    end
  end
end
