defmodule TrumanShell.Commands.MvTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Mv

  @moduletag :commands

  describe "handle/2" do
    setup do
      # Create a temp sandbox for each test
      sandbox = Path.join(System.tmp_dir!(), "mv_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)

      on_exit(fn -> File.rm_rf!(sandbox) end)

      context = %{sandbox_root: sandbox, current_dir: sandbox}
      {:ok, context: context, sandbox: sandbox}
    end

    test "renames a file", %{context: context, sandbox: sandbox} do
      # Create source file
      src = Path.join(sandbox, "old.txt")
      File.write!(src, "content")

      result = Mv.handle(["old.txt", "new.txt"], context)

      assert {:ok, ""} = result
      refute File.exists?(src)
      assert File.read!(Path.join(sandbox, "new.txt")) == "content"
    end

    test "moves file to subdirectory", %{context: context, sandbox: sandbox} do
      # Create source file and target directory
      File.write!(Path.join(sandbox, "file.txt"), "content")
      File.mkdir!(Path.join(sandbox, "subdir"))

      result = Mv.handle(["file.txt", "subdir/file.txt"], context)

      assert {:ok, ""} = result
      refute File.exists?(Path.join(sandbox, "file.txt"))
      assert File.read!(Path.join(sandbox, "subdir/file.txt")) == "content"
    end

    test "returns error for nonexistent source", %{context: context} do
      result = Mv.handle(["nonexistent.txt", "dest.txt"], context)

      assert {:error, "mv: nonexistent.txt: No such file or directory\n"} = result
    end

    test "blocks mv outside sandbox (404 principle)", %{context: context} do
      result = Mv.handle(["/etc/passwd", "stolen.txt"], context)

      assert {:error, "mv: /etc/passwd: No such file or directory\n"} = result
    end
  end
end
