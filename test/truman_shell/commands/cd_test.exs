defmodule TrumanShell.Commands.CdTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Cd

  @moduletag :commands

  describe "handle/2" do
    test "changes to subdirectory and returns set_cwd" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      {:ok, "", set_cwd: new_dir} = Cd.handle(["lib"], context)

      assert String.ends_with?(new_dir, "/lib")
    end

    test "changes to nested subdirectory" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      {:ok, "", set_cwd: new_dir} = Cd.handle(["lib/truman_shell"], context)

      assert String.ends_with?(new_dir, "/lib/truman_shell")
    end

    test "returns to sandbox root with no args" do
      sandbox_root = File.cwd!()
      current = Path.join(sandbox_root, "lib/truman_shell")
      context = %{sandbox_root: sandbox_root, current_dir: current}

      {:ok, "", set_cwd: new_dir} = Cd.handle([], context)

      assert new_dir == sandbox_root
    end

    test "returns to sandbox root with ~" do
      sandbox_root = File.cwd!()
      current = Path.join(sandbox_root, "lib/truman_shell")
      context = %{sandbox_root: sandbox_root, current_dir: current}

      {:ok, "", set_cwd: new_dir} = Cd.handle(["~"], context)

      assert new_dir == sandbox_root
    end

    test "returns to sandbox root with ~/ (trailing slash)" do
      sandbox_root = File.cwd!()
      current = Path.join(sandbox_root, "lib/truman_shell")
      context = %{sandbox_root: sandbox_root, current_dir: current}

      {:ok, "", set_cwd: new_dir} = Cd.handle(["~/"], context)

      assert new_dir == sandbox_root
    end

    test "expands ~/subdir to sandbox_root/subdir" do
      sandbox_root = File.cwd!()
      current = Path.join(sandbox_root, "lib/truman_shell")
      context = %{sandbox_root: sandbox_root, current_dir: current}

      {:ok, "", set_cwd: new_dir} = Cd.handle(["~/lib"], context)

      assert new_dir == Path.join(sandbox_root, "lib")
    end

    test "returns error for ~/nonexistent" do
      sandbox_root = File.cwd!()
      context = %{sandbox_root: sandbox_root, current_dir: sandbox_root}

      result = Cd.handle(["~/nonexistent"], context)

      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
    end

    test "navigates up with .." do
      sandbox_root = File.cwd!()
      current = Path.join(sandbox_root, "lib/truman_shell")
      context = %{sandbox_root: sandbox_root, current_dir: current}

      {:ok, "", set_cwd: new_dir} = Cd.handle([".."], context)

      assert new_dir == Path.join(sandbox_root, "lib")
    end

    test "returns error when .. would escape sandbox" do
      sandbox_root = File.cwd!()
      context = %{sandbox_root: sandbox_root, current_dir: sandbox_root}

      result = Cd.handle([".."], context)

      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
    end

    test "returns error for non-existent directory" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Cd.handle(["nonexistent"], context)

      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
    end

    test "rejects absolute paths outside sandbox (404 principle)" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Cd.handle(["/etc"], context)

      assert {:error, msg} = result
      assert msg =~ "No such file or directory"
      # Must NOT reveal that the path exists
      refute msg =~ "permission"
      refute msg =~ "Permission"
    end

    test "returns error for file (not directory)" do
      context = %{sandbox_root: File.cwd!(), current_dir: File.cwd!()}

      result = Cd.handle(["mix.exs"], context)

      assert {:error, msg} = result
      assert msg =~ "Not a directory"
    end
  end
end
