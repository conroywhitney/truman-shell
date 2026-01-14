defmodule TrumanShell.Commands.RmTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Rm

  @moduletag :commands

  describe "handle/2" do
    setup do
      # Create a temp sandbox for each test
      sandbox = Path.join(System.tmp_dir!(), "rm_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)
      # Create .trash directory
      trash_dir = Path.join(sandbox, ".trash")
      File.mkdir_p!(trash_dir)

      on_exit(fn -> File.rm_rf!(sandbox) end)

      context = %{sandbox_root: sandbox, current_dir: sandbox}
      {:ok, context: context, sandbox: sandbox, trash_dir: trash_dir}
    end

    test "soft deletes file to .trash", %{context: context, sandbox: sandbox, trash_dir: trash_dir} do
      # Create a file to delete
      file_path = Path.join(sandbox, "deleteme.txt")
      File.write!(file_path, "original content")

      result = Rm.handle(["deleteme.txt"], context)

      assert {:ok, ""} = result
      # File should no longer exist in original location
      refute File.exists?(file_path)
      # File should exist in .trash with timestamp prefix
      trash_files = File.ls!(trash_dir)
      assert length(trash_files) == 1
      [trash_file] = trash_files
      assert String.ends_with?(trash_file, "_deleteme.txt")
      # Content should be preserved
      trash_path = Path.join(trash_dir, trash_file)
      assert File.read!(trash_path) == "original content"
    end

    test "returns error for nonexistent file", %{context: context} do
      result = Rm.handle(["nonexistent.txt"], context)

      assert {:error, "rm: nonexistent.txt: No such file or directory\n"} = result
    end

    test "rm -f succeeds silently for nonexistent file", %{context: context} do
      result = Rm.handle(["-f", "nonexistent.txt"], context)

      assert {:ok, ""} = result
    end

    test "rm directory without -r returns error", %{context: context, sandbox: sandbox} do
      # Create a directory
      dir_path = Path.join(sandbox, "mydir")
      File.mkdir!(dir_path)

      result = Rm.handle(["mydir"], context)

      assert {:error, "rm: mydir: is a directory\n"} = result
      # Directory should still exist
      assert File.dir?(dir_path)
    end

    test "rm -r soft deletes directory", %{context: context, sandbox: sandbox, trash_dir: trash_dir} do
      # Create a directory with content
      dir_path = Path.join(sandbox, "mydir")
      File.mkdir!(dir_path)
      File.write!(Path.join(dir_path, "inner.txt"), "inner content")

      result = Rm.handle(["-r", "mydir"], context)

      assert {:ok, ""} = result
      # Directory should no longer exist in original location
      refute File.exists?(dir_path)
      # Directory should exist in .trash
      trash_files = File.ls!(trash_dir)
      assert length(trash_files) == 1
      [trash_dir_name] = trash_files
      assert String.ends_with?(trash_dir_name, "_mydir")
    end

    test "blocks rm outside sandbox (404 principle)", %{context: context} do
      result = Rm.handle(["/etc/passwd"], context)

      assert {:error, "rm: /etc/passwd: No such file or directory\n"} = result
    end
  end
end
