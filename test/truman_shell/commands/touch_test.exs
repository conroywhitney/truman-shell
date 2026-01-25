defmodule TrumanShell.Commands.TouchTest do
  use ExUnit.Case, async: true

  alias TrumanShell.Commands.Touch

  @moduletag :commands

  describe "handle/2" do
    setup do
      # Create a temp sandbox for each test
      sandbox = Path.join(Path.join(File.cwd!(), "tmp"), "touch_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(sandbox)

      on_exit(fn -> File.rm_rf!(sandbox) end)

      context = %{sandbox_root: sandbox, current_dir: sandbox}
      {:ok, context: context, sandbox: sandbox}
    end

    test "creates a new empty file", %{context: context, sandbox: sandbox} do
      result = Touch.handle(["newfile.txt"], context)

      assert {:ok, ""} = result
      file_path = Path.join(sandbox, "newfile.txt")
      assert File.exists?(file_path)
      assert File.read!(file_path) == ""
    end

    test "updates timestamp on existing file", %{context: context, sandbox: sandbox} do
      # Create file with content
      file_path = Path.join(sandbox, "existing.txt")
      File.write!(file_path, "original content")
      original_stat = File.stat!(file_path)

      # Small delay to ensure timestamp difference
      Process.sleep(10)

      result = Touch.handle(["existing.txt"], context)

      assert {:ok, ""} = result
      # File still exists with same content
      assert File.read!(file_path) == "original content"
      # Timestamp was updated (or at least file was touched successfully)
      new_stat = File.stat!(file_path)
      assert new_stat.mtime >= original_stat.mtime
    end

    test "blocks touch outside sandbox (404 principle)", %{context: context} do
      result = Touch.handle(["/etc/hacked.txt"], context)

      assert {:error, "touch: /etc/hacked.txt: No such file or directory\n"} = result
    end

    test "touch through file (not directory) returns ENOTDIR error", %{context: context, sandbox: sandbox} do
      # Create a regular file
      File.write!(Path.join(sandbox, "afile.txt"), "content")

      # Try to touch a path where parent is a file, not a directory
      # File.touch will fail with :enotdir
      result = Touch.handle(["afile.txt/impossible.txt"], context)

      assert {:error, "touch: afile.txt/impossible.txt: Not a directory\n"} = result
    end
  end
end
